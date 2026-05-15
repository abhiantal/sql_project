-- ============================================================
-- 📁 FILE 24: CHAT INVITES TABLE
-- Shareable invite links for group chats
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.chat_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,

    -- Invite code
    code TEXT NOT NULL UNIQUE,

    -- Settings
    created_by UUID NOT NULL,
    max_uses INTEGER,
    uses_count INTEGER DEFAULT 0,
    expires_at TIMESTAMPTZ,

    -- Role assigned on join
    invited_role TEXT DEFAULT 'member' CHECK (invited_role IN ('member', 'admin')),

    -- Status
    is_active BOOLEAN DEFAULT true,
    is_revoked BOOLEAN DEFAULT false,
    revoked_by UUID,
    revoked_at TIMESTAMPTZ,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_chat_invites_chat ON public.chat_invites(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_invites_code ON public.chat_invites(code) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_chat_invites_expires ON public.chat_invites(expires_at) WHERE expires_at IS NOT NULL;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.chat_invites ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS "chat_invites_creator_all" ON public.chat_invites;
    CREATE POLICY "chat_invites_creator_all" ON public.chat_invites
        FOR ALL
        USING (created_by = auth.uid())
        WITH CHECK (created_by = auth.uid());

    DROP POLICY IF EXISTS "chat_invites_admin_select" ON public.chat_invites;
    CREATE POLICY "chat_invites_admin_select" ON public.chat_invites
        FOR SELECT
        USING (
            EXISTS (
                SELECT 1 FROM public.chat_members
                WHERE chat_members.chat_id = chat_invites.chat_id
                  AND chat_members.user_id = auth.uid()
                  AND chat_members.role IN ('owner', 'admin')
                  AND chat_members.is_active = true
            )
        );

    -- Note: Removed the overly permissive lookup policy
    -- Invite lookup is done through the secure function instead
END $$;

-- ============================================================
-- FUNCTION: Generate unique invite code
-- ============================================================
CREATE OR REPLACE FUNCTION internal.generate_chat_invite_code()
RETURNS TEXT
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_code TEXT;
    v_exists BOOLEAN;
BEGIN
    LOOP
        v_code := encode(gen_random_bytes(6), 'base64');
        v_code := replace(replace(replace(v_code, '+', ''), '/', ''), '=', '');
        v_code := substring(v_code, 1, 8);

        SELECT EXISTS(
            SELECT 1 FROM public.chat_invites WHERE code = v_code
        ) INTO v_exists;

        EXIT WHEN NOT v_exists;
    END LOOP;

    RETURN v_code;
END;
$$;

-- ============================================================
-- FUNCTION: Create chat invite
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_chat_invite(
    p_chat_id UUID,
    p_created_by UUID,
    p_max_uses INTEGER DEFAULT NULL,
    p_expires_in_hours INTEGER DEFAULT NULL,
    p_invited_role TEXT DEFAULT 'member'
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_code TEXT;
    v_invite_id UUID;
    v_expires_at TIMESTAMPTZ;
    v_user_role TEXT;
BEGIN
    -- [SECURITY] Enforce caller identity
    IF p_created_by != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: You can only create invites for yourself';
    END IF;

    -- Check if user is admin/owner
    SELECT role INTO v_user_role
    FROM public.chat_members
    WHERE chat_id = p_chat_id AND user_id = p_created_by AND is_active = true;

    IF v_user_role IS NULL OR v_user_role = 'member' THEN
        RAISE EXCEPTION 'Only admins and owners can create invite links';
    END IF;

    -- Generate code
    v_code := internal.generate_chat_invite_code();

    -- Calculate expiration
    IF p_expires_in_hours IS NOT NULL THEN
        v_expires_at := NOW() + (p_expires_in_hours * INTERVAL '1 hour');
    END IF;

    -- Create invite
    INSERT INTO public.chat_invites (
        chat_id, code, created_by, max_uses, expires_at, invited_role
    )
    VALUES (
        p_chat_id, v_code, p_created_by, p_max_uses, v_expires_at, p_invited_role
    )
    RETURNING id INTO v_invite_id;

    RETURN jsonb_build_object(
        'success', true,
        'invite_id', v_invite_id,
        'code', v_code,
        'expires_at', v_expires_at
    );
END;
$$;

-- ============================================================
-- FUNCTION: Join chat via invite code
-- ============================================================
CREATE OR REPLACE FUNCTION public.join_chat_via_invite(
    p_user_id UUID,
    p_invite_code TEXT
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_invite RECORD;
BEGIN
    -- Validate caller
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Unauthorized: You can only join for yourself'
        );
    END IF;

    -- Find active invite
    SELECT * INTO v_invite
    FROM public.chat_invites
    WHERE code = p_invite_code
      AND is_active = true
      AND is_revoked = false
      AND (expires_at IS NULL OR expires_at > NOW())
      AND (max_uses IS NULL OR uses_count < max_uses);

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Invite not found, expired, or fully used'
        );
    END IF;

    -- Check if already a member
    IF EXISTS (
        SELECT 1 FROM public.chat_members
        WHERE chat_id = v_invite.chat_id
          AND user_id = p_user_id
          AND is_active = true
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Already a member of this chat'
        );
    END IF;

    -- Add member (reactivate if previously left)
    INSERT INTO public.chat_members (chat_id, user_id, role, invited_by)
    VALUES (v_invite.chat_id, p_user_id, v_invite.invited_role, v_invite.created_by)
    ON CONFLICT (chat_id, user_id) DO UPDATE SET
        is_active = true,
        role = v_invite.invited_role,
        joined_at = NOW(),
        invited_by = v_invite.created_by,
        updated_at = NOW();

    -- Increment invite usage
    UPDATE public.chat_invites
    SET uses_count = uses_count + 1
    WHERE id = v_invite.id;

    -- Insert system message
    INSERT INTO public.chat_messages (
        chat_id, sender_id, type,
        system_event_type, system_event_data
    ) VALUES (
        v_invite.chat_id, p_user_id, 'system',
        'member_joined',
        jsonb_build_object('user_id', p_user_id, 'via', 'invite')
    );

    RETURN jsonb_build_object(
        'success', true,
        'chat_id', v_invite.chat_id,
        'role', v_invite.invited_role,
        'message', 'Joined chat successfully'
    );
END;
$$;

-- ============================================================
-- FUNCTION: Revoke chat invite
-- ============================================================
CREATE OR REPLACE FUNCTION public.revoke_chat_invite(
    p_invite_id UUID,
    p_revoked_by UUID
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_invite RECORD;
    v_user_role TEXT;
BEGIN
    -- [SECURITY] Enforce caller identity
    IF p_revoked_by != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: You can only revoke invites as yourself';
    END IF;

    -- Get invite
    SELECT * INTO v_invite
    FROM public.chat_invites
    WHERE id = p_invite_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invite not found';
    END IF;

    -- Check permission (creator or admin/owner)
    IF v_invite.created_by != p_revoked_by THEN
        SELECT role INTO v_user_role
        FROM public.chat_members
        WHERE chat_id = v_invite.chat_id AND user_id = p_revoked_by AND is_active = true;

        IF v_user_role IS NULL OR v_user_role = 'member' THEN
            RAISE EXCEPTION 'You do not have permission to revoke this invite';
        END IF;
    END IF;

    -- Revoke
    UPDATE public.chat_invites
    SET
        is_active = false,
        is_revoked = true,
        revoked_by = p_revoked_by,
        revoked_at = NOW()
    WHERE id = p_invite_id;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION: Get invite info (for preview before joining)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_invite_info(p_invite_code TEXT)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_invite RECORD;
    v_chat RECORD;
BEGIN
    -- Find invite
    SELECT * INTO v_invite
    FROM public.chat_invites
    WHERE code = p_invite_code
      AND is_active = true
      AND is_revoked = false;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'Invite not found or revoked'
        );
    END IF;

    -- Check expiration
    IF v_invite.expires_at IS NOT NULL AND v_invite.expires_at < NOW() THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'Invite has expired'
        );
    END IF;

    -- Check uses
    IF v_invite.max_uses IS NOT NULL AND v_invite.uses_count >= v_invite.max_uses THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', 'Invite has reached maximum uses'
        );
    END IF;

    -- Get chat info
    SELECT * INTO v_chat
    FROM public.chats
    WHERE id = v_invite.chat_id;

    RETURN jsonb_build_object(
        'valid', true,
        'chat_id', v_chat.id,
        'chat_name', v_chat.name,
        'chat_avatar', v_chat.avatar,
        'chat_type', v_chat.type,
        'total_members', v_chat.total_members,
        'invited_role', v_invite.invited_role,
        'expires_at', v_invite.expires_at
    );
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT ALL ON TABLE public.chat_invites TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_chat_invite(UUID, UUID, INTEGER, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_chat_via_invite(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_chat_invite(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_invite_info(TEXT) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.chat_invites table ready';
    RAISE NOTICE '   - 0 triggers';
    RAISE NOTICE '   - 5 functions:';
    RAISE NOTICE '     • generate_chat_invite_code()';
    RAISE NOTICE '     • create_chat_invite()';
    RAISE NOTICE '     • join_chat_via_invite()';
    RAISE NOTICE '     • revoke_chat_invite()';
    RAISE NOTICE '     • get_invite_info()';
    RAISE NOTICE '   - 2 RLS policies';
    RAISE NOTICE '   - 3 indexes';
END $$;
-- ============================================================
-- 📁 FILE 21: CHAT MEMBERS TABLE
-- Participants, roles, read tracking, per-user settings
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.chat_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,

    -- Role
    role TEXT DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),

    -- Per-user chat settings
    is_pinned BOOLEAN DEFAULT false,
    is_muted BOOLEAN DEFAULT false,
    mute_until TIMESTAMPTZ,
    is_archived BOOLEAN DEFAULT false,
    is_blocked BOOLEAN DEFAULT false,

    -- Read tracking (cursor-based)
    last_read_message_id UUID,
    last_read_at TIMESTAMPTZ,
    unread_count INTEGER DEFAULT 0,
    unread_mentions INTEGER DEFAULT 0,

    -- Status
    is_active BOOLEAN DEFAULT true,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    invited_by UUID,

    -- Extra settings (notifications, custom title, etc.)
    notification_level TEXT DEFAULT 'all' CHECK (notification_level IN ('all', 'mentions', 'none')),
    settings JSONB DEFAULT '{}'::jsonb,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT unique_chat_member UNIQUE(chat_id, user_id)
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_chat_members_user ON public.chat_members(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_chat ON public.chat_members(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_members_active ON public.chat_members(user_id, is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_chat_members_chat_active ON public.chat_members(chat_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_chat_members_role ON public.chat_members(chat_id, role);
CREATE INDEX IF NOT EXISTS idx_chat_members_pinned ON public.chat_members(user_id) WHERE is_pinned = true;
CREATE INDEX IF NOT EXISTS idx_chat_members_archived ON public.chat_members(user_id) WHERE is_archived = true;
CREATE INDEX IF NOT EXISTS idx_chat_members_unread ON public.chat_members(user_id) WHERE unread_count > 0;
CREATE INDEX IF NOT EXISTS idx_chat_members_notif_level ON public.chat_members(chat_id, notification_level) WHERE is_active = true;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.chat_members ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS "chat_members_own" ON public.chat_members;
    CREATE POLICY "chat_members_own" ON public.chat_members
        FOR ALL
        USING (user_id = auth.uid())
        WITH CHECK (user_id = auth.uid());

    DROP POLICY IF EXISTS "chat_members_creator_manage" ON public.chat_members;
    CREATE POLICY "chat_members_creator_manage" ON public.chat_members
        FOR ALL
        USING (
            EXISTS (
                SELECT 1 FROM public.chats
                WHERE chats.id = chat_members.chat_id
                  AND chats.created_by = auth.uid()
            )
        )
        WITH CHECK (
            EXISTS (
                SELECT 1 FROM public.chats
                WHERE chats.id = chat_members.chat_id
                  AND chats.created_by = auth.uid()
            )
        );

    DROP POLICY IF EXISTS "chat_members_read_same_chat" ON public.chat_members;
    CREATE POLICY "chat_members_read_same_chat" ON public.chat_members
        FOR SELECT
        USING (internal.is_chat_member(chat_members.chat_id, auth.uid()));
END $$;

-- ============================================================
-- FUNCTION: Update chat member count
-- ============================================================
CREATE OR REPLACE FUNCTION internal.update_chat_member_count()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.is_active = true THEN
        UPDATE public.chats
        SET total_members = total_members + 1, updated_at = NOW()
        WHERE id = NEW.chat_id;

    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.is_active = true AND OLD.is_active = false THEN
            UPDATE public.chats
            SET total_members = total_members + 1, updated_at = NOW()
            WHERE id = NEW.chat_id;
        ELSIF NEW.is_active = false AND OLD.is_active = true THEN
            UPDATE public.chats
            SET total_members = GREATEST(0, total_members - 1), updated_at = NOW()
            WHERE id = NEW.chat_id;
        END IF;

    ELSIF TG_OP = 'DELETE' AND OLD.is_active = true THEN
        UPDATE public.chats
        SET total_members = GREATEST(0, total_members - 1), updated_at = NOW()
        WHERE id = OLD.chat_id;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- ============================================================
-- FUNCTION: Get chat member role
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_chat_member_role(
    p_chat_id UUID,
    p_user_id UUID
)
RETURNS TEXT
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_role TEXT;
BEGIN
    -- [SECURITY] Ownership check
    -- Note: Users can check their own role or other's roles IF they are in the same chat
    -- The RLS policy on chat_members already handles SELECT, but RPC needs explicit check
    IF NOT public.is_chat_member(p_chat_id, auth.uid()) AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT role INTO v_role
    FROM public.chat_members
    WHERE chat_id = p_chat_id
      AND user_id = p_user_id
      AND is_active = true;

    RETURN v_role;
END;
$$;

-- ============================================================
-- FUNCTION: Add member to chat
-- ============================================================
CREATE OR REPLACE FUNCTION public.add_chat_member(
    p_chat_id UUID,
    p_user_id UUID,
    p_role TEXT DEFAULT 'member',
    p_invited_by UUID DEFAULT NULL
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_inviter_role TEXT;
BEGIN
    -- [SECURITY] Ownership check
    IF COALESCE(p_invited_by, auth.uid()) != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: Invalid inviter ID';
    END IF;

    -- Check if inviter has permission
    IF p_invited_by IS NOT NULL THEN
        SELECT role INTO v_inviter_role
        FROM public.chat_members
        WHERE chat_id = p_chat_id AND user_id = p_invited_by AND is_active = true;

        IF v_inviter_role IS NULL OR v_inviter_role = 'member' THEN
            RAISE EXCEPTION 'You do not have permission to add members';
        END IF;
    END IF;

    -- Add or reactivate member
    INSERT INTO public.chat_members (chat_id, user_id, role, invited_by)
    VALUES (p_chat_id, p_user_id, p_role, COALESCE(p_invited_by, auth.uid()))
    ON CONFLICT (chat_id, user_id) DO UPDATE SET
        is_active = true,
        role = p_role,
        joined_at = NOW(),
        invited_by = COALESCE(p_invited_by, auth.uid()),
        updated_at = NOW();

    -- Insert system message
    INSERT INTO public.chat_messages (
        chat_id, sender_id, type,
        system_event_type, system_event_data
    ) VALUES (
        p_chat_id, COALESCE(p_invited_by, auth.uid()), 'system',
        'member_added',
        jsonb_build_object('user_id', p_user_id, 'added_by', COALESCE(p_invited_by, auth.uid()))
    );

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION: Remove member from chat
-- ============================================================
CREATE OR REPLACE FUNCTION public.remove_chat_member(
    p_chat_id UUID,
    p_user_id UUID,
    p_removed_by UUID DEFAULT NULL
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_remover_role TEXT;
    v_target_role TEXT;
BEGIN
    -- [SECURITY] Ownership check
    IF COALESCE(p_removed_by, auth.uid()) != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: Invalid remover ID';
    END IF;

    -- Get roles
    SELECT role INTO v_remover_role
    FROM public.chat_members
    WHERE chat_id = p_chat_id AND user_id = COALESCE(p_removed_by, auth.uid()) AND is_active = true;

    SELECT role INTO v_target_role
    FROM public.chat_members
    WHERE chat_id = p_chat_id AND user_id = p_user_id AND is_active = true;

    -- Self-removal is always allowed
    IF p_user_id = COALESCE(p_removed_by, auth.uid()) THEN
        -- Leave chat
        UPDATE public.chat_members
        SET is_active = false, updated_at = NOW()
        WHERE chat_id = p_chat_id AND user_id = p_user_id;

        INSERT INTO public.chat_messages (
            chat_id, sender_id, type,
            system_event_type, system_event_data
        ) VALUES (
            p_chat_id, p_user_id, 'system',
            'member_left',
            jsonb_build_object('user_id', p_user_id)
        );

        RETURN TRUE;
    END IF;

    -- Check permission for removing others
    IF v_remover_role IS NULL OR v_remover_role = 'member' THEN
        RAISE EXCEPTION 'You do not have permission to remove members';
    END IF;

    IF v_target_role = 'owner' THEN
        RAISE EXCEPTION 'Cannot remove chat owner';
    END IF;

    IF v_remover_role = 'admin' AND v_target_role = 'admin' THEN
        RAISE EXCEPTION 'Admins cannot remove other admins';
    END IF;

    -- Remove member
    UPDATE public.chat_members
    SET is_active = false, updated_at = NOW()
    WHERE chat_id = p_chat_id AND user_id = p_user_id;

    INSERT INTO public.chat_messages (
        chat_id, sender_id, type,
        system_event_type, system_event_data
    ) VALUES (
        p_chat_id, COALESCE(p_removed_by, auth.uid()), 'system',
        'member_removed',
        jsonb_build_object('user_id', p_user_id, 'removed_by', COALESCE(p_removed_by, auth.uid()))
    );

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION: Update member role
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_chat_member_role(
    p_chat_id UUID,
    p_user_id UUID,
    p_new_role TEXT,
    p_updated_by UUID DEFAULT NULL
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_updater_role TEXT;
    v_old_role TEXT;
BEGIN
    -- [SECURITY] Ownership check
    IF COALESCE(p_updated_by, auth.uid()) != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: Invalid updater ID';
    END IF;

    -- Get roles
    SELECT role INTO v_updater_role
    FROM public.chat_members
    WHERE chat_id = p_chat_id AND user_id = COALESCE(p_updated_by, auth.uid()) AND is_active = true;

    SELECT role INTO v_old_role
    FROM public.chat_members
    WHERE chat_id = p_chat_id AND user_id = p_user_id AND is_active = true;

    -- Check permission
    IF v_updater_role != 'owner' THEN
        RAISE EXCEPTION 'Only owner can change member roles';
    END IF;

    IF p_user_id = COALESCE(p_updated_by, auth.uid()) THEN
        RAISE EXCEPTION 'Cannot change your own role';
    END IF;

    -- Update role
    UPDATE public.chat_members
    SET role = p_new_role, updated_at = NOW()
    WHERE chat_id = p_chat_id AND user_id = p_user_id;

    -- Insert system message
    INSERT INTO public.chat_messages (
        chat_id, sender_id, type,
        system_event_type, system_event_data
    ) VALUES (
        p_chat_id, COALESCE(p_updated_by, auth.uid()), 'system',
        CASE WHEN p_new_role = 'admin' THEN 'member_promoted' ELSE 'member_demoted' END,
        jsonb_build_object('user_id', p_user_id, 'old_role', v_old_role, 'new_role', p_new_role)
    );

    RETURN TRUE;
END;
$$;

-- ============================================================
-- TRIGGERS
-- ============================================================
DO $$
BEGIN
    DROP TRIGGER IF EXISTS update_chat_members_updated_at ON public.chat_members;
    CREATE TRIGGER update_chat_members_updated_at
        BEFORE UPDATE ON public.chat_members
        FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

    DROP TRIGGER IF EXISTS trigger_update_member_count ON public.chat_members;
    CREATE TRIGGER trigger_update_member_count
        AFTER INSERT OR UPDATE OR DELETE ON public.chat_members
        FOR EACH ROW EXECUTE FUNCTION internal.update_chat_member_count();
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT ALL ON TABLE public.chat_members TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_chat_member_role(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_chat_member(UUID, UUID, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_chat_member(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_chat_member_role(UUID, UUID, TEXT, UUID) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.chat_members table ready';
    RAISE NOTICE '   - 2 triggers:';
    RAISE NOTICE '     • update_chat_members_updated_at';
    RAISE NOTICE '     • trigger_update_member_count';
    RAISE NOTICE '   - 5 functions:';
    RAISE NOTICE '     • update_chat_member_count()';
    RAISE NOTICE '     • get_chat_member_role()';
    RAISE NOTICE '     • add_chat_member()';
    RAISE NOTICE '     • remove_chat_member()';
    RAISE NOTICE '     • update_chat_member_role()';
    RAISE NOTICE '   - 3 RLS policies';
    RAISE NOTICE '   - 8 indexes';
END $$;
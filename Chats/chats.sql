-- ============================================================
-- 📁 FILE 20: CHATS TABLE
-- Core chat container (1:1 and group)
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type TEXT NOT NULL DEFAULT 'one_on_one' CHECK (type IN ('one_on_one', 'group')),
    
    -- Basic info (group only)
    name TEXT,
    avatar TEXT,
    description TEXT,
    
    -- Settings
    visibility TEXT DEFAULT 'private' CHECK (visibility IN ('public', 'private')),
    who_can_send TEXT DEFAULT 'all' CHECK (who_can_send IN ('all', 'admins', 'owner')),
    who_can_add_members TEXT DEFAULT 'admins' CHECK (who_can_add_members IN ('all', 'admins', 'owner')),
    disappearing_messages BOOLEAN DEFAULT false,
    disappearing_duration INTEGER,
    
    -- Metrics (trigger-maintained)
    total_members INTEGER DEFAULT 0,
    last_message_at TIMESTAMPTZ,
    
    -- Metadata (linked items, extra config)
    metadata JSONB DEFAULT '{}'::jsonb,
    
    -- Ownership
    created_by UUID NOT NULL,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_chats_type ON public.chats(type);
CREATE INDEX IF NOT EXISTS idx_chats_created_by ON public.chats(created_by);
CREATE INDEX IF NOT EXISTS idx_chats_last_message ON public.chats(last_message_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_chats_visibility ON public.chats(visibility) WHERE visibility = 'public';

-- RLS policies will be created after function definition

-- ============================================================
-- FUNCTION 1: Get or create direct chat (1:1)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_or_create_direct_chat(
    p_user1_id UUID,
    p_user2_id UUID,
    p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_chat_id UUID;
BEGIN
    -- Validate caller is one of the users
    IF auth.uid() IS NOT NULL AND auth.uid() NOT IN (p_user1_id, p_user2_id) THEN
        RAISE EXCEPTION 'Unauthorized: You can only create chats for yourself';
    END IF;

    -- Find existing 1:1 chat between these two users (ignoring is_active status)
    SELECT c.id INTO v_chat_id
    FROM public.chats c
    WHERE c.type = 'one_on_one'
      AND EXISTS (
          SELECT 1 FROM public.chat_members
          WHERE chat_id = c.id AND user_id = p_user1_id
      )
      AND EXISTS (
          SELECT 1 FROM public.chat_members
          WHERE chat_id = c.id AND user_id = p_user2_id
      )
    LIMIT 1;

    -- Update is_active if found (reactivate deleted chats) and refresh metadata
    IF v_chat_id IS NOT NULL THEN
        UPDATE public.chat_members
        SET is_active = true, updated_at = NOW()
        WHERE chat_id = v_chat_id 
          AND user_id IN (p_user1_id, p_user2_id) 
          AND is_active = false;
          
        -- Refresh metadata if new metadata is provided
        IF p_metadata != '{}'::jsonb THEN
            UPDATE public.chats
            SET metadata = metadata || p_metadata, updated_at = NOW()
            WHERE id = v_chat_id;
        END IF;
    END IF;

    -- Create if not found
    IF v_chat_id IS NULL THEN
        INSERT INTO public.chats (type, created_by, metadata)
        VALUES ('one_on_one', p_user1_id, p_metadata)
        RETURNING id INTO v_chat_id;

        INSERT INTO public.chat_members (chat_id, user_id, role)
        VALUES
            (v_chat_id, p_user1_id, 'member'),
            (v_chat_id, p_user2_id, 'member');
    END IF;

    RETURN v_chat_id;
END;
$$;

-- ============================================================
-- FUNCTION 2: Check if user is chat member
-- ============================================================
CREATE OR REPLACE FUNCTION internal.is_chat_member(
    p_chat_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.chat_members
        WHERE chat_id = p_chat_id
          AND user_id = p_user_id
          AND is_active = true
    );
END;
$$;

-- ============================================================
-- RLS (Created after function definition)
-- ============================================================
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    -- Cleanup old policies
    DROP POLICY IF EXISTS "chats_creator_all" ON public.chats;
    DROP POLICY IF EXISTS "chats_member_select" ON public.chats;
    DROP POLICY IF EXISTS "chats_public_select" ON public.chats;

    -- Create new policies
    CREATE POLICY "chats_creator_all" ON public.chats
        FOR ALL
        USING (created_by = auth.uid())
        WITH CHECK (created_by = auth.uid());

    CREATE POLICY "chats_member_select" ON public.chats
        FOR SELECT
        USING (internal.is_chat_member(chats.id, auth.uid()));

    CREATE POLICY "chats_public_select" ON public.chats
        FOR SELECT
        USING (type = 'group' AND visibility = 'public');
END $$;


-- ============================================================
-- FUNCTION 3: Mark chat as read
-- ============================================================
CREATE OR REPLACE FUNCTION public.mark_chat_as_read(
    p_chat_id UUID,
    p_user_id UUID
)
RETURNS VOID
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_message_id UUID;
BEGIN
    -- Validate caller
    IF auth.uid() IS NOT NULL AND auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Unauthorized: You can only mark your own chats as read';
    END IF;

    -- 1. Get last message id
    SELECT id INTO v_last_message_id
    FROM public.chat_messages
    WHERE chat_id = p_chat_id AND is_deleted = false
    ORDER BY sent_at DESC
    LIMIT 1;

    -- 2. Update member read cursor
    UPDATE public.chat_members
    SET
        last_read_message_id = v_last_message_id,
        last_read_at = NOW(),
        unread_count = 0,
        unread_mentions = 0,
        updated_at = NOW()
    WHERE chat_id = p_chat_id AND user_id = p_user_id;

    -- 3. Update messages sent BY OTHERS to 'read' status
    UPDATE public.chat_messages
    SET status = 'read', updated_at = NOW()
    WHERE chat_id = p_chat_id 
      AND sender_id != p_user_id 
      AND status != 'read';
END;
$$;

-- ============================================================
-- FUNCTION 4: Create group chat
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_group_chat(
    p_creator_id UUID,
    p_name TEXT,
    p_member_ids UUID[],
    p_avatar TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL
)
RETURNS UUID
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_chat_id UUID;
    v_member_id UUID;
BEGIN
    -- Validate caller
    IF auth.uid() IS NOT NULL AND auth.uid() != p_creator_id THEN
        RAISE EXCEPTION 'Unauthorized: You can only create chats for yourself';
    END IF;

    -- Create the group chat
    INSERT INTO public.chats (type, name, avatar, description, created_by)
    VALUES ('group', p_name, p_avatar, p_description, p_creator_id)
    RETURNING id INTO v_chat_id;

    -- Add creator as owner
    INSERT INTO public.chat_members (chat_id, user_id, role)
    VALUES (v_chat_id, p_creator_id, 'owner');

    -- Add other members
    FOREACH v_member_id IN ARRAY p_member_ids
    LOOP
        IF v_member_id != p_creator_id THEN
            INSERT INTO public.chat_members (chat_id, user_id, role, invited_by)
            VALUES (v_chat_id, v_member_id, 'member', p_creator_id)
            ON CONFLICT (chat_id, user_id) DO NOTHING;
        END IF;
    END LOOP;

    -- Insert system message
    INSERT INTO public.chat_messages (
        chat_id, sender_id, type,
        system_event_type, system_event_data
    ) VALUES (
        v_chat_id, p_creator_id, 'system',
        'chat_created',
        jsonb_build_object('created_by', p_creator_id, 'name', p_name)
    );

    RETURN v_chat_id;
END;
$$;

-- ============================================================
-- FUNCTION 5: Get user chats
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_user_chats(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0,
    p_include_archived BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    chat_id UUID,
    chat_type TEXT,
    chat_name TEXT,
    chat_avatar TEXT,
    last_message_at TIMESTAMPTZ,
    unread_count INTEGER,
    unread_mentions INTEGER,
    is_pinned BOOLEAN,
    is_muted BOOLEAN,
    is_archived BOOLEAN,
    member_role TEXT,
    total_members INTEGER
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id as chat_id,
        c.type as chat_type,
        c.name as chat_name,
        c.avatar as chat_avatar,
        c.last_message_at,
        cm.unread_count,
        cm.unread_mentions,
        cm.is_pinned,
        cm.is_muted,
        cm.is_archived,
        cm.role as member_role,
        c.total_members
    FROM public.chats c
    JOIN public.chat_members cm ON cm.chat_id = c.id
    WHERE cm.user_id = p_user_id
      AND cm.is_active = true
      AND (p_include_archived OR cm.is_archived = false)
    ORDER BY cm.is_pinned DESC, c.last_message_at DESC NULLS LAST
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ============================================================
-- TRIGGER: Updated at
-- ============================================================
DO $$
BEGIN
    DROP TRIGGER IF EXISTS update_chats_updated_at ON public.chats;
    CREATE TRIGGER update_chats_updated_at
        BEFORE UPDATE ON public.chats
-- FUNCTION: Delete or Leave Chat
-- ============================================================
CREATE OR REPLACE FUNCTION public.delete_chat(p_chat_id UUID)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id UUID;
    v_chat_type TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Get chat type
    SELECT type INTO v_chat_type 
    FROM public.chats 
    WHERE id = p_chat_id;
    
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Soft delete the user's membership (Leave the chat)
    UPDATE public.chat_members
    SET is_active = false, updated_at = NOW()
    WHERE chat_id = p_chat_id AND user_id = v_user_id;

    -- If it's a 1:1 chat and both users left, we clean up the chat entirely
    IF v_chat_type = 'one_on_one' THEN
       IF NOT EXISTS (
           SELECT 1 FROM public.chat_members 
           WHERE chat_id = p_chat_id AND is_active = true
       ) THEN
           DELETE FROM public.chats WHERE id = p_chat_id;
       END IF;
    END IF;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- TRIGGER: Updated at
-- ============================================================
DO $$
BEGIN
    DROP TRIGGER IF EXISTS update_chats_updated_at ON public.chats;
    CREATE TRIGGER update_chats_updated_at
        BEFORE UPDATE ON public.chats
        FOR EACH ROW 
        EXECUTE FUNCTION public.update_updated_at_column();
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT EXECUTE ON FUNCTION public.get_or_create_direct_chat(UUID, UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_chat_as_read(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_group_chat(UUID, TEXT, UUID[], TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_chats(UUID, INTEGER, INTEGER, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_chat(UUID) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.chats table ready';
    RAISE NOTICE '   - 1 trigger: update_chats_updated_at';
    RAISE NOTICE '   - 6 functions:';
    RAISE NOTICE '     • get_or_create_direct_chat()';
    RAISE NOTICE '     • is_chat_member()';
    RAISE NOTICE '     • mark_chat_as_read()';
    RAISE NOTICE '     • create_group_chat()';
    RAISE NOTICE '     • get_user_chats()';
    RAISE NOTICE '     • delete_chat()';
    RAISE NOTICE '   - 3 RLS policies';
    RAISE NOTICE '   - 4 indexes';
END $$;
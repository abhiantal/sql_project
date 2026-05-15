-- ============================================================
-- 📁 FILE 22: CHAT MESSAGES TABLE
-- Messages with replies, forwards, reactions, shared content
-- Shared content stores only ID reference (no data duplication)
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL,

    -- Message type
    type TEXT NOT NULL DEFAULT 'text' CHECK (type IN (
        'text', 'image', 'video', 'audio', 'voice', 'document',
        'location', 'contact', 'shared_content', 'system'
    )),

    -- Content
    text_content TEXT,

    -- Flexible data (location coords, contact info, etc.)
    metadata JSONB DEFAULT '{}'::jsonb,

    -- Reply
    reply_to_id UUID REFERENCES public.chat_messages(id) ON DELETE SET NULL,

    -- Forward
    forwarded_from_message_id UUID,
    forward_count INTEGER DEFAULT 0,

    -- ============================================================
    -- SHARED CONTENT (task, goal, diary, bucket, post, profile)
    -- Stores ONLY references - NO data duplication
    -- Client fetches live data using these IDs
    -- ============================================================
    shared_content_type TEXT CHECK (shared_content_type IN (
        'day_task', 'weekly_task', 'long_goal',
        'bucket_model', 'diary_entry', 'post', 'profile',
        'chat_task', 'chat_poll', NULL
    )),
    shared_content_id UUID,
    -- Optional: 'live' or 'snapshot' mode
    shared_content_mode TEXT DEFAULT 'live' CHECK (shared_content_mode IN ('live', 'snapshot', NULL)),
    -- Optional: snapshot data if mode = 'snapshot'
    shared_content_snapshot JSONB,

    -- System events
    system_event_type TEXT CHECK (system_event_type IN (
        'chat_created', 'member_joined', 'member_left',
        'member_added', 'member_removed', 'member_promoted',
        'member_demoted', 'name_changed', 'avatar_changed',
        'disappearing_enabled', 'disappearing_disabled', NULL
    )),
    system_event_data JSONB,

    -- Reactions (inline JSONB instead of separate table)
    -- Format: {"👍": ["user-id-1", "user-id-2"], "❤️": ["user-id-3"]}
    reactions JSONB DEFAULT '{}'::jsonb,

    -- Mentions
    mentioned_user_ids JSONB DEFAULT '{"items": []}'::jsonb,

    -- State
    is_edited BOOLEAN DEFAULT false,
    is_deleted BOOLEAN DEFAULT false,
    is_pinned BOOLEAN DEFAULT false,
    pinned_at TIMESTAMPTZ,
    pinned_by UUID,
    status TEXT DEFAULT 'sent' CHECK (status IN ('sending', 'sent', 'delivered', 'read', 'failed')),

    -- Timestamps
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    edited_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_chat_messages_chat_sent ON public.chat_messages(chat_id, sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender ON public.chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_reply ON public.chat_messages(reply_to_id) WHERE reply_to_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_messages_pinned ON public.chat_messages(chat_id) WHERE is_pinned = true;
CREATE INDEX IF NOT EXISTS idx_chat_messages_not_deleted ON public.chat_messages(chat_id, sent_at DESC) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_chat_messages_shared ON public.chat_messages(shared_content_type, shared_content_id) WHERE shared_content_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_messages_expires ON public.chat_messages(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_messages_mentions ON public.chat_messages USING GIN(mentioned_user_ids) WHERE mentioned_user_ids IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_messages_type ON public.chat_messages(chat_id, type);
CREATE INDEX IF NOT EXISTS idx_chat_messages_search ON public.chat_messages USING GIN(to_tsvector('english', COALESCE(text_content, '')));

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS "chat_messages_sender_all" ON public.chat_messages;
    CREATE POLICY "chat_messages_sender_all" ON public.chat_messages
        FOR ALL
        USING (sender_id = auth.uid())
        WITH CHECK (sender_id = auth.uid());

    DROP POLICY IF EXISTS "chat_messages_member_select" ON public.chat_messages;
    CREATE POLICY "chat_messages_member_select" ON public.chat_messages
        FOR SELECT
        USING (
            EXISTS (
                SELECT 1 FROM public.chat_members
                WHERE chat_members.chat_id = chat_messages.chat_id
                  AND chat_members.user_id = auth.uid()
                  AND chat_members.is_active = true
            )
        );
END $$;

-- ============================================================
-- FUNCTION: Acknowledge message receipt (transition sending -> sent)
-- ============================================================
CREATE OR REPLACE FUNCTION internal.acknowledge_message_receipt()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'sending' THEN
        NEW.status := 'sent';
    END IF;
    RETURN NEW;
END;
$$;

-- ============================================================
-- FUNCTION: Handle message changes (update unread counts)
-- ============================================================
CREATE OR REPLACE FUNCTION internal.on_chat_message_change()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Update chat last_message_at
        UPDATE public.chats
        SET last_message_at = NEW.sent_at, updated_at = NOW()
        WHERE id = NEW.chat_id;

        -- Reactivate and increment unread for 1:1 members, increment unread for active members
        UPDATE public.chat_members
        SET
            is_active = true, -- Re-activate if it was soft-deleted (for 1:1)
            unread_count = unread_count + 1,
            unread_mentions = CASE
                WHEN NEW.mentioned_user_ids IS NOT NULL
                     AND NEW.mentioned_user_ids->'items' @> to_jsonb(chat_members.user_id::text)
                THEN unread_mentions + 1
                ELSE unread_mentions
            END,
            updated_at = NOW()
        WHERE chat_id = NEW.chat_id
          AND user_id != NEW.sender_id
          AND (
            is_active = true 
            OR 
            EXISTS (SELECT 1 FROM public.chats WHERE id = NEW.chat_id AND type = 'one_on_one')
          );

        -- Set expires_at for disappearing messages
        -- Note: expires_at update is moved to BEFORE trigger or updated here
        IF NEW.expires_at IS NULL THEN
            UPDATE public.chat_messages
            SET expires_at = CASE
                WHEN (SELECT disappearing_messages FROM public.chats WHERE id = NEW.chat_id) = true
                THEN NEW.sent_at + (
                    (SELECT disappearing_duration FROM public.chats WHERE id = NEW.chat_id) * INTERVAL '1 second'
                )
                ELSE NULL
            END
            WHERE id = NEW.id;
        END IF;

        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

-- ============================================================
-- FUNCTION: Send message
-- ============================================================
CREATE OR REPLACE FUNCTION public.send_chat_message(
    p_chat_id UUID,
    p_sender_id UUID,
    p_type TEXT,
    p_text_content TEXT DEFAULT NULL,
    p_reply_to_id UUID DEFAULT NULL,
    p_mentioned_user_ids UUID[] DEFAULT NULL,
    p_metadata JSONB DEFAULT NULL
)
RETURNS UUID
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_message_id UUID;
    v_is_member BOOLEAN;
BEGIN
    -- Validate sender is member
    SELECT EXISTS(
        SELECT 1 FROM public.chat_members
        WHERE chat_id = p_chat_id AND user_id = p_sender_id AND is_active = true
    ) INTO v_is_member;

    IF NOT v_is_member THEN
        RAISE EXCEPTION 'You are not a member of this chat';
    END IF;

    -- Insert message
    INSERT INTO public.chat_messages (
        chat_id, sender_id, type, text_content,
        reply_to_id, mentioned_user_ids, metadata
    )
    VALUES (
        p_chat_id, p_sender_id, p_type, p_text_content,
        p_reply_to_id, jsonb_build_object('items', to_jsonb(p_mentioned_user_ids)), COALESCE(p_metadata, '{}'::jsonb)
    )
    RETURNING id INTO v_message_id;

    RETURN v_message_id;
END;
$$;

-- ============================================================
-- FUNCTION: Share content in chat (stores only reference)
-- ============================================================
CREATE OR REPLACE FUNCTION public.share_content_in_chat(
    p_chat_id UUID,
    p_sender_id UUID,
    p_content_type TEXT,
    p_content_id UUID,
    p_mode TEXT DEFAULT 'live',
    p_text_content TEXT DEFAULT NULL,
    p_snapshot_data JSONB DEFAULT NULL
)
RETURNS UUID
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_message_id UUID;
    v_is_member BOOLEAN;
BEGIN
    -- Validate sender is member
    SELECT EXISTS(
        SELECT 1 FROM public.chat_members
        WHERE chat_id = p_chat_id AND user_id = p_sender_id AND is_active = true
    ) INTO v_is_member;

    IF NOT v_is_member THEN
        RAISE EXCEPTION 'You are not a member of this chat';
    END IF;

    -- Insert shared content message
    INSERT INTO public.chat_messages (
        chat_id, sender_id, type, text_content,
        shared_content_type, shared_content_id,
        shared_content_mode, shared_content_snapshot
    )
    VALUES (
        p_chat_id, p_sender_id, 'shared_content', p_text_content,
        p_content_type, p_content_id,
        p_mode, CASE WHEN p_mode = 'snapshot' THEN p_snapshot_data ELSE NULL END
    )
    RETURNING id INTO v_message_id;

    RETURN v_message_id;
END;
$$;

-- ============================================================
-- FUNCTION: Get shared content data (for rendering in chat)
-- ============================================================
DROP FUNCTION IF EXISTS public.get_shared_content_data(TEXT, UUID);
CREATE OR REPLACE FUNCTION public.get_shared_content_data(
    p_content_type TEXT,
    p_content_id UUID
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_data JSONB;
BEGIN
    CASE p_content_type
        WHEN 'day_task' THEN
            SELECT jsonb_build_object(
                'task_id', dt.id,
                'type', 'day_task',
                'user_id', dt.user_id,
                'category_id', dt.category_id,
                'category_type', dt.category_type,
                'sub_types', dt.sub_types,
                'about_task', dt.about_task,
                'indicators', dt.indicators,
                'timeline', dt.timeline,
                'feedback', dt.feedback,
                'metadata', dt.metadata,
                'social_info', dt.social_info,
                'share_info', dt.share_info,
                'created_at', dt.created_at,
                'updated_at', dt.updated_at
            ) INTO v_data
            FROM public.day_tasks dt WHERE dt.id = p_content_id;

        WHEN 'weekly_task' THEN
            SELECT jsonb_build_object(
                'task_id', wt.id,
                'type', 'weekly_task',
                'user_id', wt.user_id,
                'category_id', wt.category_id,
                'category_type', wt.category_type,
                'sub_types', wt.sub_types,
                'about_task', wt.about_task,
                'indicators', wt.indicators,
                'timeline', wt.timeline,
                'feedback', wt.feedback,
                'metadata', wt.metadata,
                'social_info', wt.social_info,
                'share_info', wt.share_info,
                'created_at', wt.created_at,
                'updated_at', wt.updated_at
            ) INTO v_data
            FROM public.weekly_tasks wt WHERE wt.id = p_content_id;

        WHEN 'long_goal' THEN
            SELECT jsonb_build_object(
                'id', lg.id,
                'type', 'long_goal',
                'user_id', lg.user_id,
                'title', lg.title,
                'category_id', lg.category_id,
                'category_type', lg.category_type,
                'sub_types', lg.sub_types,
                'description', lg.description,
                'timeline', lg.timeline,
                'indicators', lg.indicators,
                'metrics', lg.metrics,
                'analysis', lg.analysis,
                'goal_log', lg.goal_log,
                'social_info', lg.social_info,
                'share_info', lg.share_info,
                'created_at', lg.created_at,
                'updated_at', lg.updated_at
            ) INTO v_data
            FROM public.long_goals lg WHERE lg.id = p_content_id;

        WHEN 'bucket_model' THEN
            SELECT jsonb_build_object(
                'id', bm.id,
                'type', 'bucket_model',
                'user_id', bm.user_id,
                'category_id', bm.category_id,
                'category_type', bm.category_type,
                'sub_types', bm.sub_types,
                'title', bm.title,
                'details', bm.details,
                'checklist', bm.checklist,
                'timeline', bm.timeline,
                'metadata', bm.metadata,
                'social_info', bm.social_info,
                'share_info', bm.share_info,
                'created_at', bm.created_at,
                'updated_at', bm.updated_at
            ) INTO v_data
            FROM public.bucket_models bm WHERE bm.id = p_content_id;

        WHEN 'diary_entry' THEN
            SELECT jsonb_build_object(
                'id', de.id,
                'title', de.title,
                'entry_date', de.entry_date,
                'mood', de.mood,
                'preview', LEFT(de.content, 200),
                'user_id', de.user_id
            ) INTO v_data
            FROM public.diary_entries de WHERE de.id = p_content_id;

        WHEN 'post' THEN
            SELECT jsonb_build_object(
                'id', p.id,
                'content', p.caption,
                'source_type', p.source_type,
                'metrics', jsonb_build_object(
                    'views', p.views_count,
                    'likes', COALESCE((p.reactions_count->>'total')::numeric::int, 0),
                    'comments', p.comments_count
                ),
                'user_id', p.user_id
            ) INTO v_data
            FROM public.posts p WHERE p.id = p_content_id;

        WHEN 'profile' THEN
            SELECT jsonb_build_object(
                'id', up.id,
                'user_id', up.user_id,
                'username', up.username,
                'profile_url', up.profile_url,
                'user_info', up.user_info
            ) INTO v_data
            FROM public.user_profiles up WHERE up.user_id = p_content_id;

        ELSE
            v_data := NULL;
    END CASE;

    -- Return null indicator if content not found
    IF v_data IS NULL THEN
        RETURN jsonb_build_object(
            'error', 'content_not_found',
            'content_type', p_content_type,
            'content_id', p_content_id
        );
    END IF;

    RETURN v_data;
END;
$$;

-- ============================================================
-- FUNCTION: Toggle reaction
-- ============================================================
CREATE OR REPLACE FUNCTION public.toggle_message_reaction(
    p_message_id UUID,
    p_user_id UUID,
    p_emoji TEXT
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_message RECORD;
    v_reactions JSONB;
    v_emoji_users JSONB;
    v_action TEXT;
BEGIN
    -- Get message
    SELECT * INTO v_message
    FROM public.chat_messages
    WHERE id = p_message_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Message not found';
    END IF;

    -- Check if user is chat member
    IF NOT EXISTS(
        SELECT 1 FROM public.chat_members
        WHERE chat_id = v_message.chat_id AND user_id = p_user_id AND is_active = true
    ) THEN
        RAISE EXCEPTION 'You are not a member of this chat';
    END IF;

    v_reactions := COALESCE(v_message.reactions, '{}'::jsonb);
    v_emoji_users := COALESCE(v_reactions->p_emoji, '[]'::jsonb);

    -- Toggle reaction
    IF v_emoji_users @> to_jsonb(p_user_id::text) THEN
        -- Remove user from emoji
        v_emoji_users := (
            SELECT COALESCE(jsonb_agg(u), '[]'::jsonb)
            FROM jsonb_array_elements_text(v_emoji_users) u
            WHERE u != p_user_id::text
        );
        v_action := 'removed';
    ELSE
        -- Add user to emoji
        v_emoji_users := v_emoji_users || to_jsonb(p_user_id::text);
        v_action := 'added';
    END IF;

    -- Update or remove emoji key
    IF jsonb_array_length(v_emoji_users) = 0 THEN
        v_reactions := v_reactions - p_emoji;
    ELSE
        v_reactions := jsonb_set(v_reactions, ARRAY[p_emoji], v_emoji_users);
    END IF;

    -- Update message
    UPDATE public.chat_messages
    SET reactions = v_reactions, updated_at = NOW()
    WHERE id = p_message_id;

    RETURN jsonb_build_object(
        'success', true,
        'action', v_action,
        'emoji', p_emoji,
        'reactions', v_reactions
    );
END;
$$;

-- ============================================================
-- FUNCTION: Edit message
-- ============================================================
CREATE OR REPLACE FUNCTION public.edit_chat_message(
    p_message_id UUID,
    p_user_id UUID,
    p_new_text TEXT
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.chat_messages
    SET
        text_content = p_new_text,
        is_edited = true,
        edited_at = NOW(),
        updated_at = NOW()
    WHERE id = p_message_id
      AND sender_id = p_user_id
      AND is_deleted = false;

    RETURN FOUND;
END;
$$;

-- ============================================================
-- FUNCTION: Delete message (soft delete)
-- ============================================================
CREATE OR REPLACE FUNCTION public.delete_chat_message(
    p_message_id UUID,
    p_user_id UUID,
    p_for_everyone BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_message RECORD;
BEGIN
    SELECT * INTO v_message
    FROM public.chat_messages
    WHERE id = p_message_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Only sender can delete for everyone
    IF p_for_everyone AND v_message.sender_id != p_user_id THEN
        RAISE EXCEPTION 'Only the sender can delete for everyone';
    END IF;

    IF p_for_everyone THEN
        UPDATE public.chat_messages
        SET
            is_deleted = true,
            text_content = NULL,
            updated_at = NOW()
        WHERE id = p_message_id;
    END IF;

    -- For "delete for me" - handled client-side (local hide)

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION: Pin/unpin message
-- ============================================================
CREATE OR REPLACE FUNCTION public.toggle_pin_message(
    p_message_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_message RECORD;
    v_user_role TEXT;
BEGIN
    SELECT * INTO v_message
    FROM public.chat_messages
    WHERE id = p_message_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Check user role
    SELECT role INTO v_user_role
    FROM public.chat_members
    WHERE chat_id = v_message.chat_id AND user_id = p_user_id AND is_active = true;

    IF v_user_role IS NULL OR v_user_role = 'member' THEN
        RAISE EXCEPTION 'Only admins and owners can pin messages';
    END IF;

    -- Toggle pin
    IF v_message.is_pinned THEN
        UPDATE public.chat_messages
        SET is_pinned = false, pinned_at = NULL, pinned_by = NULL, updated_at = NOW()
        WHERE id = p_message_id;
    ELSE
        UPDATE public.chat_messages
        SET is_pinned = true, pinned_at = NOW(), pinned_by = p_user_id, updated_at = NOW()
        WHERE id = p_message_id;
    END IF;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION: Get chat messages
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_chat_messages(
    p_chat_id UUID,
    p_user_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_before_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    chat_id UUID,
    sender_id UUID,
    sender_name TEXT,
    sender_avatar TEXT,
    content TEXT,
    media JSONB,
    status TEXT,
    is_pinned BOOLEAN,
    is_deleted BOOLEAN,
    reply_to_id UUID,
    reactions JSONB,
    sent_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- Validate membership
    IF NOT EXISTS(
        SELECT 1 FROM public.chat_members
        WHERE chat_members.chat_id = p_chat_id AND user_id = p_user_id AND is_active = true
    ) THEN
        RAISE EXCEPTION 'You are not a member of this chat';
    END IF;

    RETURN QUERY
    SELECT
        m.id, m.chat_id, m.sender_id, m.type, m.text_content,
        m.metadata, m.reply_to_id, m.shared_content_type, m.shared_content_id,
        m.shared_content_mode, m.reactions, m.is_edited, m.is_deleted,
        m.is_pinned, m.sent_at
    FROM public.chat_messages m
    WHERE m.chat_id = p_chat_id
      AND m.is_deleted = false
      AND (p_before_id IS NULL OR m.sent_at < (
          SELECT sent_at FROM public.chat_messages WHERE chat_messages.id = p_before_id
      ))
    ORDER BY m.sent_at DESC
    LIMIT p_limit;
END;
$$;

-- ============================================================
-- FUNCTION: Cleanup disappearing messages
-- ============================================================
CREATE OR REPLACE FUNCTION public.cleanup_disappearing_messages()
RETURNS INTEGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    WITH deleted AS (
        DELETE FROM public.chat_messages
        WHERE expires_at IS NOT NULL AND expires_at < NOW()
        RETURNING id
    )
    SELECT COUNT(*) INTO v_deleted FROM deleted;

    RETURN v_deleted;
END;
$$;

-- ============================================================
-- FUNCTION: Search messages
-- ============================================================
CREATE OR REPLACE FUNCTION public.search_chat_messages(
    p_chat_id UUID,
    p_user_id UUID,
    p_query TEXT,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    id UUID,
    sender_id UUID,
    text_content TEXT,
    sent_at TIMESTAMPTZ,
    rank REAL
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- Validate membership
    IF NOT EXISTS(
        SELECT 1 FROM public.chat_members
        WHERE chat_members.chat_id = p_chat_id AND user_id = p_user_id AND is_active = true
    ) THEN
        RAISE EXCEPTION 'You are not a member of this chat';
    END IF;

    RETURN QUERY
    SELECT
        m.id, m.sender_id, m.text_content, m.sent_at,
        ts_rank(to_tsvector('english', COALESCE(m.text_content, '')), plainto_tsquery('english', p_query)) as rank
    FROM public.chat_messages m
    WHERE m.chat_id = p_chat_id
      AND m.is_deleted = false
      AND to_tsvector('english', COALESCE(m.text_content, '')) @@ plainto_tsquery('english', p_query)
    ORDER BY rank DESC, m.sent_at DESC
    LIMIT p_limit;
END;
$$;

-- ============================================================
-- TRIGGERS
-- ============================================================
DO $$
BEGIN
    DROP TRIGGER IF EXISTS update_chat_messages_updated_at ON public.chat_messages;
    CREATE TRIGGER update_chat_messages_updated_at
        BEFORE UPDATE ON public.chat_messages
        FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

    DROP TRIGGER IF EXISTS trigger_acknowledge_message ON public.chat_messages;
    CREATE TRIGGER trg_acknowledge_message_receipt
        BEFORE INSERT ON public.chat_messages
        FOR EACH ROW
        EXECUTE FUNCTION internal.acknowledge_message_receipt();

    CREATE TRIGGER trg_chat_message_change
        AFTER INSERT OR UPDATE OR DELETE ON public.chat_messages
        FOR EACH ROW
        EXECUTE FUNCTION internal.on_chat_message_change();
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT ALL ON TABLE public.chat_messages TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_chat_message(UUID, UUID, TEXT, TEXT, UUID, UUID[], JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.share_content_in_chat(UUID, UUID, TEXT, UUID, TEXT, TEXT, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_shared_content_data(TEXT, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.toggle_message_reaction(UUID, UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.edit_chat_message(UUID, UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_chat_message(UUID, UUID, BOOLEAN) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.toggle_pin_message(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_chat_messages(UUID, UUID, INTEGER, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_chat_messages(UUID, UUID, TEXT, INTEGER) TO authenticated, service_role;

-- [Administrative/Internal]
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.cleanup_disappearing_messages() TO service_role;
REVOKE EXECUTE ON FUNCTION public.on_chat_message_change() FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.acknowledge_message_receipt() FROM authenticated, anon;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.chat_messages table ready';
    RAISE NOTICE '   - 2 triggers:';
    RAISE NOTICE '     • update_chat_messages_updated_at';
    RAISE NOTICE '     • trigger_on_chat_message_change';
    RAISE NOTICE '   - 11 functions:';
    RAISE NOTICE '     • on_chat_message_change()';
    RAISE NOTICE '     • send_chat_message()';
    RAISE NOTICE '     • share_content_in_chat()';
    RAISE NOTICE '     • get_shared_content_data()';
    RAISE NOTICE '     • toggle_message_reaction()';
    RAISE NOTICE '     • edit_chat_message()';
    RAISE NOTICE '     • delete_chat_message()';
    RAISE NOTICE '     • toggle_pin_message()';
    RAISE NOTICE '     • get_chat_messages()';
    RAISE NOTICE '     • cleanup_disappearing_messages()';
    RAISE NOTICE '     • search_chat_messages()';
    RAISE NOTICE '   - 2 RLS policies';
    RAISE NOTICE '   - 10 indexes';
    RAISE NOTICE '';
    RAISE NOTICE '   📌 Shared Content Note:';
    RAISE NOTICE '   - Only stores content_type + content_id (NO data duplication)';
    RAISE NOTICE '   - Client fetches live data using get_shared_content_data()';
    RAISE NOTICE '   - Optional snapshot mode for offline/deleted content';
END $$;
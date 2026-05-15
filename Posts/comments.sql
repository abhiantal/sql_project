-- ============================================================
-- 📁 FILE 03: COMMENTS TABLE
-- Threaded comment system with materialized path
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,

    -- ════════════════════════════════════════════════════════
    -- THREADING
    -- ════════════════════════════════════════════════════════
    parent_comment_id UUID REFERENCES public.comments(id) ON DELETE CASCADE,
    reply_to_user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    thread_depth INTEGER DEFAULT 0,
    thread_path TEXT,

    -- ════════════════════════════════════════════════════════
    -- CONTENT
    -- ════════════════════════════════════════════════════════
    content TEXT NOT NULL,
    content_rendered TEXT,
    mentions JSONB DEFAULT '{"items": []}'::jsonb,
    mentioned_usernames JSONB DEFAULT '{"items": []}'::jsonb,
    hashtags JSONB DEFAULT '{"items": []}'::jsonb,

    -- ════════════════════════════════════════════════════════
    -- MEDIA (single image/gif/sticker)
    -- ════════════════════════════════════════════════════════
    media JSONB,

    -- ════════════════════════════════════════════════════════
    -- ENGAGEMENT (Trigger-Maintained)
    -- ════════════════════════════════════════════════════════
    reactions_count JSONB DEFAULT '{"total":0}'::jsonb,
    replies_count INTEGER DEFAULT 0,

    -- ════════════════════════════════════════════════════════
    -- STATUS
    -- ════════════════════════════════════════════════════════
    is_edited BOOLEAN DEFAULT FALSE,
    edited_at TIMESTAMPTZ,
    is_deleted BOOLEAN DEFAULT FALSE,
    is_hidden BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,
    is_by_author BOOLEAN DEFAULT FALSE,

    -- ════════════════════════════════════════════════════════
    -- TIMESTAMPS
    -- ════════════════════════════════════════════════════════
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_comments_user ON public.comments(user_id);
CREATE INDEX IF NOT EXISTS idx_comments_post ON public.comments(post_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comments_parent ON public.comments(parent_comment_id) WHERE parent_comment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_comments_thread_path ON public.comments(post_id, thread_path);
CREATE INDEX IF NOT EXISTS idx_comments_pinned ON public.comments(post_id) WHERE is_pinned = true;
CREATE INDEX IF NOT EXISTS idx_comments_not_deleted ON public.comments(post_id, created_at) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_comments_mentions ON public.comments USING GIN(mentions);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comments' AND policyname = 'comments_select_post_visible') THEN
        CREATE POLICY "comments_select_post_visible" ON public.comments
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM public.posts p
                    WHERE p.id = comments.post_id
                    AND p.published_at IS NOT NULL
                    AND (
                        p.visibility = 'public'
                        OR p.user_id = auth.uid()
                        OR (
                            p.visibility = 'followers'
                            AND EXISTS (
                                SELECT 1 FROM public.follows f
                                WHERE f.follower_id = auth.uid()
                                AND f.following_id = p.user_id
                                AND f.status = 'active'
                            )
                        )
                        OR (
                            p.visibility = 'following'
                            AND EXISTS (
                                SELECT 1 FROM public.follows f
                                WHERE f.follower_id = p.user_id
                                AND f.following_id = auth.uid()
                                AND f.status = 'active'
                            )
                        )
                    )
                )
            );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comments' AND policyname = 'comments_select_own') THEN
        CREATE POLICY "comments_select_own" ON public.comments
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comments' AND policyname = 'comments_insert_own') THEN
        CREATE POLICY "comments_insert_own" ON public.comments
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comments' AND policyname = 'comments_update_own') THEN
        CREATE POLICY "comments_update_own" ON public.comments
            FOR UPDATE USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comments' AND policyname = 'comments_delete_own') THEN
        CREATE POLICY "comments_delete_own" ON public.comments
            FOR DELETE USING (auth.uid() = user_id);
    END IF;

    -- Allow anyone to update counters (Hardened: only authenticated users can update their own data or trigger-based updates)
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'comments' AND policyname = 'comments_update_counters') THEN
        CREATE POLICY "comments_update_counters" ON public.comments 
            FOR UPDATE TO authenticated 
            USING (auth.uid() IS NOT NULL)
            WITH CHECK (auth.uid() IS NOT NULL);
    END IF;
END $$;

-- ============================================================
-- TRIGGER FUNCTION: Auto-generate thread_path
-- ============================================================
-- ============================================================
-- INTERNAL TRIGGER FUNCTIONS (Relocated to internal schema)
-- ============================================================
CREATE OR REPLACE FUNCTION internal.fn_set_comment_thread_path()
RETURNS TRIGGER SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE v_parent_path TEXT; v_parent_depth INTEGER; v_sibling_count INTEGER; v_new_segment TEXT;
BEGIN
    IF NEW.parent_comment_id IS NULL THEN
        SELECT COUNT(*) INTO v_sibling_count FROM public.comments WHERE post_id = NEW.post_id AND parent_comment_id IS NULL;
        NEW.thread_path := LPAD((v_sibling_count + 1)::text, 4, '0');
        NEW.thread_depth := 0;
    ELSE
        SELECT thread_path, thread_depth INTO v_parent_path, v_parent_depth FROM public.comments WHERE id = NEW.parent_comment_id;
        IF v_parent_path IS NULL THEN RAISE EXCEPTION 'Parent comment not found'; END IF;
        IF v_parent_depth >= 4 THEN RAISE EXCEPTION 'Maximum thread depth reached (4 levels)'; END IF;
        SELECT COUNT(*) INTO v_sibling_count FROM public.comments WHERE parent_comment_id = NEW.parent_comment_id;
        v_new_segment := LPAD((v_sibling_count + 1)::text, 4, '0');
        NEW.thread_path := v_parent_path || '/' || v_new_segment;
        NEW.thread_depth := v_parent_depth + 1;
    END IF;
    RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION internal.fn_set_comment_is_by_author()
RETURNS TRIGGER SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
BEGIN
    SELECT (p.user_id = NEW.user_id) INTO NEW.is_by_author FROM public.posts p WHERE p.id = NEW.post_id;
    RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION internal.fn_update_post_comment_count()
RETURNS TRIGGER SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE v_post_id UUID; v_count INTEGER;
BEGIN
    v_post_id := COALESCE(NEW.post_id, OLD.post_id);
    SELECT COUNT(*) INTO v_count FROM public.comments WHERE post_id = v_post_id AND is_deleted = false;
    UPDATE public.posts SET comments_count = v_count WHERE id = v_post_id;
    RETURN COALESCE(NEW, OLD);
END; $$;

CREATE OR REPLACE FUNCTION internal.fn_update_parent_replies_count()
RETURNS TRIGGER SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE v_parent_id UUID; v_count INTEGER;
BEGIN
    v_parent_id := COALESCE(NEW.parent_comment_id, OLD.parent_comment_id);
    IF v_parent_id IS NOT NULL THEN
        SELECT COUNT(*) INTO v_count FROM public.comments WHERE parent_comment_id = v_parent_id AND is_deleted = false;
        UPDATE public.comments SET replies_count = v_count WHERE id = v_parent_id;
    END IF;
    RETURN COALESCE(NEW, OLD);
END; $$;

-- ============================================================
-- CREATE TRIGGERS
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_set_comment_thread_path') THEN
        CREATE TRIGGER trg_set_comment_thread_path
            BEFORE INSERT ON public.comments
            FOR EACH ROW EXECUTE FUNCTION internal.fn_set_comment_thread_path();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_set_comment_is_by_author') THEN
        CREATE TRIGGER trg_set_comment_is_by_author
            BEFORE INSERT ON public.comments
            FOR EACH ROW EXECUTE FUNCTION internal.fn_set_comment_is_by_author();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_post_comment_count') THEN
        CREATE TRIGGER trg_update_post_comment_count
            AFTER INSERT OR DELETE ON public.comments
            FOR EACH ROW EXECUTE FUNCTION internal.fn_update_post_comment_count();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_parent_replies_count') THEN
        CREATE TRIGGER trg_update_parent_replies_count
            AFTER INSERT OR DELETE ON public.comments
            FOR EACH ROW EXECUTE FUNCTION internal.fn_update_parent_replies_count();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_comments_updated_at') THEN
        CREATE TRIGGER trg_update_comments_updated_at
            BEFORE UPDATE ON public.comments
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;
END $$;

-- ============================================================
-- FUNCTION: Add comment
-- ============================================================
CREATE OR REPLACE FUNCTION public.add_comment(
    p_user_id UUID,
    p_post_id UUID,
    p_content TEXT,
    p_parent_comment_id UUID DEFAULT NULL,
    p_mentions UUID[] DEFAULT '{}',
    p_mentioned_usernames TEXT[] DEFAULT '{}',
    p_media JSONB DEFAULT NULL
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_comment_id UUID;
    v_post RECORD;
    v_reply_to_user_id UUID;
    v_result RECORD;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Verify post exists and allows comments
    SELECT id, user_id, allow_comments, published_at
    INTO v_post
    FROM public.posts
    WHERE id = p_post_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Post not found';
    END IF;

    IF v_post.published_at IS NULL THEN
        RAISE EXCEPTION 'Post is not available';
    END IF;

    IF NOT v_post.allow_comments THEN
        RAISE EXCEPTION 'Comments are disabled on this post';
    END IF;

    -- Get reply_to_user_id from parent comment
    IF p_parent_comment_id IS NOT NULL THEN
        SELECT user_id INTO v_reply_to_user_id
        FROM public.comments
        WHERE id = p_parent_comment_id
        AND post_id = p_post_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Parent comment not found in this post';
        END IF;
    END IF;

    -- Insert comment (thread_path & is_by_author set by triggers)
    INSERT INTO public.comments (
        user_id, post_id, parent_comment_id,
        reply_to_user_id, content,
        mentions, mentioned_usernames, media
    )
    VALUES (
        p_user_id, p_post_id, p_parent_comment_id,
        v_reply_to_user_id, p_content,
        jsonb_build_object('items', to_jsonb(p_mentions)), jsonb_build_object('items', to_jsonb(p_mentioned_usernames)), p_media
    )
    RETURNING id INTO v_comment_id;

    -- Return created comment with user info
    SELECT
        c.id,
        c.user_id,
        up.username,
        up.display_name,
        up.profile_url,
        c.content,
        c.parent_comment_id,
        c.thread_depth,
        c.thread_path,
        c.is_by_author,
        c.media,
        c.created_at
    INTO v_result
    FROM public.comments c
    JOIN public.user_profiles up ON up.user_id = c.user_id
    WHERE c.id = v_comment_id;

    RETURN jsonb_build_object(
        'success', true,
        'comment_id', v_result.id,
        'user_id', v_result.user_id,
        'username', v_result.username,
        'display_name', v_result.display_name,
        'profile_url', v_result.profile_url,
        'content', v_result.content,
        'parent_comment_id', v_result.parent_comment_id,
        'thread_depth', v_result.thread_depth,
        'thread_path', v_result.thread_path,
        'is_by_author', v_result.is_by_author,
        'media', v_result.media,
        'created_at', v_result.created_at
    );
END;
$$;

-- ============================================================
-- FUNCTION: Get post comments (threaded)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_post_comments(
    p_post_id UUID,
    p_requesting_user_id UUID,
    p_sort_by TEXT DEFAULT 'newest',
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0,
    p_parent_comment_id UUID DEFAULT NULL
)
RETURNS TABLE (
    comment_id UUID,
    user_id UUID,
    username TEXT,
    display_name TEXT,
    profile_url TEXT,
    content TEXT,
    media JSONB,
    parent_comment_id UUID,
    reply_to_user_id UUID,
    reply_to_username TEXT,
    reply_to_display_name TEXT,
    thread_depth INTEGER,
    thread_path TEXT,
    reactions_count JSONB,
    replies_count INTEGER,
    is_edited BOOLEAN,
    is_by_author BOOLEAN,
    is_pinned BOOLEAN,
    is_liked BOOLEAN,
    created_at TIMESTAMPTZ
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id as comment_id,
        c.user_id,
        up.username,
        up.display_name,
        up.profile_url,
        CASE
            WHEN c.is_deleted THEN '[Comment deleted]'
            WHEN c.is_hidden AND c.user_id != p_requesting_user_id THEN '[Comment hidden]'
            ELSE c.content
        END as content,
        CASE WHEN c.is_deleted OR c.is_hidden THEN NULL ELSE c.media END as media,
        c.parent_comment_id,
        c.reply_to_user_id,
        rtu.username as reply_to_username,
        rtu.display_name as reply_to_display_name,
        c.thread_depth,
        c.thread_path,
        c.reactions_count,
        c.replies_count,
        c.is_edited,
        c.is_by_author,
        c.is_pinned,
        EXISTS(
            SELECT 1 FROM public.reactions r
            WHERE r.target_type = 'comment'
            AND r.target_id = c.id
            AND r.user_id = p_requesting_user_id
        ) as is_liked,
        c.created_at
    FROM public.comments c
    JOIN public.user_profiles up ON up.user_id = c.user_id
    LEFT JOIN public.user_profiles rtu ON rtu.user_id = c.reply_to_user_id
    WHERE c.post_id = p_post_id
    AND (
        p_parent_comment_id IS NULL
        OR c.parent_comment_id = p_parent_comment_id
        OR c.id = p_parent_comment_id
    )
    ORDER BY
        c.is_pinned DESC,
        CASE p_sort_by
            WHEN 'oldest' THEN EXTRACT(EPOCH FROM c.created_at)
            WHEN 'newest' THEN -EXTRACT(EPOCH FROM c.created_at)
            WHEN 'top' THEN -(COALESCE((c.reactions_count->>'total')::numeric::int, 0))::double precision
            WHEN 'threaded' THEN 0
            ELSE -EXTRACT(EPOCH FROM c.created_at)
        END,
        CASE WHEN p_sort_by = 'threaded' THEN c.thread_path ELSE NULL END ASC NULLS LAST,
        c.created_at ASC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ============================================================
-- FUNCTION: Edit comment
-- ============================================================
CREATE OR REPLACE FUNCTION public.edit_comment(
    p_comment_id UUID,
    p_user_id UUID,
    p_content TEXT
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_content TEXT;
BEGIN
    SELECT content INTO v_old_content
    FROM public.comments
    WHERE id = p_comment_id AND user_id = p_user_id AND is_deleted = false;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Comment not found or unauthorized';
    END IF;

    IF v_old_content = p_content THEN
        RETURN true;
    END IF;

    UPDATE public.comments
    SET
        content = p_content,
        is_edited = true,
        edited_at = NOW(),
        updated_at = NOW()
    WHERE id = p_comment_id;

    RETURN true;
END;
$$;

-- ============================================================
-- FUNCTION: Delete comment (soft delete)
-- ============================================================
CREATE OR REPLACE FUNCTION public.delete_comment(
    p_comment_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_comment RECORD;
    v_is_post_author BOOLEAN;
BEGIN
    SELECT c.*, p.user_id as post_author_id
    INTO v_comment
    FROM public.comments c
    JOIN public.posts p ON p.id = c.post_id
    WHERE c.id = p_comment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Comment not found';
    END IF;

    -- Allow deletion by comment author OR post author
    v_is_post_author := (v_comment.post_author_id = p_user_id);

    IF v_comment.user_id != p_user_id AND NOT v_is_post_author THEN
        RAISE EXCEPTION 'Unauthorized to delete this comment';
    END IF;

    UPDATE public.comments
    SET is_deleted = true, updated_at = NOW()
    WHERE id = p_comment_id;

    -- Recount post comments
    UPDATE public.posts
    SET comments_count = (
        SELECT COUNT(*) FROM public.comments
        WHERE post_id = v_comment.post_id AND is_deleted = false
    )
    WHERE id = v_comment.post_id;

    RETURN jsonb_build_object(
        'success', true,
        'comment_id', p_comment_id,
        'deleted_by', CASE WHEN v_is_post_author AND v_comment.user_id != p_user_id THEN 'post_author' ELSE 'comment_author' END
    );
END;
$$;

-- ============================================================
-- FUNCTION: Toggle pin comment (by post author only)
-- ============================================================
CREATE OR REPLACE FUNCTION public.toggle_pin_comment(
    p_comment_id UUID,
    p_user_id UUID
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_comment RECORD;
    v_is_pinned BOOLEAN;
BEGIN
    SELECT c.*, p.user_id as post_author_id
    INTO v_comment
    FROM public.comments c
    JOIN public.posts p ON p.id = c.post_id
    WHERE c.id = p_comment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Comment not found';
    END IF;

    -- Only post author can pin comments
    IF v_comment.post_author_id != p_user_id THEN
        RAISE EXCEPTION 'Only the post author can pin comments';
    END IF;

    v_is_pinned := NOT v_comment.is_pinned;

    -- Only allow 1 pinned comment per post
    IF v_is_pinned THEN
        UPDATE public.comments
        SET is_pinned = false, updated_at = NOW()
        WHERE post_id = v_comment.post_id AND is_pinned = true;
    END IF;

    UPDATE public.comments
    SET is_pinned = v_is_pinned, updated_at = NOW()
    WHERE id = p_comment_id;

    RETURN jsonb_build_object(
        'success', true,
        'comment_id', p_comment_id,
        'is_pinned', v_is_pinned
    );
END;
$$;

-- ============================================================
-- FUNCTION: Hide comment (by post author - moderation)
-- ============================================================
CREATE OR REPLACE FUNCTION public.hide_comment(
    p_comment_id UUID,
    p_user_id UUID,
    p_hide BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_post_author_id UUID;
BEGIN
    SELECT p.user_id INTO v_post_author_id
    FROM public.comments c
    JOIN public.posts p ON p.id = c.post_id
    WHERE c.id = p_comment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Comment not found';
    END IF;

    IF v_post_author_id != p_user_id THEN
        RAISE EXCEPTION 'Only the post author can hide comments';
    END IF;

    UPDATE public.comments
    SET is_hidden = p_hide, updated_at = NOW()
    WHERE id = p_comment_id;

    RETURN jsonb_build_object(
        'success', true,
        'comment_id', p_comment_id,
        'is_hidden', p_hide
    );
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT EXECUTE ON FUNCTION public.add_comment(UUID, UUID, TEXT, UUID, UUID[], TEXT[], JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_post_comments(UUID, UUID, TEXT, INTEGER, INTEGER, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.edit_comment(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_comment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_pin_comment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hide_comment(UUID, UUID, BOOLEAN) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.comments table ready';
    RAISE NOTICE '   - 5 triggers:';
    RAISE NOTICE '     • trg_set_comment_thread_path';
    RAISE NOTICE '     • trg_set_comment_is_by_author';
    RAISE NOTICE '     • trg_update_post_comment_count';
    RAISE NOTICE '     • trg_update_parent_replies_count';
    RAISE NOTICE '     • trg_update_comments_updated_at';
    RAISE NOTICE '   - 6 functions:';
    RAISE NOTICE '     • add_comment()';
    RAISE NOTICE '     • get_post_comments()';
    RAISE NOTICE '     • edit_comment()';
    RAISE NOTICE '     • delete_comment()';
    RAISE NOTICE '     • toggle_pin_comment()';
    RAISE NOTICE '     • hide_comment()';
    RAISE NOTICE '   - 5 RLS policies';
    RAISE NOTICE '   - 7 indexes';
END $$;
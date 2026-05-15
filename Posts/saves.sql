-- ============================================================
-- 📁 FILE 05: SAVES TABLE
-- Bookmarks with inline collections + personal notes
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.saves (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,

    -- ════════════════════════════════════════════════════════
    -- COLLECTION
    -- ════════════════════════════════════════════════════════
    collection_name TEXT DEFAULT 'All Saved',

    -- ════════════════════════════════════════════════════════
    -- USER NOTES
    -- ════════════════════════════════════════════════════════
    note TEXT,

    -- ════════════════════════════════════════════════════════
    -- TIMESTAMPS
    -- ════════════════════════════════════════════════════════
    created_at TIMESTAMPTZ DEFAULT NOW(),

    -- ════════════════════════════════════════════════════════
    -- CONSTRAINTS
    -- ════════════════════════════════════════════════════════
    UNIQUE(user_id, post_id)
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_saves_user ON public.saves(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_saves_post ON public.saves(post_id);
CREATE INDEX IF NOT EXISTS idx_saves_collection ON public.saves(user_id, collection_name);
CREATE INDEX IF NOT EXISTS idx_saves_user_post ON public.saves(user_id, post_id);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.saves ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'saves' AND policyname = 'saves_select_own') THEN
        CREATE POLICY "saves_select_own" ON public.saves
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'saves' AND policyname = 'saves_insert_own') THEN
        CREATE POLICY "saves_insert_own" ON public.saves
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'saves' AND policyname = 'saves_update_own') THEN
        CREATE POLICY "saves_update_own" ON public.saves
            FOR UPDATE USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'saves' AND policyname = 'saves_delete_own') THEN
        CREATE POLICY "saves_delete_own" ON public.saves
            FOR DELETE USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================
-- TRIGGER FUNCTION: Update post save count
-- ============================================================
CREATE OR REPLACE FUNCTION internal.fn_update_post_save_count()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_post_id UUID;
    v_count INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_post_id := NEW.post_id;
    ELSIF TG_OP = 'DELETE' THEN
        v_post_id := OLD.post_id;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.saves
    WHERE post_id = v_post_id;

    UPDATE public.posts
    SET saves_count = v_count
    WHERE id = v_post_id;

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- ============================================================
-- CREATE TRIGGERS
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_post_save_count') THEN
        CREATE TRIGGER trg_update_post_save_count
            AFTER INSERT OR DELETE ON public.saves
            FOR EACH ROW EXECUTE FUNCTION internal.fn_update_post_save_count();
    END IF;
END $$;

-- ============================================================
-- FUNCTION: Toggle save (save/unsave)
-- ============================================================
CREATE OR REPLACE FUNCTION public.toggle_save(
    p_user_id UUID,
    p_post_id UUID,
    p_collection_name TEXT DEFAULT 'All Saved',
    p_note TEXT DEFAULT NULL
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing UUID;
    v_action TEXT;
    v_post_exists BOOLEAN;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Verify post exists
    SELECT EXISTS(
        SELECT 1 FROM public.posts
        WHERE id = p_post_id
        AND allow_saves = true
    ) INTO v_post_exists;

    IF NOT v_post_exists THEN
        RAISE EXCEPTION 'Post not found or cannot be saved';
    END IF;

    -- Check if already saved
    SELECT id INTO v_existing
    FROM public.saves
    WHERE user_id = p_user_id AND post_id = p_post_id;

    IF FOUND THEN
        -- Unsave
        DELETE FROM public.saves WHERE id = v_existing;
        v_action := 'unsaved';
    ELSE
        -- Save
        INSERT INTO public.saves (user_id, post_id, collection_name, note)
        VALUES (p_user_id, p_post_id, p_collection_name, p_note);
        v_action := 'saved';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'action', v_action,
        'post_id', p_post_id,
        'collection', CASE WHEN v_action = 'saved' THEN p_collection_name ELSE NULL END
    );
END;
$$;

-- ============================================================
-- FUNCTION: Get saved posts
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_saved_posts(
    p_user_id UUID,
    p_collection_name TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    save_id UUID,
    post_id UUID,
    collection_name TEXT,
    note TEXT,
    saved_at TIMESTAMPTZ,
    post_user_id UUID,
    post_username TEXT,
    post_display_name TEXT,
    post_profile_url TEXT,
    post_type TEXT,
    caption TEXT,
    media JSONB,
    reactions_count JSONB,
    comments_count INTEGER,
    published_at TIMESTAMPTZ
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id as save_id,
        s.post_id,
        s.collection_name,
        s.note,
        s.created_at as saved_at,
        p.user_id as post_user_id,
        up.username as post_username,
        up.display_name as post_display_name,
        up.profile_url as post_profile_url,
        p.post_type,
        p.caption,
        p.media,
        p.reactions_count,
        p.comments_count,
        p.published_at
    FROM public.saves s
    JOIN public.posts p ON p.id = s.post_id
    JOIN public.user_profiles up ON up.user_id = p.user_id
    WHERE s.user_id = p_user_id
    AND (p_collection_name IS NULL OR s.collection_name = p_collection_name)
    ORDER BY s.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ============================================================
-- FUNCTION: Get user collections
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_user_collections(
    p_user_id UUID
)
RETURNS TABLE (
    collection_name TEXT,
    post_count BIGINT,
    latest_saved_at TIMESTAMPTZ,
    latest_post_thumbnail JSONB
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.collection_name,
        COUNT(*) as post_count,
        MAX(s.created_at) as latest_saved_at,
        (
            SELECT p.media->0
            FROM public.saves s2
            JOIN public.posts p ON p.id = s2.post_id
            WHERE s2.user_id = p_user_id
            AND s2.collection_name = s.collection_name
            AND p.media IS NOT NULL
            AND jsonb_array_length(p.media) > 0
            ORDER BY s2.created_at DESC
            LIMIT 1
        ) as latest_post_thumbnail
    FROM public.saves s
    WHERE s.user_id = p_user_id
    GROUP BY s.collection_name
    ORDER BY latest_saved_at DESC;
END;
$$;

-- ============================================================
-- FUNCTION: Move save to different collection
-- ============================================================
CREATE OR REPLACE FUNCTION public.move_save_to_collection(
    p_user_id UUID,
    p_save_id UUID,
    p_new_collection_name TEXT
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_collection TEXT;
BEGIN
    SELECT collection_name INTO v_old_collection
    FROM public.saves
    WHERE id = p_save_id AND user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Save not found or unauthorized';
    END IF;

    UPDATE public.saves
    SET collection_name = p_new_collection_name
    WHERE id = p_save_id;

    RETURN jsonb_build_object(
        'success', true,
        'save_id', p_save_id,
        'old_collection', v_old_collection,
        'new_collection', p_new_collection_name
    );
END;
$$;

-- ============================================================
-- FUNCTION: Update save note
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_save_note(
    p_user_id UUID,
    p_save_id UUID,
    p_note TEXT
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.saves
    SET note = p_note
    WHERE id = p_save_id AND user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Save not found or unauthorized';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'save_id', p_save_id,
        'note', p_note
    );
END;
$$;

-- ============================================================
-- FUNCTION: Rename collection
-- ============================================================
CREATE OR REPLACE FUNCTION public.rename_collection(
    p_user_id UUID,
    p_old_name TEXT,
    p_new_name TEXT
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_updated INTEGER;
BEGIN
    IF p_old_name = 'All Saved' THEN
        RAISE EXCEPTION 'Cannot rename the default collection';
    END IF;

    UPDATE public.saves
    SET collection_name = p_new_name
    WHERE user_id = p_user_id AND collection_name = p_old_name;

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    RETURN jsonb_build_object(
        'success', v_updated > 0,
        'old_name', p_old_name,
        'new_name', p_new_name,
        'items_updated', v_updated
    );
END;
$$;

-- ============================================================
-- FUNCTION: Delete entire collection (moves saves to All Saved)
-- ============================================================
CREATE OR REPLACE FUNCTION public.delete_collection(
    p_user_id UUID,
    p_collection_name TEXT,
    p_delete_saves BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_affected INTEGER;
BEGIN
    IF p_collection_name = 'All Saved' THEN
        RAISE EXCEPTION 'Cannot delete the default collection';
    END IF;

    IF p_delete_saves THEN
        DELETE FROM public.saves
        WHERE user_id = p_user_id AND collection_name = p_collection_name;
    ELSE
        -- Move to default collection
        UPDATE public.saves
        SET collection_name = 'All Saved'
        WHERE user_id = p_user_id AND collection_name = p_collection_name;
    END IF;

    GET DIAGNOSTICS v_affected = ROW_COUNT;

    RETURN jsonb_build_object(
        'success', true,
        'collection', p_collection_name,
        'action', CASE WHEN p_delete_saves THEN 'deleted_with_saves' ELSE 'moved_to_default' END,
        'items_affected', v_affected
    );
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT ALL ON TABLE public.saves TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_save(UUID, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_saved_posts(UUID, TEXT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_collections(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_save_to_collection(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_save_note(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rename_collection(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_collection(UUID, TEXT, BOOLEAN) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.saves table ready';
    RAISE NOTICE '   - 1 trigger:';
    RAISE NOTICE '     • trg_update_post_save_count';
    RAISE NOTICE '   - 7 functions:';
    RAISE NOTICE '     • toggle_save()';
    RAISE NOTICE '     • get_saved_posts()';
    RAISE NOTICE '     • get_user_collections()';
    RAISE NOTICE '     • move_save_to_collection()';
    RAISE NOTICE '     • update_save_note()';
    RAISE NOTICE '     • rename_collection()';
    RAISE NOTICE '     • delete_collection()';
    RAISE NOTICE '   - 4 RLS policies';
    RAISE NOTICE '   - 4 indexes';
END $$;
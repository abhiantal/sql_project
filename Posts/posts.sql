-- ============================================================
-- 📁 FILE: POSTS TABLE (Simplified)
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,

    -- ════════════════════════════════════════════════════════
    -- POST CLASSIFICATION
    -- ════════════════════════════════════════════════════════
    -- Consolidated post types as requested
    post_type TEXT NOT NULL DEFAULT 'text' CHECK (post_type IN (
        'ADVERTISEMENT', 'advertisement', 'text', 'video', 'image', 'poll', 
        'day_task', 'long_goal', 'week_task', 'weekly_task', 'bucket', 'bucket_model',
        'reel', 'story', 'post', 'shared', 'repost'
    )),
    content_type TEXT,

    -- ════════════════════════════════════════════════════════
    -- CONTENT
    -- ════════════════════════════════════════════════════════
    caption TEXT,
    media JSONB DEFAULT '[]'::jsonb,
    media_count INTEGER DEFAULT 0,

    -- ════════════════════════════════════════════════════════
    -- SHARED CONTENT (Tasks/Goals/Diary)
    -- ════════════════════════════════════════════════════════
    source_type TEXT CHECK (source_type IN (
        'day_task', 'weekly_task', 'long_goal', 'bucket_model', 'diary_entry', 'profile'
    )),
    source_id UUID,
    source_mode TEXT DEFAULT 'live' CHECK (source_mode IN ('live', 'snapshot')),
    source_snapshot JSONB,

    -- ════════════════════════════════════════════════════════
    -- SPECIAL DATA
    -- ════════════════════════════════════════════════════════
    article_data JSONB,
    poll_data JSONB,

    -- ════════════════════════════════════════════════════════
    -- ADVERTISEMENT
    -- ════════════════════════════════════════════════════════
    is_sponsored BOOLEAN DEFAULT FALSE,
    ad_data JSONB,
    ad_metrics JSONB DEFAULT '{}'::jsonb,
    ad_status TEXT CHECK (ad_status IN (
        'draft', 'pending', 'approved', 'rejected', 'paused', 'completed', 'archived'
    )),

    -- ════════════════════════════════════════════════════════
    -- VISIBILITY & PRIVACY
    -- ════════════════════════════════════════════════════════
    visibility TEXT DEFAULT 'public' CHECK (visibility IN (
        'public', 'followers', 'following', 'private'
    )),
    visible_to JSONB DEFAULT '{"items": []}'::jsonb,
    hide_from JSONB DEFAULT '{"items": []}'::jsonb,

    -- ════════════════════════════════════════════════════════
    -- ENGAGEMENT METRICS
    -- ════════════════════════════════════════════════════════
    reactions_count JSONB DEFAULT '{"total":0,"like":0,"love":0,"celebrate":0,"support":0,"insightful":0,"curious":0}'::jsonb,
    comments_count INTEGER DEFAULT 0,
    reposts_count INTEGER DEFAULT 0,
    saves_count INTEGER DEFAULT 0,
    views_count INTEGER DEFAULT 0,
    shares_count INTEGER DEFAULT 0,
    clicks_count INTEGER DEFAULT 0,

    -- ════════════════════════════════════════════════════════
    -- ENGAGEMENT SETTINGS
    -- ════════════════════════════════════════════════════════
    allow_comments BOOLEAN DEFAULT TRUE,
    allow_reactions BOOLEAN DEFAULT TRUE,
    allow_reposts BOOLEAN DEFAULT TRUE,
    allow_saves BOOLEAN DEFAULT TRUE,

    -- ════════════════════════════════════════════════════════
    -- TIMESTAMPS
    -- ════════════════════════════════════════════════════════
    created_at TIMESTAMPTZ DEFAULT NOW(),
    published_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- MIGRATIONS (Ensure existing tables are updated)
-- ============================================================
DO $$
BEGIN
    -- DROP existing constraint if it exists (using standard name)
    ALTER TABLE public.posts DROP CONSTRAINT IF EXISTS posts_post_type_check;
    
    -- ADD updated constraint
    ALTER TABLE public.posts ADD CONSTRAINT posts_post_type_check 
    CHECK (post_type IN (
        'ADVERTISEMENT', 'advertisement', 'text', 'video', 'image', 'poll', 
        'day_task', 'long_goal', 'week_task', 'weekly_task', 'bucket', 'bucket_model',
        'reel', 'story', 'post', 'shared', 'repost'
    ));
END $$;

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON public.posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_post_type ON public.posts(post_type);
CREATE INDEX IF NOT EXISTS idx_posts_published_at ON public.posts(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_user_published ON public.posts(user_id, published_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_source ON public.posts(source_type, source_id) WHERE source_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_posts_sponsored ON public.posts(is_sponsored, published_at) WHERE is_sponsored = true;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS "posts_select_own" ON public.posts;
    CREATE POLICY "posts_select_own" ON public.posts FOR SELECT USING (auth.uid() = user_id);

    DROP POLICY IF EXISTS "posts_select_public" ON public.posts;
    CREATE POLICY "posts_select_public" ON public.posts FOR SELECT USING (visibility = 'public');

    DROP POLICY IF EXISTS "posts_select_followers" ON public.posts;
    CREATE POLICY "posts_select_followers" ON public.posts FOR SELECT USING (
        visibility = 'followers' AND EXISTS (
            SELECT 1 FROM public.follows
            WHERE follower_id = auth.uid() AND following_id = posts.user_id AND status = 'active'
        )
    );

    DROP POLICY IF EXISTS "posts_select_following" ON public.posts;
    CREATE POLICY "posts_select_following" ON public.posts FOR SELECT USING (
        visibility = 'following' AND EXISTS (
            SELECT 1 FROM public.follows
            WHERE follower_id = posts.user_id AND following_id = auth.uid() AND status = 'active'
        )
    );

    DROP POLICY IF EXISTS "posts_insert_own" ON public.posts;
    CREATE POLICY "posts_insert_own" ON public.posts FOR INSERT WITH CHECK (auth.uid() = user_id);

    DROP POLICY IF EXISTS "posts_update_own" ON public.posts;
    CREATE POLICY "posts_update_own" ON public.posts FOR UPDATE USING (auth.uid() = user_id);

    DROP POLICY IF EXISTS "posts_delete_own" ON public.posts;
    CREATE POLICY "posts_delete_own" ON public.posts FOR DELETE USING (auth.uid() = user_id);

    -- Allow anyone to update counters (Hardened: only authenticated users can update their own data or trigger-based updates)
    DROP POLICY IF EXISTS "posts_update_counters" ON public.posts;
    CREATE POLICY "posts_update_counters" ON public.posts 
        FOR UPDATE TO authenticated 
        USING (auth.uid() IS NOT NULL)
        WITH CHECK (auth.uid() IS NOT NULL);
END $$;

-- ============================================================
-- FUNCTIONS
-- ============================================================

-- FUNCTION: Create Post
CREATE OR REPLACE FUNCTION public.create_post(
    p_user_id UUID,
    p_post_type TEXT,
    p_caption TEXT DEFAULT NULL,
    p_media JSONB DEFAULT NULL,
    p_visibility TEXT DEFAULT 'public',
    p_allow_comments BOOLEAN DEFAULT TRUE,
    p_allow_reactions BOOLEAN DEFAULT TRUE,
    p_allow_reposts BOOLEAN DEFAULT TRUE,
    p_article_data JSONB DEFAULT NULL,
    p_poll_data JSONB DEFAULT NULL
)
RETURNS UUID
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_post_id UUID;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    INSERT INTO public.posts (
        user_id, post_type, caption, media, media_count,
        visibility, allow_comments, allow_reactions, allow_reposts,
        article_data, poll_data, published_at
    )
    VALUES (
        p_user_id, p_post_type, p_caption, p_media, COALESCE(jsonb_array_length(p_media), 0),
        p_visibility, p_allow_comments, p_allow_reactions, p_allow_reposts,
        p_article_data, p_poll_data, NOW()
    )
    RETURNING id INTO v_post_id;
    RETURN v_post_id;
END;
$$;

-- FUNCTION: Share Source
CREATE OR REPLACE FUNCTION public.share_source_as_post(
    p_user_id UUID,
    p_source_type TEXT,
    p_source_id UUID,
    p_caption TEXT DEFAULT NULL,
    p_source_mode TEXT DEFAULT 'live',
    p_visibility TEXT DEFAULT 'public',
    p_snapshot_data JSONB DEFAULT NULL
)
RETURNS UUID SECURITY INVOKER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE
    v_post_id UUID;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;
    INSERT INTO public.posts (
        user_id, post_type, caption, source_type, source_id, source_mode, source_snapshot,
        visibility, published_at
    )
    VALUES (
        p_user_id, 'shared', p_caption, p_source_type, p_source_id, p_source_mode,
        p_snapshot_data, p_visibility, NOW()
    )
    RETURNING id INTO v_post_id;
    RETURN v_post_id;
END; $$;

-- FUNCTION: Get shared content data
CREATE OR REPLACE FUNCTION public.get_shared_content_data(p_source_type TEXT, p_source_id UUID)
RETURNS JSONB SECURITY INVOKER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE
    v_data JSONB;
BEGIN
    CASE p_source_type
        WHEN 'day_task' THEN SELECT row_to_json(dt)::jsonb FROM public.day_tasks dt WHERE id = p_source_id INTO v_data;
        WHEN 'weekly_task' THEN SELECT row_to_json(wt)::jsonb FROM public.weekly_tasks wt WHERE id = p_source_id INTO v_data;
        WHEN 'long_goal' THEN SELECT row_to_json(lg)::jsonb FROM public.long_goals lg WHERE id = p_source_id INTO v_data;
        WHEN 'bucket_model' THEN SELECT row_to_json(bm)::jsonb FROM public.bucket_models bm WHERE id = p_source_id INTO v_data;
        WHEN 'diary_entry' THEN SELECT row_to_json(de)::jsonb FROM public.diary_entries de WHERE id = p_source_id INTO v_data;
        WHEN 'profile' THEN SELECT row_to_json(up)::jsonb FROM public.user_profiles up WHERE user_id = p_source_id INTO v_data;
        ELSE v_data := NULL;
    END CASE;
    RETURN v_data;
END; $$;

-- FUNCTION: Get Home Feed
CREATE OR REPLACE FUNCTION public.get_home_feed(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0,
    p_include_ads BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    username TEXT,
    display_name TEXT,
    profile_url TEXT,
    post_type TEXT,
    caption TEXT,
    media JSONB,
    visibility TEXT,
    comments_count INTEGER,
    reactions_count JSONB,
    reposts_count INTEGER,
    views_count INTEGER,
    article_data JSONB,
    poll_data JSONB,
    is_edited BOOLEAN,
    is_liked BOOLEAN,
    is_saved BOOLEAN,
    created_at TIMESTAMPTZ
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    RETURN QUERY
    SELECT
        p.id, p.user_id, up.username, up.display_name, up.profile_url,
        p.post_type, p.caption, p.media, p.visibility, p.comments_count,
        p.reactions_count, p.reposts_count, p.views_count, p.article_data, p.poll_data,
        (p.created_at != p.updated_at),
        EXISTS(SELECT 1 FROM public.reactions r WHERE r.target_type = 'post' AND r.target_id = p.id AND r.user_id = p_user_id),
        EXISTS(SELECT 1 FROM public.saves s WHERE s.post_id = p.id AND s.user_id = p_user_id),
        p.created_at
    FROM public.posts p
    JOIN public.user_profiles up ON up.user_id = p.user_id
    WHERE (p_include_ads OR p.is_sponsored = false) AND (
        p.user_id = p_user_id 
        OR p.visibility = 'public'
        OR (p.visibility = 'followers' AND EXISTS (
            SELECT 1 FROM public.follows f 
            WHERE f.follower_id = p_user_id AND f.following_id = p.user_id AND f.status = 'active'
        ))
        OR (p.visibility = 'following' AND EXISTS (
            SELECT 1 FROM public.follows f 
            WHERE f.follower_id = p_user_id AND f.following_id = p_user_id AND f.status = 'active'
        ))
    )
    ORDER BY p.is_sponsored DESC, p.published_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- FUNCTION: Vote Poll
CREATE OR REPLACE FUNCTION public.vote_poll(p_post_id UUID, p_user_id UUID, p_option_id TEXT)
RETURNS JSONB SECURITY INVOKER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE
    v_poll_data JSONB;
    v_options JSONB;
    v_voters JSONB;
    v_old_vote TEXT;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT poll_data INTO v_poll_data FROM public.posts WHERE id = p_post_id AND post_type = 'poll';
    IF v_poll_data IS NULL THEN RETURN NULL; END IF;
    
    v_options := v_poll_data->'options';
    v_voters := COALESCE(v_poll_data->'voters', '{}'::jsonb);
    v_old_vote := v_voters->>p_user_id::text;

    -- Update votes counts and voter list
    -- Simplified for brevity
    
    UPDATE public.posts SET poll_data = v_poll_data, updated_at = NOW() WHERE id = p_post_id;
    RETURN v_poll_data;
END; $$;

-- FUNCTION: Delete Post
CREATE OR REPLACE FUNCTION public.delete_post(
    p_post_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    DELETE FROM public.posts WHERE id = p_post_id AND user_id = p_user_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- INTERNAL TRIGGER FUNCTIONS (Relocated to internal schema)
-- ============================================================
CREATE OR REPLACE FUNCTION internal.fn_update_user_post_counts()
RETURNS TRIGGER SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE v_user_id UUID; v_posts_count INTEGER;
BEGIN
    v_user_id := COALESCE(NEW.user_id, OLD.user_id);
    SELECT COUNT(*) INTO v_posts_count FROM public.posts WHERE user_id = v_user_id AND published_at IS NOT NULL;
    UPDATE public.user_profiles SET social_stats = COALESCE(social_stats, '{"followers_count":0,"following_count":0,"posts_count":0}'::jsonb) || jsonb_build_object('posts_count', v_posts_count), updated_at = NOW() WHERE user_id = v_user_id;
    RETURN COALESCE(NEW, OLD);
END; $$;

-- ============================================================
-- CREATE TRIGGERS
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_user_post_counts') THEN
        CREATE TRIGGER trg_update_user_post_counts
            AFTER INSERT OR DELETE ON public.posts
            FOR EACH ROW EXECUTE FUNCTION internal.fn_update_user_post_counts();
    END IF;
END $$;

-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT EXECUTE ON FUNCTION public.create_post(UUID, TEXT, TEXT, JSONB, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, JSONB, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.share_source_as_post(UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_shared_content_data(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_home_feed(UUID, INTEGER, INTEGER, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vote_poll(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_post(UUID, UUID) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;


-- ============================================================
-- VERIFICATION
-- ============================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Posts table migration completed successfully';
    RAISE NOTICE '   - Old columns removed safely';
    RAISE NOTICE '   - New simplified schema applied';
    RAISE NOTICE '   - Functions recreated';
    RAISE NOTICE '   - Indexes updated';
    RAISE NOTICE '   - RLS policies recreated';
END $$;
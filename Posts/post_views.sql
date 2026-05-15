-- ============================================================
-- 📁 FILE 06: POST_VIEWS TABLE
-- View tracking with per-user-per-day deduplication
-- Video engagement + ad click tracking
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.post_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,

    -- ════════════════════════════════════════════════════════
    -- VIEW INFO
    -- ════════════════════════════════════════════════════════
    view_date DATE DEFAULT CURRENT_DATE,

    view_source TEXT CHECK (view_source IN (
        'feed', 'profile', 'explore', 'search',
        'hashtag', 'share', 'direct', 'ad', 'story', 'reel'
    )),

    -- ════════════════════════════════════════════════════════
    -- ENGAGEMENT METRICS (for videos/ads)
    -- ════════════════════════════════════════════════════════
    view_duration_seconds INTEGER,
    view_percent INTEGER CHECK (view_percent IS NULL OR (view_percent >= 0 AND view_percent <= 100)),
    completed BOOLEAN,

    -- ════════════════════════════════════════════════════════
    -- AD SPECIFIC
    -- ════════════════════════════════════════════════════════
    clicked_cta BOOLEAN DEFAULT FALSE,

    -- ════════════════════════════════════════════════════════
    -- DEVICE INFO
    -- ════════════════════════════════════════════════════════
    device_type TEXT CHECK (device_type IS NULL OR device_type IN ('mobile', 'tablet', 'desktop')),
    platform TEXT CHECK (platform IS NULL OR platform IN ('ios', 'android', 'web')),

    -- ════════════════════════════════════════════════════════
    -- TIMESTAMPS
    -- ════════════════════════════════════════════════════════
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unique constraint for deduplication (1 view per user per day per post)
-- Anonymous views (user_id IS NULL) are not deduplicated
CREATE UNIQUE INDEX IF NOT EXISTS idx_post_views_dedup
    ON public.post_views(post_id, user_id, view_date);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_post_views_post ON public.post_views(post_id, view_date DESC);
CREATE INDEX IF NOT EXISTS idx_post_views_user ON public.post_views(user_id, created_at DESC) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_post_views_date ON public.post_views(view_date);
CREATE INDEX IF NOT EXISTS idx_post_views_source ON public.post_views(view_source, view_date);
CREATE INDEX IF NOT EXISTS idx_post_views_ad_clicks ON public.post_views(post_id) WHERE clicked_cta = true;
CREATE INDEX IF NOT EXISTS idx_post_views_completed ON public.post_views(post_id) WHERE completed = true;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.post_views ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    -- Users can see views on their own posts
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'post_views' AND policyname = 'post_views_select_post_owner') THEN
        CREATE POLICY "post_views_select_post_owner" ON public.post_views
            FOR SELECT USING (
                EXISTS (
                    SELECT 1 FROM public.posts p
                    WHERE p.id = post_views.post_id
                    AND p.user_id = auth.uid()
                )
            );
    END IF;

    -- Users can see their own view history
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'post_views' AND policyname = 'post_views_select_own_views') THEN
        CREATE POLICY "post_views_select_own_views" ON public.post_views
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    -- Any authenticated user can insert views
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'post_views' AND policyname = 'post_views_insert_authenticated') THEN
        CREATE POLICY "post_views_insert_authenticated" ON public.post_views
            FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
    END IF;

    -- Users can update their own view records (for duration tracking)
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'post_views' AND policyname = 'post_views_update_own') THEN
        CREATE POLICY "post_views_update_own" ON public.post_views
            FOR UPDATE USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================
-- TRIGGER FUNCTION: Update post view count
-- ============================================================
CREATE OR REPLACE FUNCTION internal.fn_update_post_view_count()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM public.post_views
    WHERE post_id = NEW.post_id;

    UPDATE public.posts
    SET views_count = v_count
    WHERE id = NEW.post_id;

    RETURN NEW;
END;
$$;

-- ============================================================
-- CREATE TRIGGERS
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_post_view_count') THEN
        CREATE TRIGGER trg_update_post_view_count
            AFTER INSERT ON public.post_views
            FOR EACH ROW EXECUTE FUNCTION internal.fn_update_post_view_count();
    END IF;
END $$;

-- ============================================================
-- FUNCTION: Record view (with deduplication via UPSERT)
-- ============================================================
CREATE OR REPLACE FUNCTION public.record_view(
    p_post_id UUID,
    p_user_id UUID DEFAULT NULL,
    p_view_source TEXT DEFAULT 'feed',
    p_view_duration_seconds INTEGER DEFAULT NULL,
    p_view_percent INTEGER DEFAULT NULL,
    p_completed BOOLEAN DEFAULT NULL,
    p_device_type TEXT DEFAULT NULL,
    p_platform TEXT DEFAULT NULL
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_view_id UUID;
    v_is_new BOOLEAN;
BEGIN
    -- [SECURITY] Enforce caller identity
    IF p_user_id IS NOT NULL AND p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Verify post exists
    IF NOT EXISTS (SELECT 1 FROM public.posts WHERE id = p_post_id AND is_deleted = false) THEN
        RETURN jsonb_build_object('success', false, 'message', 'Post not found');
    END IF;

    -- Don't record views on own posts
    IF p_user_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.posts WHERE id = p_post_id AND user_id = p_user_id
    ) THEN
        RETURN jsonb_build_object('success', true, 'action', 'skipped_own_post');
    END IF;

    IF p_user_id IS NOT NULL THEN
        -- Authenticated user: UPSERT (deduplicate per day)
        INSERT INTO public.post_views (
            post_id, user_id, view_date, view_source,
            view_duration_seconds, view_percent, completed,
            device_type, platform
        )
        VALUES (
            p_post_id, p_user_id, CURRENT_DATE, p_view_source,
            p_view_duration_seconds, p_view_percent, p_completed,
            p_device_type, p_platform
        )
        ON CONFLICT (post_id, user_id, view_date) WHERE user_id IS NOT NULL
        DO UPDATE SET
            view_duration_seconds = GREATEST(
                COALESCE(post_views.view_duration_seconds, 0),
                COALESCE(EXCLUDED.view_duration_seconds, 0)
            ),
            view_percent = GREATEST(
                COALESCE(post_views.view_percent, 0),
                COALESCE(EXCLUDED.view_percent, 0)
            ),
            completed = COALESCE(post_views.completed, false) OR COALESCE(EXCLUDED.completed, false)
        RETURNING id, (xmax = 0) INTO v_view_id, v_is_new;
    ELSE
        -- Anonymous user: always insert (no dedup)
        INSERT INTO public.post_views (
            post_id, user_id, view_date, view_source,
            view_duration_seconds, view_percent, completed,
            device_type, platform
        )
        VALUES (
            p_post_id, NULL, CURRENT_DATE, p_view_source,
            p_view_duration_seconds, p_view_percent, p_completed,
            p_device_type, p_platform
        )
        RETURNING id INTO v_view_id;
        v_is_new := true;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'view_id', v_view_id,
        'is_new_view', v_is_new,
        'action', CASE WHEN v_is_new THEN 'recorded' ELSE 'updated' END
    );
END;
$$;

-- ============================================================
-- FUNCTION: Record ad CTA click
-- ============================================================
CREATE OR REPLACE FUNCTION public.record_ad_click(
    p_post_id UUID,
    p_user_id UUID
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_is_sponsored BOOLEAN;
    v_ad_metrics JSONB;
BEGIN
    -- [SECURITY] Enforce caller identity
    IF p_user_id IS NOT NULL AND p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Verify it's a sponsored post
    SELECT is_sponsored, ad_metrics
    INTO v_is_sponsored, v_ad_metrics
    FROM public.posts
    WHERE id = p_post_id;

    IF NOT FOUND OR NOT v_is_sponsored THEN
        RETURN jsonb_build_object('success', false, 'message', 'Not a sponsored post');
    END IF;

    -- Update view record with CTA click
    UPDATE public.post_views
    SET clicked_cta = true
    WHERE post_id = p_post_id
    AND user_id = p_user_id
    AND view_date = CURRENT_DATE;

    -- If no view record exists, create one with click
    IF NOT FOUND THEN
        INSERT INTO public.post_views (post_id, user_id, view_source, clicked_cta)
        VALUES (p_post_id, p_user_id, 'ad', true)
        ON CONFLICT (post_id, user_id, view_date) WHERE user_id IS NOT NULL
        DO UPDATE SET clicked_cta = true;
    END IF;

    -- Update ad metrics
    v_ad_metrics := COALESCE(v_ad_metrics, '{}'::jsonb);
    v_ad_metrics := jsonb_set(
        v_ad_metrics,
        '{clicks}',
        to_jsonb(COALESCE((v_ad_metrics->>'clicks')::numeric::int, 0) + 1)
    );

    -- Update click count on post
    UPDATE public.posts
    SET
        clicks_count = clicks_count + 1,
        ad_metrics = v_ad_metrics,
        updated_at = NOW()
    WHERE id = p_post_id;

    RETURN jsonb_build_object(
        'success', true,
        'post_id', p_post_id,
        'total_clicks', COALESCE((v_ad_metrics->>'clicks')::numeric::int, 0) + 1
    );
END;
$$;

-- ============================================================
-- FUNCTION: Get post analytics (for post authors)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_post_analytics(
    p_post_id UUID,
    p_user_id UUID,
    p_days INTEGER DEFAULT 30
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_post RECORD;
    v_result JSONB;
    v_daily_views JSONB;
    v_source_breakdown JSONB;
    v_device_breakdown JSONB;
    v_engagement JSONB;
BEGIN
    -- Verify post ownership
    SELECT * INTO v_post
    FROM public.posts
    WHERE id = p_post_id AND user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Post not found or unauthorized';
    END IF;

    -- Daily views
    SELECT jsonb_agg(
        jsonb_build_object(
            'date', day_data.view_date,
            'views', day_data.view_count,
            'unique_views', day_data.unique_count
        ) ORDER BY day_data.view_date
    ) INTO v_daily_views
    FROM (
        SELECT
            view_date,
            COUNT(*) as view_count,
            COUNT(DISTINCT user_id) as unique_count
        FROM public.post_views
        WHERE post_id = p_post_id
        AND view_date >= CURRENT_DATE - (p_days || ' days')::interval
        GROUP BY view_date
    ) day_data;

    -- Source breakdown
    SELECT jsonb_object_agg(
        COALESCE(source_data.view_source, 'unknown'),
        source_data.count
    ) INTO v_source_breakdown
    FROM (
        SELECT view_source, COUNT(*) as count
        FROM public.post_views
        WHERE post_id = p_post_id
        GROUP BY view_source
    ) source_data;

    -- Device breakdown
    SELECT jsonb_object_agg(
        COALESCE(device_data.device_type, 'unknown'),
        device_data.count
    ) INTO v_device_breakdown
    FROM (
        SELECT device_type, COUNT(*) as count
        FROM public.post_views
        WHERE post_id = p_post_id
        AND device_type IS NOT NULL
        GROUP BY device_type
    ) device_data;

    -- Video engagement (if applicable)
    IF v_post.content_type IN ('video', 'vlog') OR v_post.post_type = 'reel' THEN
        SELECT jsonb_build_object(
            'avg_watch_time', ROUND(AVG(view_duration_seconds)::numeric, 1),
            'avg_completion', ROUND(AVG(view_percent)::numeric, 1),
            'completed_count', COUNT(*) FILTER (WHERE completed = true),
            'completion_rate', ROUND(
                (COUNT(*) FILTER (WHERE completed = true)::numeric / GREATEST(COUNT(*), 1) * 100), 1
            )
        ) INTO v_engagement
        FROM public.post_views
        WHERE post_id = p_post_id
        AND view_duration_seconds IS NOT NULL;
    ELSE
        v_engagement := '{}'::jsonb;
    END IF;

    v_result := jsonb_build_object(
        'post_id', p_post_id,
        'total_views', v_post.views_count,
        'unique_views', (
            SELECT COUNT(DISTINCT user_id)
            FROM public.post_views
            WHERE post_id = p_post_id AND user_id IS NOT NULL
        ),
        'reactions_count', v_post.reactions_count,
        'comments_count', v_post.comments_count,
        'reposts_count', v_post.reposts_count,
        'saves_count', v_post.saves_count,
        'shares_count', v_post.shares_count,
        'engagement_rate', ROUND(
            CASE WHEN v_post.views_count > 0 THEN
                (
                    COALESCE((v_post.reactions_count->>'total')::numeric::int, 0) +
                    v_post.comments_count +
                    v_post.reposts_count +
                    v_post.saves_count
                )::numeric / v_post.views_count * 100
            ELSE 0 END, 2
        ),
        'daily_views', COALESCE(v_daily_views, '[]'::jsonb),
        'source_breakdown', COALESCE(v_source_breakdown, '{}'::jsonb),
        'device_breakdown', COALESCE(v_device_breakdown, '{}'::jsonb),
        'video_engagement', v_engagement
    );

    -- Add ad metrics if sponsored
    IF v_post.is_sponsored THEN
        v_result := v_result || jsonb_build_object(
            'ad_metrics', v_post.ad_metrics,
            'cta_clicks', v_post.clicks_count,
            'ctr', ROUND(
                CASE WHEN v_post.views_count > 0 THEN
                    v_post.clicks_count::numeric / v_post.views_count * 100
                ELSE 0 END, 2
            )
        );
    END IF;

    RETURN v_result;
END;
$$;

-- ============================================================
-- FUNCTION: Get story viewers (who viewed my story)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_story_viewers(
    p_post_id UUID,
    p_user_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    viewer_user_id UUID,
    viewer_username TEXT,
    viewer_display_name TEXT,
    viewer_profile_url TEXT,
    viewed_at TIMESTAMPTZ
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- Verify story belongs to user
    IF NOT EXISTS (
        SELECT 1 FROM public.posts
        WHERE id = p_post_id
        AND user_id = p_user_id
        AND post_type = 'story'
    ) THEN
        RAISE EXCEPTION 'Story not found or unauthorized';
    END IF;

    RETURN QUERY
    SELECT
        pv.user_id as viewer_user_id,
        up.username as viewer_username,
        up.display_name as viewer_display_name,
        up.profile_url as viewer_profile_url,
        pv.created_at as viewed_at
    FROM public.post_views pv
    JOIN public.user_profiles up ON up.user_id = pv.user_id
    WHERE pv.post_id = p_post_id
    AND pv.user_id IS NOT NULL
    AND pv.user_id != p_user_id
    ORDER BY pv.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ============================================================
-- FUNCTION: Update video view progress
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_view_progress(
    p_post_id UUID,
    p_user_id UUID,
    p_duration_seconds INTEGER,
    p_view_percent INTEGER,
    p_completed BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.post_views
    SET
        view_duration_seconds = GREATEST(
            COALESCE(view_duration_seconds, 0),
            p_duration_seconds
        ),
        view_percent = GREATEST(
            COALESCE(view_percent, 0),
            p_view_percent
        ),
        completed = COALESCE(completed, false) OR p_completed
    WHERE post_id = p_post_id
    AND user_id = p_user_id
    AND view_date = CURRENT_DATE;

    IF NOT FOUND THEN
        -- Create view record if doesn't exist
        PERFORM public.record_view(
            p_post_id, p_user_id, 'feed',
            p_duration_seconds, p_view_percent, p_completed
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'post_id', p_post_id,
        'duration', p_duration_seconds,
        'percent', p_view_percent,
        'completed', p_completed
    );
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT ALL ON TABLE public.post_views TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_view(UUID, UUID, TEXT, INTEGER, INTEGER, BOOLEAN, TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.record_ad_click(UUID, UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_post_analytics(UUID, UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_story_viewers(UUID, UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_view_progress(UUID, UUID, INTEGER, INTEGER, BOOLEAN) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.post_views table ready';
    RAISE NOTICE '   - 1 trigger:';
    RAISE NOTICE '     • trg_update_post_view_count';
    RAISE NOTICE '   - 5 functions:';
    RAISE NOTICE '     • record_view()';
    RAISE NOTICE '     • record_ad_click()';
    RAISE NOTICE '     • get_post_analytics()';
    RAISE NOTICE '     • get_story_viewers()';
    RAISE NOTICE '     • update_view_progress()';
    RAISE NOTICE '   - 4 RLS policies';
    RAISE NOTICE '   - 7 indexes (incl. unique dedup)';
END $$;
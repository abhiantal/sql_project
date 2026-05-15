-- ============================================================
-- 📁 FILE 04: FOLLOWS TABLE
-- Social graph with relationship types + feed preferences
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.follows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,

    -- ════════════════════════════════════════════════════════
    -- STATUS
    -- ════════════════════════════════════════════════════════
    status TEXT DEFAULT 'active' CHECK (status IN (
        'active', 'pending', 'blocked'
    )),

    -- ════════════════════════════════════════════════════════
    -- RELATIONSHIP TYPE
    -- ════════════════════════════════════════════════════════
    relationship TEXT DEFAULT 'follow' CHECK (relationship IN (
        'follow', 'close_friend', 'favorite', 'muted', 'restricted'
    )),

    -- ════════════════════════════════════════════════════════
    -- NOTIFICATION PREFERENCES
    -- ════════════════════════════════════════════════════════
    notifications JSONB DEFAULT '{
        "posts": true,
        "stories": true,
        "reels": true,
        "live": true,
        "all": true
    }'::jsonb,

    -- ════════════════════════════════════════════════════════
    -- FEED PREFERENCES
    -- ════════════════════════════════════════════════════════
    show_in_feed BOOLEAN DEFAULT TRUE,
    feed_priority INTEGER DEFAULT 0,

    -- ════════════════════════════════════════════════════════
    -- TIMESTAMPS
    -- ════════════════════════════════════════════════════════
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- ════════════════════════════════════════════════════════
    -- CONSTRAINTS
    -- ════════════════════════════════════════════════════════
    UNIQUE(follower_id, following_id),
    CHECK(follower_id != following_id)
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_follows_follower ON public.follows(follower_id, status);
CREATE INDEX IF NOT EXISTS idx_follows_following ON public.follows(following_id, status);
CREATE INDEX IF NOT EXISTS idx_follows_active ON public.follows(follower_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_follows_pending ON public.follows(following_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_follows_mutual ON public.follows(follower_id, following_id, status);
CREATE INDEX IF NOT EXISTS idx_follows_feed_priority ON public.follows(follower_id, feed_priority DESC) WHERE show_in_feed = true;
CREATE INDEX IF NOT EXISTS idx_follows_relationship ON public.follows(follower_id, relationship);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'follows' AND policyname = 'follows_select_own') THEN
        CREATE POLICY "follows_select_own" ON public.follows
            FOR SELECT USING (auth.uid() = follower_id OR auth.uid() = following_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'follows' AND policyname = 'follows_select_public_active') THEN
        CREATE POLICY "follows_select_public_active" ON public.follows
            FOR SELECT USING (status = 'active');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'follows' AND policyname = 'follows_insert_own') THEN
        CREATE POLICY "follows_insert_own" ON public.follows
            FOR INSERT WITH CHECK (auth.uid() = follower_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'follows' AND policyname = 'follows_update_own') THEN
        CREATE POLICY "follows_update_own" ON public.follows
            FOR UPDATE USING (auth.uid() = follower_id OR auth.uid() = following_id)
            WITH CHECK (auth.uid() = follower_id OR auth.uid() = following_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'follows' AND policyname = 'follows_delete_own') THEN
        CREATE POLICY "follows_delete_own" ON public.follows
            FOR DELETE USING (auth.uid() = follower_id);
    END IF;
END $$;

-- ============================================================
-- TRIGGER FUNCTION: Update user follow counts in user_profiles
-- ============================================================
DROP FUNCTION IF EXISTS internal.fn_update_user_follow_counts() CASCADE;
CREATE OR REPLACE FUNCTION internal.fn_update_user_follow_counts()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_follower_id UUID;
    v_following_id UUID;
    v_followers_count INTEGER;
    v_following_count INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_follower_id := NEW.follower_id;
        v_following_id := NEW.following_id;
    ELSIF TG_OP = 'DELETE' THEN
        v_follower_id := OLD.follower_id;
        v_following_id := OLD.following_id;
    ELSIF TG_OP = 'UPDATE' THEN
        v_follower_id := NEW.follower_id;
        v_following_id := NEW.following_id;
    END IF;

    -- Update follower's following_count
    SELECT COUNT(*) INTO v_following_count
    FROM public.follows
    WHERE follower_id = v_follower_id AND status = 'active';
 
    UPDATE public.user_profiles
    SET social_stats = COALESCE(social_stats, '{"followers_count":0,"following_count":0,"posts_count":0}'::jsonb) ||
        jsonb_build_object('following_count', v_following_count),
        updated_at = NOW()
    WHERE user_id = v_follower_id;
 
    -- Update following's followers_count
    SELECT COUNT(*) INTO v_followers_count
    FROM public.follows
    WHERE following_id = v_following_id AND status = 'active';
 
    UPDATE public.user_profiles
    SET social_stats = COALESCE(social_stats, '{"followers_count":0,"following_count":0,"posts_count":0}'::jsonb) ||
        jsonb_build_object('followers_count', v_followers_count),
        updated_at = NOW()
    WHERE user_id = v_following_id;

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- ============================================================
-- CREATE TRIGGERS
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_follows_updated_at') THEN
        CREATE TRIGGER trg_update_follows_updated_at
            BEFORE UPDATE ON public.follows
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_user_follow_counts') THEN
        CREATE TRIGGER trg_update_user_follow_counts
            AFTER INSERT OR UPDATE OR DELETE ON public.follows
            FOR EACH ROW EXECUTE FUNCTION internal.fn_update_user_follow_counts();
    END IF;
END $$;

-- ============================================================
-- FUNCTION: Toggle follow (follow/unfollow)
-- ============================================================
DROP FUNCTION IF EXISTS public.toggle_follow(UUID, UUID);
CREATE OR REPLACE FUNCTION public.toggle_follow(
    p_follower_id UUID,
    p_following_id UUID
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing RECORD;
    v_action TEXT;
    v_status TEXT;
    v_is_private BOOLEAN;
BEGIN
    -- Can't follow yourself
    IF p_follower_id = p_following_id THEN
        RAISE EXCEPTION 'Cannot follow yourself';
    END IF;

    -- Check if already following
    SELECT * INTO v_existing
    FROM public.follows
    WHERE follower_id = p_follower_id AND following_id = p_following_id;

    IF FOUND THEN
        IF v_existing.status = 'blocked' THEN
            RAISE EXCEPTION 'You are blocked by this user';
        END IF;

        -- Unfollow
        DELETE FROM public.follows
        WHERE id = v_existing.id;

        v_action := 'unfollowed';
        v_status := NULL;
    ELSE
        -- Check if target account is private
        SELECT COALESCE((up.user_info->>'is_private')::boolean, false)
        INTO v_is_private
        FROM public.user_profiles up
        WHERE up.user_id = p_following_id;

        IF v_is_private THEN
            v_status := 'pending';
            v_action := 'requested';
        ELSE
            v_status := 'active';
            v_action := 'followed';
        END IF;

        INSERT INTO public.follows (follower_id, following_id, status)
        VALUES (p_follower_id, p_following_id, v_status);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'action', v_action,
        'status', v_status,
        'follower_id', p_follower_id,
        'following_id', p_following_id
    );
END;
$$;

-- ============================================================
-- FUNCTION: Respond to follow request
-- ============================================================
DROP FUNCTION IF EXISTS public.respond_follow_request(UUID, UUID, BOOLEAN);
CREATE OR REPLACE FUNCTION public.respond_follow_request(
    p_user_id UUID,
    p_follower_id UUID,
    p_accept BOOLEAN
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing RECORD;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT * INTO v_existing
    FROM public.follows
    WHERE follower_id = p_follower_id
    AND following_id = p_user_id
    AND status = 'pending';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No pending follow request found';
    END IF;

    IF p_accept THEN
        UPDATE public.follows
        SET status = 'active', updated_at = NOW()
        WHERE id = v_existing.id;

        RETURN jsonb_build_object('success', true, 'action', 'accepted');
    ELSE
        DELETE FROM public.follows WHERE id = v_existing.id;

        RETURN jsonb_build_object('success', true, 'action', 'rejected');
    END IF;
END;
$$;

-- ============================================================
-- FUNCTION: Update relationship type
-- ============================================================
DROP FUNCTION IF EXISTS public.update_follow_relationship(UUID, UUID, TEXT, BOOLEAN, JSONB);
CREATE OR REPLACE FUNCTION public.update_follow_relationship(
    p_follower_id UUID,
    p_following_id UUID,
    p_relationship TEXT,
    p_show_in_feed BOOLEAN DEFAULT NULL,
    p_notifications JSONB DEFAULT NULL
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_feed_priority INTEGER;
BEGIN
    -- Calculate feed priority based on relationship
    v_feed_priority := CASE p_relationship
        WHEN 'favorite' THEN 10
        WHEN 'close_friend' THEN 5
        WHEN 'follow' THEN 0
        WHEN 'muted' THEN -10
        WHEN 'restricted' THEN -5
        ELSE 0
    END;

    UPDATE public.follows
    SET
        relationship = p_relationship,
        show_in_feed = COALESCE(p_show_in_feed,
            CASE WHEN p_relationship = 'muted' THEN false ELSE true END
        ),
        feed_priority = v_feed_priority,
        notifications = COALESCE(p_notifications, notifications),
        updated_at = NOW()
    WHERE follower_id = p_follower_id
    AND following_id = p_following_id
    AND status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Follow relationship not found';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'relationship', p_relationship,
        'show_in_feed', COALESCE(p_show_in_feed, p_relationship != 'muted'),
        'feed_priority', v_feed_priority
    );
END;
$$;

-- ============================================================
-- FUNCTION: Block user
-- ============================================================
DROP FUNCTION IF EXISTS public.block_user(UUID, UUID);
CREATE OR REPLACE FUNCTION public.block_user(
    p_user_id UUID,
    p_blocked_user_id UUID
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_user_id = p_blocked_user_id THEN
        RAISE EXCEPTION 'Cannot block yourself';
    END IF;

    -- Remove any existing follow from blocked user → me
    DELETE FROM public.follows
    WHERE follower_id = p_blocked_user_id AND following_id = p_user_id;

    -- Update or insert blocked follow from me → blocked user
    INSERT INTO public.follows (follower_id, following_id, status, show_in_feed)
    VALUES (p_user_id, p_blocked_user_id, 'blocked', false)
    ON CONFLICT (follower_id, following_id)
    DO UPDATE SET status = 'blocked', show_in_feed = false, updated_at = NOW();

    RETURN jsonb_build_object(
        'success', true,
        'action', 'blocked',
        'blocked_user_id', p_blocked_user_id
    );
END;
$$;

-- ============================================================
-- FUNCTION: Unblock user
-- ============================================================
DROP FUNCTION IF EXISTS public.unblock_user(UUID, UUID);
CREATE OR REPLACE FUNCTION public.unblock_user(
    p_user_id UUID,
    p_blocked_user_id UUID
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM public.follows
    WHERE follower_id = p_user_id
    AND following_id = p_blocked_user_id
    AND status = 'blocked';

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'User was not blocked');
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'action', 'unblocked',
        'unblocked_user_id', p_blocked_user_id
    );
END;
$$;

-- ============================================================
-- FUNCTION: Get followers list
-- ============================================================
DROP FUNCTION IF EXISTS public.get_followers(UUID, UUID, INTEGER, INTEGER, TEXT);
CREATE OR REPLACE FUNCTION public.get_followers(
    p_user_id UUID,
    p_requesting_user_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0,
    p_search TEXT DEFAULT NULL
)
RETURNS TABLE (
    follow_id UUID,
    user_id UUID,
    username TEXT,
    display_name TEXT,
    profile_url TEXT,
    user_info JSONB,
    followed_at TIMESTAMPTZ,
    is_following_back BOOLEAN,
    is_mutual BOOLEAN
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.id as follow_id,
        f.follower_id as user_id,
        up.username,
        up.display_name,
        up.profile_url,
        up.user_info,
        f.created_at as followed_at,
        -- Am I (requesting user) following this follower?
        EXISTS(
            SELECT 1 FROM public.follows f2
            WHERE f2.follower_id = p_requesting_user_id
            AND f2.following_id = f.follower_id
            AND f2.status = 'active'
        ) as is_following_back,
        -- Is it mutual (they follow each other)?
        EXISTS(
            SELECT 1 FROM public.follows f3
            WHERE f3.follower_id = p_user_id
            AND f3.following_id = f.follower_id
            AND f3.status = 'active'
        ) as is_mutual
    FROM public.follows f
    JOIN public.user_profiles up ON up.user_id = f.follower_id
    WHERE f.following_id = p_user_id
    AND f.status = 'active'
    AND (p_search IS NULL OR up.username ILIKE '%' || p_search || '%' OR up.display_name ILIKE '%' || p_search || '%')
    ORDER BY f.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ============================================================
-- FUNCTION: Get following list
-- ============================================================
DROP FUNCTION IF EXISTS public.get_following(UUID, UUID, TEXT, INTEGER, INTEGER, TEXT);
CREATE OR REPLACE FUNCTION public.get_following(
    p_user_id UUID,
    p_requesting_user_id UUID,
    p_relationship TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0,
    p_search TEXT DEFAULT NULL
)
RETURNS TABLE (
    follow_id UUID,
    user_id UUID,
    username TEXT,
    display_name TEXT,
    profile_url TEXT,
    user_info JSONB,
    relationship TEXT,
    show_in_feed BOOLEAN,
    followed_at TIMESTAMPTZ,
    is_mutual BOOLEAN
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.id as follow_id,
        f.following_id as user_id,
        up.username,
        up.display_name,
        up.profile_url,
        up.user_info,
        f.relationship,
        f.show_in_feed,
        f.created_at as followed_at,
        EXISTS(
            SELECT 1 FROM public.follows f2
            WHERE f2.follower_id = f.following_id
            AND f2.following_id = p_user_id
            AND f2.status = 'active'
        ) as is_mutual
    FROM public.follows f
    JOIN public.user_profiles up ON up.user_id = f.following_id
    WHERE f.follower_id = p_user_id
    AND f.status = 'active'
    AND (p_relationship IS NULL OR f.relationship = p_relationship)
    AND (p_search IS NULL OR up.username ILIKE '%' || p_search || '%' OR up.display_name ILIKE '%' || p_search || '%')
    ORDER BY f.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ============================================================
-- FUNCTION: Check follow status between two users
-- ============================================================
DROP FUNCTION IF EXISTS public.check_follow_status(UUID, UUID);
CREATE OR REPLACE FUNCTION public.check_follow_status(
    p_user1_id UUID,
    p_user2_id UUID
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_i_follow RECORD;
    v_they_follow RECORD;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Do I follow them?
    SELECT status, relationship INTO v_i_follow
    FROM public.follows
    WHERE follower_id = p_user_id AND following_id = p_target_user_id;

    -- Do they follow me?
    SELECT status, relationship INTO v_they_follow
    FROM public.follows
    WHERE follower_id = p_target_user_id AND following_id = p_user_id;

    RETURN jsonb_build_object(
        'i_follow', v_i_follow.status IS NOT NULL AND v_i_follow.status = 'active',
        'i_follow_status', v_i_follow.status,
        'i_follow_relationship', v_i_follow.relationship,
        'they_follow', v_they_follow.status IS NOT NULL AND v_they_follow.status = 'active',
        'they_follow_status', v_they_follow.status,
        'is_mutual', (
            v_i_follow.status = 'active' AND v_they_follow.status = 'active'
        ),
        'is_blocked', (
            v_i_follow.status = 'blocked' OR v_they_follow.status = 'blocked'
        ),
        'is_pending', v_i_follow.status = 'pending'
    );
END;
$$;

-- ============================================================
-- FUNCTION: Get follow suggestions
-- ============================================================
DROP FUNCTION IF EXISTS public.get_follow_suggestions(UUID, INTEGER);
CREATE OR REPLACE FUNCTION public.get_follow_suggestions(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    user_id UUID,
    username TEXT,
    display_name TEXT,
    profile_url TEXT,
    user_info JSONB,
    mutual_followers_count INTEGER,
    reason TEXT
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH my_following AS (
        SELECT following_id
        FROM public.follows
        WHERE follower_id = p_user_id AND status = 'active'
    ),
    -- Friends of friends (mutual connections)
    friends_of_friends AS (
        SELECT
            f2.following_id as suggested_user_id,
            COUNT(DISTINCT f2.follower_id) as mutual_count
        FROM public.follows f2
        WHERE f2.follower_id IN (SELECT following_id FROM my_following)
        AND f2.following_id != p_user_id
        AND f2.following_id NOT IN (SELECT following_id FROM my_following)
        AND f2.status = 'active'
        GROUP BY f2.following_id
        ORDER BY mutual_count DESC
        LIMIT p_limit
    )
    SELECT
        fof.suggested_user_id as user_id,
        up.username,
        up.display_name,
        up.profile_url,
        up.user_info,
        fof.mutual_count::numeric::integer as mutual_followers_count,
        'mutual_connections' as reason
    FROM friends_of_friends fof
    JOIN public.user_profiles up ON up.user_id = fof.suggested_user_id
    ORDER BY fof.mutual_count DESC
    LIMIT p_limit;
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT ALL ON TABLE public.follows TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_follow(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_follow_request(UUID, UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_follow_relationship(UUID, UUID, TEXT, BOOLEAN, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_user(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unblock_user(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_followers(UUID, UUID, INTEGER, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_following(UUID, UUID, TEXT, INTEGER, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_follow_status(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_follow_suggestions(UUID, INTEGER) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.follows table ready';
    RAISE NOTICE '   - 2 triggers:';
    RAISE NOTICE '     • trg_update_follows_updated_at';
    RAISE NOTICE '     • trg_update_user_follow_counts';
    RAISE NOTICE '   - 9 functions:';
    RAISE NOTICE '     • toggle_follow()';
    RAISE NOTICE '     • respond_follow_request()';
    RAISE NOTICE '     • update_follow_relationship()';
    RAISE NOTICE '     • block_user()';
    RAISE NOTICE '     • unblock_user()';
    RAISE NOTICE '     • get_followers()';
    RAISE NOTICE '     • get_following()';
    RAISE NOTICE '     • check_follow_status()';
    RAISE NOTICE '     • get_follow_suggestions()';
    RAISE NOTICE '   - 5 RLS policies';
    RAISE NOTICE '   - 7 indexes';
END $$;
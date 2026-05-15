-- ============================================================
-- 📁 FILE 18: MENTORSHIP CONNECTIONS TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.mentorship_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    mentor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    request_type TEXT NOT NULL DEFAULT 'request_access',
    request_status TEXT NOT NULL DEFAULT 'pending',
    request_message TEXT,
    response_message TEXT,
    requested_at TIMESTAMPTZ DEFAULT NOW(),
    responded_at TIMESTAMPTZ,

    relationship_type TEXT NOT NULL DEFAULT 'custom',
    relationship_label TEXT,

    allowed_screens JSONB NOT NULL DEFAULT '["all"]'::jsonb,

    permissions JSONB NOT NULL DEFAULT '{
        "show_points": true,
        "show_streak": true,
        "show_rank": true,
        "show_tasks": false,
        "show_task_details": false,
        "show_goals": false,
        "show_goal_details": false,
        "show_mood": false,
        "show_diary": false,
        "show_rewards": true,
        "show_progress": true
    }'::jsonb,

    duration TEXT NOT NULL DEFAULT '7_days',
    starts_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,

    access_status TEXT NOT NULL DEFAULT 'inactive',
    is_live_enabled BOOLEAN DEFAULT TRUE,

    view_count INT DEFAULT 0,
    last_viewed_at TIMESTAMPTZ,
    last_viewed_screen TEXT,

    cached_snapshot JSONB DEFAULT '{}'::jsonb,
    snapshot_captured_at TIMESTAMPTZ,

    notify_owner_on_view BOOLEAN DEFAULT FALSE,
    notify_mentor_on_update BOOLEAN DEFAULT TRUE,
    notify_mentor_on_inactive BOOLEAN DEFAULT TRUE,
    inactive_threshold_days INT DEFAULT 3,

    last_encouragement_at TIMESTAMPTZ,
    last_encouragement_type TEXT,
    last_encouragement_message TEXT,
    encouragement_count INT DEFAULT 0,

    last_notified JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT mentorship_unique_pair UNIQUE (owner_id, mentor_id),
    CONSTRAINT mentorship_no_self CHECK (owner_id != mentor_id),
    CONSTRAINT mentorship_valid_request_type CHECK (
        request_type IN ('request_access', 'offer_share')
    ),
    CONSTRAINT mentorship_valid_request_status CHECK (
        request_status IN ('pending', 'approved', 'rejected', 'cancelled', 'expired')
    ),
    CONSTRAINT mentorship_valid_access_status CHECK (
        access_status IN ('inactive', 'active', 'paused', 'expired', 'revoked')
    ),
    CONSTRAINT mentorship_valid_relationship CHECK (
        relationship_type IN (
            'teacher_student', 'parent_child', 'boss_employee',
            'coach_athlete', 'accountability_partner', 'custom'
        )
    ),
    CONSTRAINT mentorship_valid_duration CHECK (
        duration IN ('one_time', '1_day', '7_days', '30_days', '6_months', 'always')
    )
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_mentorship_owner_id ON public.mentorship_connections(owner_id);
CREATE INDEX IF NOT EXISTS idx_mentorship_mentor_id ON public.mentorship_connections(mentor_id);
CREATE INDEX IF NOT EXISTS idx_mentorship_my_mentors ON public.mentorship_connections(owner_id, access_status) WHERE access_status IN ('active', 'paused');
CREATE INDEX IF NOT EXISTS idx_mentorship_my_mentees ON public.mentorship_connections(mentor_id, access_status) WHERE access_status IN ('active', 'paused');
CREATE INDEX IF NOT EXISTS idx_mentorship_pending_to_owner ON public.mentorship_connections(owner_id, request_status) WHERE request_status = 'pending';
CREATE INDEX IF NOT EXISTS idx_mentorship_pending_from_mentor ON public.mentorship_connections(mentor_id, request_status) WHERE request_status = 'pending';
CREATE INDEX IF NOT EXISTS idx_mentorship_active_access ON public.mentorship_connections(owner_id, mentor_id, access_status) WHERE access_status = 'active';
CREATE INDEX IF NOT EXISTS idx_mentorship_expires_at ON public.mentorship_connections(expires_at) WHERE expires_at IS NOT NULL AND access_status = 'active';
CREATE INDEX IF NOT EXISTS idx_mentorship_relationship ON public.mentorship_connections(relationship_type);
CREATE INDEX IF NOT EXISTS idx_mentorship_updated_at ON public.mentorship_connections(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_mentorship_last_viewed ON public.mentorship_connections(last_viewed_at DESC) WHERE last_viewed_at IS NOT NULL;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.mentorship_connections ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'mentorship_connections' AND policyname = 'mentorship_owner_select') THEN
        CREATE POLICY "mentorship_owner_select" ON public.mentorship_connections
            FOR SELECT USING (auth.uid() = owner_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'mentorship_connections' AND policyname = 'mentorship_mentor_select') THEN
        CREATE POLICY "mentorship_mentor_select" ON public.mentorship_connections
            FOR SELECT USING (auth.uid() = mentor_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'mentorship_connections' AND policyname = 'mentorship_owner_insert') THEN
        CREATE POLICY "mentorship_owner_insert" ON public.mentorship_connections
            FOR INSERT WITH CHECK (auth.uid() = owner_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'mentorship_connections' AND policyname = 'mentorship_mentor_insert') THEN
        CREATE POLICY "mentorship_mentor_insert" ON public.mentorship_connections
            FOR INSERT WITH CHECK (auth.uid() = mentor_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'mentorship_connections' AND policyname = 'mentorship_owner_update') THEN
        CREATE POLICY "mentorship_owner_update" ON public.mentorship_connections
            FOR UPDATE USING (auth.uid() = owner_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'mentorship_connections' AND policyname = 'mentorship_mentor_update') THEN
        CREATE POLICY "mentorship_mentor_update" ON public.mentorship_connections
            FOR UPDATE USING (auth.uid() = mentor_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'mentorship_connections' AND policyname = 'mentorship_owner_delete') THEN
        CREATE POLICY "mentorship_owner_delete" ON public.mentorship_connections
            FOR DELETE USING (auth.uid() = owner_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'mentorship_connections' AND policyname = 'mentorship_mentor_delete') THEN
        CREATE POLICY "mentorship_mentor_delete" ON public.mentorship_connections
            FOR DELETE USING (
                auth.uid() = mentor_id AND
                request_status = 'pending' AND
                request_type = 'request_access'
            );
    END IF;
END $$;

-- ============================================================
-- REALTIME
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND tablename = 'mentorship_connections'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.mentorship_connections;
    END IF;
EXCEPTION
    WHEN undefined_object THEN
        NULL;
END $$;

-- ============================================================
-- FUNCTION: Update mentorship updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION internal.update_mentorship_updated_at()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- ============================================================
-- FUNCTION 1: Approve mentorship
-- ============================================================
CREATE OR REPLACE FUNCTION public.approve_mentorship(
    p_connection_id UUID,
    p_custom_permissions JSONB DEFAULT NULL,
    p_custom_screens JSONB DEFAULT NULL,
    p_response_message TEXT DEFAULT NULL
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_connection RECORD;
    v_expires_at TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_connection
    FROM public.mentorship_connections WHERE id = p_connection_id;

    IF v_connection IS NULL THEN
        RAISE EXCEPTION 'Connection not found';
    END IF;

    IF v_connection.owner_id != auth.uid() THEN
        RAISE EXCEPTION 'Only the owner can approve requests';
    END IF;

    IF v_connection.request_status != 'pending' THEN
        RAISE EXCEPTION 'Can only approve pending requests';
    END IF;

    v_expires_at := CASE v_connection.duration
        WHEN 'one_time' THEN NOW() + INTERVAL '1 hour'
        WHEN '1_day' THEN NOW() + INTERVAL '1 day'
        WHEN '7_days' THEN NOW() + INTERVAL '7 days'
        WHEN '30_days' THEN NOW() + INTERVAL '30 days'
        WHEN '6_months' THEN NOW() + INTERVAL '6 months'
        WHEN 'always' THEN NULL
        ELSE NOW() + INTERVAL '7 days'
    END;

    UPDATE public.mentorship_connections SET
        request_status = 'approved',
        access_status = 'active',
        responded_at = NOW(),
        response_message = p_response_message,
        permissions = COALESCE(p_custom_permissions, permissions),
        allowed_screens = COALESCE(p_custom_screens, allowed_screens),
        starts_at = NOW(),
        expires_at = v_expires_at,
        updated_at = NOW()
    WHERE id = p_connection_id;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION 2: Reject mentorship
-- ============================================================
CREATE OR REPLACE FUNCTION public.reject_mentorship(
    p_connection_id UUID,
    p_response_message TEXT DEFAULT NULL
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_connection RECORD;
BEGIN
    SELECT * INTO v_connection
    FROM public.mentorship_connections WHERE id = p_connection_id;

    IF v_connection IS NULL THEN
        RAISE EXCEPTION 'Connection not found';
    END IF;

    IF v_connection.owner_id != auth.uid() THEN
        RAISE EXCEPTION 'Only the owner can reject requests';
    END IF;

    IF v_connection.request_status != 'pending' THEN
        RAISE EXCEPTION 'Can only reject pending requests';
    END IF;

    UPDATE public.mentorship_connections SET
        request_status = 'rejected',
        access_status = 'inactive',
        responded_at = NOW(),
        response_message = p_response_message,
        updated_at = NOW()
    WHERE id = p_connection_id;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION 3: Revoke mentorship
-- ============================================================
CREATE OR REPLACE FUNCTION public.revoke_mentorship(p_connection_id UUID)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_connection RECORD;
BEGIN
    SELECT * INTO v_connection
    FROM public.mentorship_connections WHERE id = p_connection_id;

    IF v_connection IS NULL THEN
        RAISE EXCEPTION 'Connection not found';
    END IF;

    IF v_connection.owner_id != auth.uid() THEN
        RAISE EXCEPTION 'Only the owner can revoke access';
    END IF;

    UPDATE public.mentorship_connections SET
        access_status = 'revoked',
        updated_at = NOW()
    WHERE id = p_connection_id;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION 4: Toggle mentorship pause
-- ============================================================
CREATE OR REPLACE FUNCTION public.toggle_mentorship_pause(p_connection_id UUID)
RETURNS TEXT
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_connection RECORD;
    v_new_status TEXT;
BEGIN
    SELECT * INTO v_connection
    FROM public.mentorship_connections WHERE id = p_connection_id;

    IF v_connection IS NULL THEN
        RAISE EXCEPTION 'Connection not found';
    END IF;

    IF v_connection.owner_id != auth.uid() THEN
        RAISE EXCEPTION 'Only the owner can pause/resume';
    END IF;

    v_new_status := CASE v_connection.access_status
        WHEN 'active' THEN 'paused'
        WHEN 'paused' THEN 'active'
        ELSE v_connection.access_status
    END;

    UPDATE public.mentorship_connections SET
        access_status = v_new_status,
        updated_at = NOW()
    WHERE id = p_connection_id;

    RETURN v_new_status;
END;
$$;

-- ============================================================
-- FUNCTION 5: Log mentorship view
-- ============================================================
CREATE OR REPLACE FUNCTION public.log_mentorship_view(
    p_connection_id UUID,
    p_screen TEXT DEFAULT NULL
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_connection RECORD;
BEGIN
    SELECT * INTO v_connection
    FROM public.mentorship_connections WHERE id = p_connection_id;

    IF v_connection IS NULL THEN
        RETURN FALSE;
    END IF;

    IF v_connection.mentor_id != auth.uid() THEN
        RETURN FALSE;
    END IF;

    IF v_connection.access_status != 'active' THEN
        RETURN FALSE;
    END IF;

    -- Check expiration
    IF v_connection.expires_at IS NOT NULL AND v_connection.expires_at < NOW() THEN
        UPDATE public.mentorship_connections SET
            access_status = 'expired',
            updated_at = NOW()
        WHERE id = p_connection_id;
        RETURN FALSE;
    END IF;

    UPDATE public.mentorship_connections SET
        view_count = view_count + 1,
        last_viewed_at = NOW(),
        last_viewed_screen = COALESCE(p_screen, last_viewed_screen),
        updated_at = NOW()
    WHERE id = p_connection_id;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION 6: Update mentorship snapshot
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_mentorship_snapshot(
    p_connection_id UUID,
    p_snapshot JSONB
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_connection RECORD;
BEGIN
    SELECT * INTO v_connection
    FROM public.mentorship_connections WHERE id = p_connection_id;

    IF v_connection IS NULL THEN
        RETURN FALSE;
    END IF;

    IF v_connection.owner_id != auth.uid() AND v_connection.mentor_id != auth.uid() THEN
        RETURN FALSE;
    END IF;

    UPDATE public.mentorship_connections SET
        cached_snapshot = p_snapshot,
        snapshot_captured_at = NOW(),
        updated_at = NOW()
    WHERE id = p_connection_id;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION 7: Extend mentorship
-- ============================================================
CREATE OR REPLACE FUNCTION public.extend_mentorship(
    p_connection_id UUID,
    p_new_duration TEXT
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_connection RECORD;
    v_new_expires_at TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_connection
    FROM public.mentorship_connections WHERE id = p_connection_id;

    IF v_connection IS NULL THEN
        RAISE EXCEPTION 'Connection not found';
    END IF;

    IF v_connection.owner_id != auth.uid() THEN
        RAISE EXCEPTION 'Only the owner can extend duration';
    END IF;

    v_new_expires_at := CASE p_new_duration
        WHEN 'one_time' THEN NOW() + INTERVAL '1 hour'
        WHEN '1_day' THEN NOW() + INTERVAL '1 day'
        WHEN '7_days' THEN NOW() + INTERVAL '7 days'
        WHEN '30_days' THEN NOW() + INTERVAL '30 days'
        WHEN '6_months' THEN NOW() + INTERVAL '6 months'
        WHEN 'always' THEN NULL
        ELSE NOW() + INTERVAL '7 days'
    END;

    UPDATE public.mentorship_connections SET
        duration = p_new_duration,
        expires_at = v_new_expires_at,
        access_status = 'active',
        updated_at = NOW()
    WHERE id = p_connection_id;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION 8: Send mentorship encouragement
-- ============================================================
CREATE OR REPLACE FUNCTION public.send_mentorship_encouragement(
    p_connection_id UUID,
    p_encouragement_type TEXT DEFAULT 'emoji'
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_connection RECORD;
BEGIN
    SELECT * INTO v_connection
    FROM public.mentorship_connections WHERE id = p_connection_id;

    IF v_connection IS NULL THEN
        RETURN FALSE;
    END IF;

    IF v_connection.mentor_id != auth.uid() THEN
        RETURN FALSE;
    END IF;

    UPDATE public.mentorship_connections SET
        last_encouragement_at = NOW(),
        last_encouragement_type = p_encouragement_type,
        encouragement_count = encouragement_count + 1,
        updated_at = NOW()
    WHERE id = p_connection_id;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION 9: Check mentorship expirations
-- ============================================================
CREATE OR REPLACE FUNCTION internal.check_mentorship_expirations()
RETURNS VOID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- Expire active connections past their expiration date
    UPDATE public.mentorship_connections SET
        access_status = 'expired',
        updated_at = NOW()
    WHERE access_status = 'active'
    AND expires_at IS NOT NULL
    AND expires_at < NOW();

    -- Expire old pending requests (30 days)
    UPDATE public.mentorship_connections SET
        request_status = 'expired',
        updated_at = NOW()
    WHERE request_status = 'pending'
    AND requested_at < NOW() - INTERVAL '30 days';
END;
$$;

-- ============================================================
-- FUNCTION 10: Get mentorship stats
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_mentorship_stats(p_user_id UUID)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSONB;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT jsonb_build_object(
        'total_mentors', COUNT(*) FILTER (WHERE owner_id = p_user_id AND request_status = 'approved'),
        'active_mentors', COUNT(*) FILTER (WHERE owner_id = p_user_id AND access_status = 'active'),
        'pending_requests_to_me', COUNT(*) FILTER (
            WHERE owner_id = p_user_id AND request_status = 'pending' AND request_type = 'request_access'),
        'pending_offers_to_me', COUNT(*) FILTER (
            WHERE mentor_id = p_user_id AND request_status = 'pending' AND request_type = 'offer_share'),
        'total_mentees', COUNT(*) FILTER (WHERE mentor_id = p_user_id AND request_status = 'approved'),
        'active_mentees', COUNT(*) FILTER (WHERE mentor_id = p_user_id AND access_status = 'active'),
        'pending_requests_from_me', COUNT(*) FILTER (
            WHERE mentor_id = p_user_id AND request_status = 'pending' AND request_type = 'request_access'),
        'pending_offers_from_me', COUNT(*) FILTER (
            WHERE owner_id = p_user_id AND request_status = 'pending' AND request_type = 'offer_share')
    )
    INTO v_result
    FROM public.mentorship_connections
    WHERE owner_id = p_user_id OR mentor_id = p_user_id;

    RETURN COALESCE(v_result, '{}'::jsonb);
END;
$$;

-- ============================================================
-- FUNCTION 11: Check if mentor can view screen
-- ============================================================
CREATE OR REPLACE FUNCTION internal.can_mentor_view_screen(
    p_mentor_id UUID,
    p_owner_id UUID,
    p_screen TEXT
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_connection RECORD;
    v_allowed_screens JSONB;
BEGIN
    SELECT * INTO v_connection
    FROM public.mentorship_connections
    WHERE mentor_id = p_mentor_id
    AND owner_id = p_owner_id
    AND access_status = 'active';

    IF v_connection IS NULL THEN
        RETURN FALSE;
    END IF;

    IF v_connection.expires_at IS NOT NULL AND v_connection.expires_at < NOW() THEN
        RETURN FALSE;
    END IF;

    v_allowed_screens := v_connection.allowed_screens;

    IF v_allowed_screens @> '["all"]'::jsonb THEN
        RETURN TRUE;
    END IF;

    RETURN v_allowed_screens @> to_jsonb(p_screen);
END;
$$;

-- ============================================================
-- TRIGGER: Updated at
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trigger_mentorship_updated_at') THEN
        CREATE TRIGGER trigger_mentorship_updated_at
            BEFORE UPDATE ON public.mentorship_connections
            FOR EACH ROW EXECUTE FUNCTION internal.update_mentorship_updated_at();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON public.mentorship_connections TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_mentorship(UUID, JSONB, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_mentorship(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_mentorship(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_mentorship_pause(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_mentorship_view(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_mentorship_snapshot(UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.extend_mentorship(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_mentorship_encouragement(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_mentorship_stats(UUID) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION internal.can_mentor_view_screen(UUID, UUID, TEXT) TO authenticated, service_role;


-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.mentorship_connections table ready';
    RAISE NOTICE '   - 1 trigger: trigger_mentorship_updated_at';
    RAISE NOTICE '   - 12 functions:';
    RAISE NOTICE '     • update_mentorship_updated_at()';
    RAISE NOTICE '     • approve_mentorship()';
    RAISE NOTICE '     • reject_mentorship()';
    RAISE NOTICE '     • revoke_mentorship()';
    RAISE NOTICE '     • toggle_mentorship_pause()';
    RAISE NOTICE '     • log_mentorship_view()';
    RAISE NOTICE '     • update_mentorship_snapshot()';
    RAISE NOTICE '     • extend_mentorship()';
    RAISE NOTICE '     • send_mentorship_encouragement()';
    RAISE NOTICE '     • check_mentorship_expirations()';
    RAISE NOTICE '     • get_mentorship_stats()';
    RAISE NOTICE '     • can_mentor_view_screen()';
    RAISE NOTICE '   - 8 RLS policies';
    RAISE NOTICE '   - 11 indexes';
END $$;
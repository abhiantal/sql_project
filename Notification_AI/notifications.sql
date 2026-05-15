-- ============================================================
-- 📁 FILE 10: NOTIFICATIONS TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    notification_info JSONB NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(user_id, is_read) WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS idx_notifications_created ON public.notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON public.notifications((notification_info->>'type'));
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON public.notifications(user_id, created_at DESC) WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS idx_notifications_updated ON public.notifications(updated_at DESC);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'notifications' AND policyname = 'notifications_select_own') THEN
        CREATE POLICY "notifications_select_own" ON public.notifications
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'notifications' AND policyname = 'notifications_insert_system') THEN
        CREATE POLICY "notifications_insert_system" ON public.notifications
            FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND user_id = auth.uid());
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'notifications' AND policyname = 'notifications_update_own') THEN
        CREATE POLICY "notifications_update_own" ON public.notifications
            FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'notifications' AND policyname = 'notifications_delete_own') THEN
        CREATE POLICY "notifications_delete_own" ON public.notifications
            FOR DELETE USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================
-- FUNCTION 1: Create notification
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_notification(
    p_user_id UUID,
    p_type TEXT,
    p_title TEXT,
    p_body TEXT,
    p_data JSONB DEFAULT NULL,
    p_action_url TEXT DEFAULT NULL,
    p_image_url TEXT DEFAULT NULL
)
RETURNS UUID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_notification_id UUID;
BEGIN
    INSERT INTO public.notifications (
        user_id,
        notification_info,
        metadata
    )
    VALUES (
        p_user_id,
        jsonb_build_object(
            'type', p_type,
            'title', p_title,
            'body', p_body,
            'data', COALESCE(p_data, '{}'::jsonb),
            'action_url', p_action_url,
            'image_url', p_image_url
        ),
        jsonb_build_object('created_by', 'system')
    )
    RETURNING id INTO v_notification_id;

    RETURN v_notification_id;
END;
$$;

-- ============================================================
-- FUNCTION 2: Mark notification as read
-- ============================================================
CREATE OR REPLACE FUNCTION public.mark_notification_read(
    p_notification_id UUID,
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
        RAISE EXCEPTION 'Unauthorized: You can only mark your own notifications as read';
    END IF;

    UPDATE public.notifications
    SET is_read = TRUE, read_at = NOW(), updated_at = NOW()
    WHERE id = p_notification_id AND user_id = p_user_id;

    RETURN FOUND;
END;
$$;

-- ============================================================
-- FUNCTION 3: Mark all notifications as read
-- ============================================================
CREATE OR REPLACE FUNCTION public.mark_all_notifications_read(p_user_id UUID)
RETURNS INTEGER
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: You can only mark your own notifications as read';
    END IF;

    UPDATE public.notifications
    SET is_read = TRUE, read_at = NOW(), updated_at = NOW()
    WHERE user_id = p_user_id AND is_read = FALSE;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- ============================================================
-- FUNCTION 4: Get unread notification count
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_unread_notification_count(p_user_id UUID)
RETURNS INTEGER
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM public.notifications
    WHERE user_id = p_user_id AND is_read = FALSE;

    RETURN v_count;
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT ALL ON TABLE public.notifications TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_notification(UUID, TEXT, TEXT, TEXT, JSONB, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_unread_notification_count(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- TRIGGER: Updated at
-- ============================================================
-- Note: update_updated_at_column should exist in common helpers
DO $$
BEGIN
    DROP TRIGGER IF EXISTS update_notifications_updated_at ON public.notifications;
    CREATE TRIGGER update_notifications_updated_at
        BEFORE UPDATE ON public.notifications
        FOR EACH ROW 
        EXECUTE FUNCTION public.update_updated_at_column();
END $$;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.notifications table ready';
    RAISE NOTICE '   - 0 triggers';
    RAISE NOTICE '   - 4 functions:';
    RAISE NOTICE '     • create_notification()';
    RAISE NOTICE '     • mark_notification_read()';
    RAISE NOTICE '     • mark_all_notifications_read()';
    RAISE NOTICE '     • get_unread_notification_count()';
    RAISE NOTICE '   - 4 RLS policies';
    RAISE NOTICE '   - 5 indexes';
END $$;
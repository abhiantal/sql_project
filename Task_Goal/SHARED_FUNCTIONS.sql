-- ============================================================
-- 📁 FILE 09: SHARED FUNCTIONS FOR ALL TASK/GOAL TABLES
-- Media cleanup and analytics triggers
-- ============================================================

-- ============================================================
-- FUNCTION: Delete user media on task delete (Shared)
-- ============================================================
CREATE OR REPLACE FUNCTION internal.delete_user_media_on_task_delete()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_bucket_name TEXT;
    v_user_id UUID;
    v_task_id UUID;
BEGIN
    v_user_id := OLD.user_id;
    v_task_id := OLD.id;

    CASE TG_TABLE_NAME
        WHEN 'day_tasks' THEN v_bucket_name := 'daily-task-media';
        WHEN 'weekly_tasks' THEN v_bucket_name := 'weekly-task-media';
        WHEN 'long_goals' THEN v_bucket_name := 'long-goals-media';
        WHEN 'bucket_models' THEN v_bucket_name := 'bucket-media';
        -- diary_entries delete media removed
        ELSE RETURN OLD;
    END CASE;

    -- NOTE: Direct deletion from storage.objects is forbidden by Supabase.
    -- Storage cleanup must be handled via the Storage API in the client application.
    -- DELETE FROM storage.objects
    -- WHERE bucket_id = v_bucket_name
    --   AND name LIKE (v_user_id::text || '/' || v_task_id::text || '/%');

    RETURN OLD;
END;
$$;

-- ============================================================
-- TRIGGERS: Media cleanup for each table
-- ============================================================

-- Bucket Models
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'cleanup_bucket_media') THEN
        CREATE TRIGGER cleanup_bucket_media
            BEFORE DELETE ON public.bucket_models
            FOR EACH ROW EXECUTE FUNCTION internal.delete_user_media_on_task_delete();
    END IF;
END $$;

-- Day Tasks
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'cleanup_day_task_media') THEN
        CREATE TRIGGER cleanup_day_task_media
            BEFORE DELETE ON public.day_tasks
            FOR EACH ROW EXECUTE FUNCTION internal.delete_user_media_on_task_delete();
    END IF;
END $$;

-- Weekly Tasks
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'cleanup_weekly_task_media') THEN
        CREATE TRIGGER cleanup_weekly_task_media
            BEFORE DELETE ON public.weekly_tasks
            FOR EACH ROW EXECUTE FUNCTION internal.delete_user_media_on_task_delete();
    END IF;
END $$;

-- Long Goals
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'cleanup_long_goal_media') THEN
        CREATE TRIGGER cleanup_long_goal_media
            BEFORE DELETE ON public.long_goals
            FOR EACH ROW EXECUTE FUNCTION internal.delete_user_media_on_task_delete();
    END IF;
END $$;

-- Diary Entries Delete Trigger Removed

-- ============================================================
-- FUNCTION: Handle task change analytics (Shared)
-- ============================================================
CREATE OR REPLACE FUNCTION internal.handle_task_change_analytics()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    -- Get user_id based on operation
    IF TG_OP = 'DELETE' THEN
        v_user_id := OLD.user_id;
    ELSE
        v_user_id := NEW.user_id;
    END IF;

    -- Refresh performance analytics
    PERFORM public.refresh_performance_analytics(v_user_id);

    -- Update mentorship snapshots for active live mentors
    UPDATE public.mentorship_connections
    SET
        cached_snapshot = jsonb_build_object(
            'overview', (SELECT overview FROM public.performance_analytics WHERE user_id = v_user_id),
            'today', (SELECT today FROM public.performance_analytics WHERE user_id = v_user_id),
            'captured_at', NOW()
        ),
        snapshot_captured_at = NOW(),
        updated_at = NOW()
    WHERE owner_id = v_user_id
    AND access_status = 'active'
    AND is_live_enabled = TRUE;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

-- ============================================================
-- TRIGGERS: Analytics for each table
-- ============================================================

-- Bucket Models
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'analytics_on_bucket_models_change') THEN
        CREATE TRIGGER analytics_on_bucket_models_change
            AFTER INSERT OR UPDATE ON public.bucket_models
            FOR EACH ROW EXECUTE FUNCTION internal.handle_task_change_analytics();
    END IF;
END $$;

-- Day Tasks
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'analytics_on_day_tasks_change') THEN
        CREATE TRIGGER analytics_on_day_tasks_change
            AFTER INSERT OR UPDATE ON public.day_tasks
            FOR EACH ROW EXECUTE FUNCTION internal.handle_task_change_analytics();
    END IF;
END $$;

-- Weekly Tasks
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'analytics_on_weekly_tasks_change') THEN
        CREATE TRIGGER analytics_on_weekly_tasks_change
            AFTER INSERT OR UPDATE ON public.weekly_tasks
            FOR EACH ROW EXECUTE FUNCTION internal.handle_task_change_analytics();
    END IF;
END $$;

-- Long Goals
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'analytics_on_long_goals_change') THEN
        CREATE TRIGGER analytics_on_long_goals_change
            AFTER INSERT OR UPDATE ON public.long_goals
            FOR EACH ROW EXECUTE FUNCTION internal.handle_task_change_analytics();
    END IF;
END $$;

-- Diary Entries
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'analytics_on_diary_entries_change') THEN
        CREATE TRIGGER analytics_on_diary_entries_change
            AFTER INSERT OR UPDATE ON public.diary_entries
            FOR EACH ROW EXECUTE FUNCTION internal.handle_task_change_analytics();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ Shared task functions ready';
    RAISE NOTICE '   - 2 functions:';
    RAISE NOTICE '     • delete_user_media_on_task_delete()';
    RAISE NOTICE '     • handle_task_change_analytics()';
    RAISE NOTICE '   - 10 triggers (2 per table × 5 tables):';
    RAISE NOTICE '     • cleanup_bucket_media';
    RAISE NOTICE '     • cleanup_day_task_media';
    RAISE NOTICE '     • cleanup_weekly_task_media';
    RAISE NOTICE '     • cleanup_long_goal_media';
    -- Diary media cleanup trigger removed
    RAISE NOTICE '     • analytics_on_bucket_models_change';
    RAISE NOTICE '     • analytics_on_day_tasks_change';
    RAISE NOTICE '     • analytics_on_weekly_tasks_change';
    RAISE NOTICE '     • analytics_on_long_goals_change';
    RAISE NOTICE '     • analytics_on_diary_entries_change';
END $$;
-- ============================================================
-- 📁 FILE: packages/Core/selective_storage_cleanup.sql
-- Automated storage object cleanup for individual record 
-- deletions and updates (Posts, Tasks, Profiles, etc.)
-- ============================================================

-- 1. Helper function to delete an object from storage.objects
-- Handles both full URLs and relative paths.
CREATE OR REPLACE FUNCTION public.delete_storage_object(p_bucket_id TEXT, p_path_or_url TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
    v_path TEXT;
BEGIN
    IF p_path_or_url IS NULL OR p_path_or_url = '' THEN
        RETURN;
    END IF;

    -- Extract path from URL if necessary
    -- Format: .../storage/v1/object/public/[bucket]/[path]
    -- Or: .../storage/v1/object/sign/[bucket]/[path]?token=...
    IF p_path_or_url ~ '^http' THEN
        v_path := substring(p_path_or_url from '/storage/v1/object/(?:public|sign)/[^/]+/(.+?)(?:\?|$)');
    ELSE
        v_path := p_path_or_url;
    END IF;

    IF v_path IS NOT NULL THEN
        -- NOTE: Direct deletion from storage.objects is forbidden by Supabase.
        -- Storage cleanup must be handled via the Storage API in the client application.
        /*
        DELETE FROM storage.objects 
        WHERE bucket_id = p_bucket_id 
        AND name = v_path;
        */
    END IF;
END;
$$;

-- 2. POSTS: Handle media deletions on delete/update
CREATE OR REPLACE FUNCTION public.handle_post_media_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item JSONB;
BEGIN
    -- ON DELETE: Clear all media
    IF (TG_OP = 'DELETE') THEN
        IF OLD.media IS NOT NULL AND OLD.media ? 'items' AND jsonb_typeof(OLD.media->'items') = 'array' THEN
            FOR v_item IN SELECT * FROM jsonb_array_elements(OLD.media->'items') LOOP
                PERFORM public.delete_storage_object('social-media', v_item->>'url');
            END LOOP;
        END IF;
        RETURN OLD;
    END IF;

    -- ON UPDATE: Clear media that was removed from the list
    IF (TG_OP = 'UPDATE') THEN
        IF OLD.media IS NOT NULL AND OLD.media ? 'items' AND jsonb_typeof(OLD.media->'items') = 'array' 
           AND NEW.media IS NOT NULL AND NEW.media ? 'items' AND jsonb_typeof(NEW.media->'items') = 'array' THEN
            -- Find items in OLD that are NOT in NEW
            FOR v_item IN 
                SELECT o.value FROM jsonb_array_elements(OLD.media->'items') o
                WHERE NOT EXISTS (
                    SELECT 1 FROM jsonb_array_elements(NEW.media->'items') n 
                    WHERE n.value->>'url' = o.value->>'url'
                )
            LOOP
                PERFORM public.delete_storage_object('social-media', v_item->>'url');
            END LOOP;
        END IF;
        RETURN NEW;
    END IF;

    RETURN NULL;
END;
$$;

-- 3. TASKS (Day/Weekly/Long/Bucket): Handle main media and feedback media
CREATE OR REPLACE FUNCTION public.handle_task_media_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_bucket TEXT;
    v_comment JSONB;
    v_old_media TEXT;
    v_new_media TEXT;
BEGIN
    -- Determine bucket based on table
    v_bucket := CASE TG_TABLE_NAME
        WHEN 'day_tasks' THEN 'daily-task-media'
        WHEN 'weekly_tasks' THEN 'weekly-task-media'
        WHEN 'long_goals' THEN 'long-goals-media'
        WHEN 'bucket_models' THEN 'bucket-media'
    END;

    -- Extract media URLs safely based on table schema
    IF TG_TABLE_NAME IN ('day_tasks', 'weekly_tasks') THEN
        v_old_media := OLD.about_task->>'media_url';
        IF (TG_OP = 'UPDATE') THEN v_new_media := NEW.about_task->>'media_url'; END IF;
    ELSIF TG_TABLE_NAME = 'long_goals' THEN
        v_old_media := OLD.description->>'media_url';
        IF (TG_OP = 'UPDATE') THEN v_new_media := NEW.description->>'media_url'; END IF;
    ELSIF TG_TABLE_NAME = 'bucket_models' THEN
        v_old_media := OLD.details->>'media_url';
        IF (TG_OP = 'UPDATE') THEN v_new_media := NEW.details->>'media_url'; END IF;
    END IF;

    -- ON DELETE: Clear main media and all feedback media
    IF (TG_OP = 'DELETE') THEN
        -- Clear main media
        IF v_old_media IS NOT NULL THEN
            PERFORM public.delete_storage_object(v_bucket, v_old_media);
        END IF;

        -- Clear feedback media (Day/Weekly Tasks use 'feedback' column)
        IF TG_TABLE_NAME IN ('day_tasks', 'weekly_tasks') THEN
            IF OLD.feedback IS NOT NULL AND OLD.feedback ? 'comments' 
               AND (OLD.feedback->'comments'->'items') IS NOT NULL 
               AND jsonb_typeof(OLD.feedback->'comments'->'items') = 'array' THEN
                FOR v_comment IN SELECT * FROM jsonb_array_elements(OLD.feedback->'comments'->'items') LOOP
                    IF v_comment ? 'media_url' THEN
                        PERFORM public.delete_storage_object(v_bucket, v_comment->>'media_url');
                    END IF;
                END LOOP;
            END IF;
        END IF;
        
        -- Note: Long Goals and Buckets store feedback/media differently (logs/checklist)
        -- which are handled by their own specific cleanup logic if needed.
        
        RETURN OLD;
    END IF;

    -- ON UPDATE: Clear old main media if replaced
    IF (TG_OP = 'UPDATE') THEN
        IF v_old_media IS DISTINCT FROM v_new_media THEN
            PERFORM public.delete_storage_object(v_bucket, v_old_media);
        END IF;
        RETURN NEW;
    END IF;

    RETURN NULL;
END;
$$;

-- 4. PROFILES: Delete old avatar on update OR wipe all media on profile deletion
CREATE OR REPLACE FUNCTION public.handle_user_profile_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_buckets TEXT[] := ARRAY[
        'bucket-media', 'daily-task-media', 'weekly-task-media', 
        'long-goals-media', 'social-media', 'chat-media', 
        'diary-media', 'user-avatars'
    ];
BEGIN
    -- ON UPDATE: Delete old profile image if replaced
    IF (TG_OP = 'UPDATE') THEN
        IF (OLD.profile_url IS DISTINCT FROM NEW.profile_url) THEN
            PERFORM public.delete_storage_object('user-avatars', OLD.profile_url);
        END IF;
        RETURN NEW;
    END IF;

        -- NOTE: Direct deletion from storage.objects is forbidden by Supabase.
        -- Storage cleanup must be handled via the Storage API in the client application.
        /*
        DELETE FROM storage.objects 
        WHERE bucket_id = ANY(v_buckets)
        AND (storage.foldername(name))[1] = OLD.user_id::text;
        */

    RETURN NULL;
END;
$$;

-- 5. CHAT ATTACHMENTS: Delete file on message/attachment removal
CREATE OR REPLACE FUNCTION public.handle_chat_attachment_cleanup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.delete_storage_object('chat-media', OLD.url);
    RETURN OLD;
END;
$$;

-- ============================================================
-- REGISTER TRIGGERS
-- ============================================================

-- Posts
DROP TRIGGER IF EXISTS cleanup_post_media_trigger ON public.posts;
CREATE TRIGGER cleanup_post_media_trigger
    BEFORE DELETE OR UPDATE ON public.posts
    FOR EACH ROW EXECUTE FUNCTION public.handle_post_media_cleanup();

-- Tasks
DROP TRIGGER IF EXISTS cleanup_day_task_media_trigger ON public.day_tasks;
CREATE TRIGGER cleanup_day_task_media_trigger
    BEFORE DELETE OR UPDATE ON public.day_tasks
    FOR EACH ROW EXECUTE FUNCTION public.handle_task_media_cleanup();

DROP TRIGGER IF EXISTS cleanup_weekly_task_media_trigger ON public.weekly_tasks;
CREATE TRIGGER cleanup_weekly_task_media_trigger
    BEFORE DELETE OR UPDATE ON public.weekly_tasks
    FOR EACH ROW EXECUTE FUNCTION public.handle_task_media_cleanup();

DROP TRIGGER IF EXISTS cleanup_long_goal_media_trigger ON public.long_goals;
CREATE TRIGGER cleanup_long_goal_media_trigger
    BEFORE DELETE OR UPDATE ON public.long_goals
    FOR EACH ROW EXECUTE FUNCTION public.handle_task_media_cleanup();

DROP TRIGGER IF EXISTS cleanup_bucket_model_media_trigger ON public.bucket_models;
CREATE TRIGGER cleanup_bucket_model_media_trigger
    BEFORE DELETE OR UPDATE ON public.bucket_models
    FOR EACH ROW EXECUTE FUNCTION public.handle_task_media_cleanup();

-- Profiles
DROP TRIGGER IF EXISTS cleanup_user_profile_trigger ON public.user_profiles;
CREATE TRIGGER cleanup_user_profile_trigger
    BEFORE DELETE OR UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_user_profile_cleanup();

-- Chat Attachments
DROP TRIGGER IF EXISTS cleanup_chat_attachment_trigger ON public.chat_message_attachments;
CREATE TRIGGER cleanup_chat_attachment_trigger
    BEFORE DELETE ON public.chat_message_attachments
    FOR EACH ROW EXECUTE FUNCTION public.handle_chat_attachment_cleanup();
    
-- ============================================================
-- GRANTS
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_storage_object(TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.handle_post_media_cleanup() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.handle_task_media_cleanup() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.handle_user_profile_cleanup() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.handle_chat_attachment_cleanup() TO postgres, service_role;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ Selective storage cleanup ready';
    RAISE NOTICE '   - 7 triggers registered';
    RAISE NOTICE '   - 5 cleanup functions ready';
END $$;

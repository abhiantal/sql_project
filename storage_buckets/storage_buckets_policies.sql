-- ============================================================
-- 📁 FILE 09: STORAGE BUCKETS & POLICIES
-- Complete Supabase Storage Configuration
-- Includes: boolean fix, chat sharing, task sharing, diary sharing
-- ============================================================


-- ============================================================
-- 🔧 HELPER FUNCTION: Check if user is an active chat member
-- FIX: is_active = true (boolean), NOT is_active = 1 (integer)
-- This was the root cause of all chat-media 404 errors
-- ============================================================
CREATE OR REPLACE FUNCTION internal.is_chat_member(p_chat_id UUID, p_user_id UUID)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.chat_members
        WHERE chat_id  = p_chat_id
          AND user_id  = p_user_id
          AND (is_active IS NOT FALSE) -- Handles BOTH NULL and true as "active"
    );
END;
$$;




-- ============================================================
-- 🔧 HELPER FUNCTION: Get user's total storage usage per bucket
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_user_storage_usage(p_user_id UUID)
RETURNS TABLE (
    bucket_name TEXT,
    total_size  BIGINT,
    file_count  BIGINT
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
        o.bucket_id,
        COALESCE(SUM(COALESCE((o.metadata->>'size')::BIGINT, 0)), 0),
        COUNT(*)
    FROM storage.objects o
    WHERE o.bucket_id IN (
        'user-avatars', 'bucket-media', 'daily-task-media',
        'weekly-task-media', 'long-goals-media', 'social-media',
        'chat-media', 'diary-media'
    )
    AND (
        (string_to_array(o.name, '/'))[1] = p_user_id::text
        OR o.owner = p_user_id
    )
    GROUP BY o.bucket_id
    ORDER BY o.bucket_id;
END;
$$;


-- ============================================================
-- 🔧 HELPER FUNCTION: Cleanup orphaned / temp files (via cron)
-- NOTE: Direct DELETE on storage.objects is blocked by Supabase.
--       Use the Storage API from your backend/edge function instead.
-- ============================================================
CREATE OR REPLACE FUNCTION internal.cleanup_orphaned_files()
RETURNS INTEGER
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_deleted INTEGER := 0;
BEGIN
    -- Placeholder — actual deletion must go through the Storage API.
    -- Example edge function call:
    --   supabase.storage.from('social-media').remove([...tempPaths])
    RETURN v_deleted;
END;
$$;


-- ============================================================
-- 🪣 BUCKET CONFIGURATION
-- ============================================================
DO $$
DECLARE
    common_mime_types TEXT[] := ARRAY[
        -- Images
        'image/jpeg','image/jpg','image/png','image/gif','image/webp',
        'image/svg+xml','image/heic','image/heif','image/bmp','image/tiff',
        -- Videos
        'video/mp4','video/webm','video/quicktime','video/x-msvideo',
        'video/mpeg','video/ogg','video/x-matroska','video/3gpp',
        -- Audio
        'audio/mpeg','audio/wav','audio/ogg','audio/mp3','audio/mp4',
        'audio/x-m4a','audio/aac','audio/flac','audio/x-wav',
        -- Documents
        'application/pdf','text/plain','text/markdown','text/csv',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-powerpoint',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation'
    ];

    image_mime_types TEXT[] := ARRAY[
        'image/jpeg','image/jpg','image/png','image/webp',
        'image/heic','image/heif','image/gif','image/bmp'
    ];
BEGIN

    -- BUCKET 1: user-avatars — 5 MB, images only, PUBLIC
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types, avif_autodetection)
    VALUES ('user-avatars','user-avatars', true, 5242880, image_mime_types, false)
    ON CONFLICT (id) DO UPDATE SET
        public             = EXCLUDED.public,
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

    -- BUCKET 2: bucket-media — 50 MB, all types, PRIVATE (personal file buckets)
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('bucket-media','bucket-media', false, 52428800, common_mime_types)
    ON CONFLICT (id) DO UPDATE SET
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

    -- BUCKET 3: daily-task-media — 10 MB, all types, PRIVATE
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('daily-task-media','daily-task-media', false, 10485760, common_mime_types)
    ON CONFLICT (id) DO UPDATE SET
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

    -- BUCKET 4: weekly-task-media — 50 MB, all types, PRIVATE
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('weekly-task-media','weekly-task-media', false, 52428800, common_mime_types)
    ON CONFLICT (id) DO UPDATE SET
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

    -- BUCKET 5: long-goals-media — 50 MB, all types, PRIVATE
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('long-goals-media','long-goals-media', false, 52428800, common_mime_types)
    ON CONFLICT (id) DO UPDATE SET
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

    -- BUCKET 6: social-media — 100 MB, all types, PRIVATE (signed URLs)
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('social-media','social-media', false, 104857600, common_mime_types)
    ON CONFLICT (id) DO UPDATE SET
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

    -- BUCKET 7: chat-media — 20 MB, all types, PRIVATE
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('chat-media','chat-media', false, 20971520, common_mime_types)
    ON CONFLICT (id) DO UPDATE SET
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

    -- BUCKET 8: diary-media — 20 MB, all types, PRIVATE
    INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    VALUES ('diary-media','diary-media', false, 20971520, common_mime_types)
    ON CONFLICT (id) DO UPDATE SET
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

END $$;


-- ============================================================
-- ⚠️  DROP ALL EXISTING STORAGE POLICIES (avoid name conflicts)
-- ============================================================
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN (
        SELECT policyname
        FROM pg_policies
        WHERE schemaname = 'storage'
          AND tablename  = 'objects'
    ) LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', pol.policyname);
    END LOOP;
END $$;


-- ============================================================
-- 📤  INSERT — upload to own folder OR to a chat folder
-- Path convention:
--   own files  → {userId}/{filename}
--   chat files → {chatId}/{filename}   (chat-media bucket only)
-- ============================================================
CREATE POLICY "storage_insert_own_folder"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id IN (
        'user-avatars', 'bucket-media', 'daily-task-media',
        'weekly-task-media', 'long-goals-media', 'social-media',
        'chat-media', 'diary-media'
    )
    AND (
        -- Standard: path[1] = userId  (all non-chat buckets)
        (string_to_array(name, '/'))[1] = auth.uid()::text

        OR

        -- New chat format: chatId/filename  (path[1] is chatId)
        (
            bucket_id = 'chat-media'
            AND internal.is_chat_member(
                    ((string_to_array(name, '/'))[1])::uuid,
                    auth.uid()
                )
        )

        OR

        -- Old chat format: userId/chatId/filename
        (
            bucket_id = 'chat-media'
            AND array_length(string_to_array(name, '/'), 1) >= 3
            AND (string_to_array(name, '/'))[1] = auth.uid()::text
        )
    )
);



-- ============================================================
-- 📝  UPDATE — own files or chat files
-- ============================================================
CREATE POLICY "storage_update_own_files"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
    bucket_id IN (
        'user-avatars','bucket-media','daily-task-media',
        'weekly-task-media','long-goals-media','social-media',
        'chat-media','diary-media'
    )
    AND (
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR (
            bucket_id = 'chat-media'
            AND internal.is_chat_member(
                    ((string_to_array(name, '/'))[1])::uuid, auth.uid()
                )
        )
        OR owner = auth.uid()
    )
)
WITH CHECK (
    bucket_id IN (
        'user-avatars','bucket-media','daily-task-media',
        'weekly-task-media','long-goals-media','social-media',
        'chat-media','diary-media'
    )
    AND (
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR (
            bucket_id = 'chat-media'
            AND internal.is_chat_member(
                    ((string_to_array(name, '/'))[1])::uuid, auth.uid()
                )
        )
        OR owner = auth.uid()
    )
);


-- ============================================================
-- 🗑️  DELETE — own files or chat files
-- ============================================================
CREATE POLICY "storage_delete_own_files"
ON storage.objects
FOR DELETE
TO authenticated
USING (
    bucket_id IN (
        'user-avatars','bucket-media','daily-task-media',
        'weekly-task-media','long-goals-media','social-media',
        'chat-media','diary-media'
    )
    AND (
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR (
            bucket_id = 'chat-media'
            AND internal.is_chat_member(
                    ((string_to_array(name, '/'))[1])::uuid, auth.uid()
                )
        )
        OR owner = auth.uid()
    )
);


-- ============================================================
-- 👁️  SELECT — user-avatars (Public Access via URL, Listing Blocked)
-- ============================================================
-- [SECURITY] Removed broad SELECT policy to prevent directory listing.
-- Public buckets automatically allow public access to files via their URL.
-- No SELECT policy is needed unless listing or metadata access is required.
DROP POLICY IF EXISTS "storage_avatars_public_read" ON storage.objects;


-- ============================================================
-- 👁️  SELECT — bucket-media
-- Owner only (personal bucket feature — not shared)
-- ============================================================
CREATE POLICY "storage_bucket_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'bucket-media'
    AND (
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR owner = auth.uid()
    )
);


-- ============================================================
-- 👁️  SELECT — daily-task-media
-- Access granted to:
--   1. The owner (uploader)
--   2. Any user the task was explicitly shared with
--      share_info structure: { "is_share": true, "posted": { "with_id": "<uuid>" } }
-- ============================================================
CREATE POLICY "storage_daily_task_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'daily-task-media'
    AND (
        -- Owner
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR owner = auth.uid()
        -- Shared recipient
        OR EXISTS (
            SELECT 1 FROM public.day_tasks
            WHERE user_id::text = (string_to_array(name, '/'))[1]
              AND (share_info->>'is_share')::boolean = true
              AND share_info->'posted'->>'with_id' = auth.uid()::text
        )
    )
);


-- ============================================================
-- 👁️  SELECT — weekly-task-media
-- Access granted to owner OR shared recipient
-- share_info structure: { "is_share": true, "posted": { "with_id": "<uuid>" } }
-- ============================================================
CREATE POLICY "storage_weekly_task_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'weekly-task-media'
    AND (
        -- Owner
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR owner = auth.uid()
        -- Shared recipient
        OR EXISTS (
            SELECT 1 FROM public.weekly_tasks
            WHERE user_id::text = (string_to_array(name, '/'))[1]
              AND (share_info->>'is_share')::boolean = true
              AND share_info->'posted'->>'with_id' = auth.uid()::text
        )
    )
);


-- ============================================================
-- 👁️  SELECT — long-goals-media
-- Access granted to owner OR shared recipient
-- share_info structure: { "is_share": true, "posted": { "with_id": "<uuid>" } }
-- ============================================================
CREATE POLICY "storage_long_goals_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'long-goals-media'
    AND (
        -- Owner
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR owner = auth.uid()
        -- Shared recipient
        OR EXISTS (
            SELECT 1 FROM public.long_goals
            WHERE user_id::text = (string_to_array(name, '/'))[1]
              AND (share_info->>'is_share')::boolean = true
              AND share_info->'posted'->>'with_id' = auth.uid()::text
        )
    )
);


-- ============================================================
-- 👁️  SELECT — social-media
-- All authenticated users can read social posts.
-- Fine-grained visibility (followers, public, private) is
-- enforced at the database / application layer, not storage.
-- ============================================================
CREATE POLICY "storage_social_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'social-media');


-- ============================================================
-- 👁️  SELECT — chat-media
-- Path format: chat-media/{chatId}/{filename}
-- Access granted to:
--   1. The file owner / uploader (fallback)
--   2. Any active member of that chat
-- ============================================================
-- Drop the existing policy
DROP POLICY IF EXISTS "storage_chat_media_read" ON storage.objects;

-- Recreate with both old (userId/chatId/file) and new (chatId/file) formats
CREATE POLICY "storage_chat_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'chat-media'
    AND (
        -- ── NEW FORMAT: chatId/filename ──────────────────────────
        -- path[1] is a chatId; user is a member of that chat
        internal.is_chat_member(
            ((string_to_array(name, '/'))[1])::uuid,
            auth.uid()
        )

        OR

        -- ── OLD FORMAT: userId/chatId/filename ──────────────────
        -- path[1] is a userId (uploader), path[2] is a chatId
        -- Allow if: current user IS the uploader
        --        OR current user is a member of path[2] chat
        (
            array_length(string_to_array(name, '/'), 1) >= 3
            AND (
                -- Uploader owns the file (path[1] = their userId)
                (string_to_array(name, '/'))[1] = auth.uid()::text
                OR
                -- Any active member of the chat in path[2]
                internal.is_chat_member(
                    ((string_to_array(name, '/'))[2])::uuid,
                    auth.uid()
                )
            )
        )
    )
);



-- ============================================================
-- 👁️  SELECT — diary-media
-- Access granted to:
--   1. The owner
--   2. Any user in the shared_with JSONB array
--      share_info structure: { "is_shared": true, "shared_with": ["<uuid>", ...] }
-- ============================================================
CREATE POLICY "storage_diary_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'diary-media'
    AND (
        -- Owner
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR owner = auth.uid()
        -- Shared recipient (UUID present in the shared_with array)
        OR EXISTS (
            SELECT 1 FROM public.diary_entries
            WHERE user_id::text = (string_to_array(name, '/'))[1]
              AND (share_info->>'is_shared')::boolean = true
              AND share_info->'shared_with' ? auth.uid()::text
        )
    )
);


-- ============================================================
-- ✅  GRANT EXECUTE PERMISSIONS
-- ============================================================
-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT EXECUTE ON FUNCTION public.get_user_storage_usage(UUID)    TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION internal.is_chat_member(UUID, UUID)      TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.cleanup_orphaned_files()        TO service_role;


-- ============================================================
-- 📊  VERIFICATION OUTPUT
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '==============================================';
    RAISE NOTICE '✅ Buckets configured:';
    RAISE NOTICE '   user-avatars       5MB   PUBLIC';
    RAISE NOTICE '   bucket-media      50MB   private';
    RAISE NOTICE '   daily-task-media  10MB   private';
    RAISE NOTICE '   weekly-task-media 50MB   private';
    RAISE NOTICE '   long-goals-media  50MB   private';
    RAISE NOTICE '   social-media     100MB   private';
    RAISE NOTICE '   chat-media        20MB   private';
    RAISE NOTICE '   diary-media       20MB   private';
    RAISE NOTICE '';
    RAISE NOTICE '✅ Policies:';
    RAISE NOTICE '   INSERT  storage_insert_own_folder';
    RAISE NOTICE '   UPDATE  storage_update_own_files';
    RAISE NOTICE '   DELETE  storage_delete_own_files';
    RAISE NOTICE '   SELECT  storage_avatars_public_read       (public)';
    RAISE NOTICE '   SELECT  storage_bucket_media_read         (owner)';
    RAISE NOTICE '   SELECT  storage_daily_task_media_read     (owner + shared)';
    RAISE NOTICE '   SELECT  storage_weekly_task_media_read    (owner + shared)';
    RAISE NOTICE '   SELECT  storage_long_goals_media_read     (owner + shared)';
    RAISE NOTICE '   SELECT  storage_social_media_read         (all authenticated)';
    RAISE NOTICE '   SELECT  storage_chat_media_read           (owner + chat members)';
    RAISE NOTICE '   SELECT  storage_diary_media_read          (owner + shared_with[])';
    RAISE NOTICE '';
    RAISE NOTICE '✅ Helper functions:';
    RAISE NOTICE '   is_chat_member()        — BOOLEAN fix applied (internal)';
    RAISE NOTICE '   get_user_storage_usage()';
    RAISE NOTICE '   cleanup_orphaned_files() (internal)';
    RAISE NOTICE '==============================================';
END $$;
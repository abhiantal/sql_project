-- ============================================================
-- 📁 DATABASE & STORAGE HARDENING SCRIPT
-- FILE: C:\StudioProjects\the_time_chart\packages\20260501_final_hardening.sql
-- ============================================================

-- ============================================================
-- 1️⃣ FIX: DEDUPLICATION UNIQUE INDEX ON POST_VIEWS
-- Resolves standard PostgREST ON CONFLICT spec crash
-- ============================================================
DROP INDEX IF EXISTS public.idx_post_views_dedup;

CREATE UNIQUE INDEX IF NOT EXISTS idx_post_views_dedup
    ON public.post_views(post_id, user_id, view_date);


-- ============================================================
-- 2️⃣ HELPER FUNCTION: Check if user is an active chat member
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
          AND (is_active IS NOT FALSE)
    );
END;
$$;


-- ============================================================
-- 3️⃣ HELPER FUNCTION: Storage stats & Usage
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
-- 4️⃣ CONFIGURATION: CREATE & SET UP ALL STORAGE BUCKETS
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
-- 5️⃣  DROP ALL EXISTING STORAGE POLICIES TO AVOID DUPLICATES
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
-- 6️⃣ CREATE NEW, HIGH-COMPATIBILITY ROW LEVEL SECURITY POLICIES
-- ============================================================

-- 📤 INSERT Policy (Handles both old flat and new nested paths safely)
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
        (string_to_array(name, '/'))[1] = auth.uid()::text

        OR

        (
            bucket_id = 'chat-media'
            AND internal.is_chat_member(
                    ((string_to_array(name, '/'))[1])::uuid,
                    auth.uid()
                )
        )

        OR

        (
            bucket_id = 'chat-media'
            AND array_length(string_to_array(name, '/'), 1) >= 3
            AND (string_to_array(name, '/'))[1] = auth.uid()::text
        )
    )
);

-- 📝 UPDATE Policy
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

-- 🗑️ DELETE Policy
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

-- 👁️ SELECT Policy — bucket-media
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

-- 👁️ SELECT Policy — daily-task-media
CREATE POLICY "storage_daily_task_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'daily-task-media'
    AND (
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR owner = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.day_tasks
            WHERE user_id::text = (string_to_array(name, '/'))[1]
              AND (share_info->>'is_share')::boolean = true
              AND share_info->'posted'->>'with_id' = auth.uid()::text
        )
    )
);

-- 👁️ SELECT Policy — weekly-task-media
CREATE POLICY "storage_weekly_task_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'weekly-task-media'
    AND (
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR owner = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.weekly_tasks
            WHERE user_id::text = (string_to_array(name, '/'))[1]
              AND (share_info->>'is_share')::boolean = true
              AND share_info->'posted'->>'with_id' = auth.uid()::text
        )
    )
);

-- 👁️ SELECT Policy — long-goals-media
CREATE POLICY "storage_long_goals_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'long-goals-media'
    AND (
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR owner = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.long_goals
            WHERE user_id::text = (string_to_array(name, '/'))[1]
              AND (share_info->>'is_share')::boolean = true
              AND share_info->'posted'->>'with_id' = auth.uid()::text
        )
    )
);

-- 👁️ SELECT Policy — social-media
CREATE POLICY "storage_social_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'social-media');

-- 👁️ SELECT Policy — chat-media
CREATE POLICY "storage_chat_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'chat-media'
    AND (
        internal.is_chat_member(
            ((string_to_array(name, '/'))[1])::uuid,
            auth.uid()
        )
        OR
        (
            array_length(string_to_array(name, '/'), 1) >= 3
            AND (
                (string_to_array(name, '/'))[1] = auth.uid()::text
                OR
                internal.is_chat_member(
                    ((string_to_array(name, '/'))[2])::uuid,
                    auth.uid()
                )
            )
        )
    )
);

-- 👁️ SELECT Policy — diary-media
CREATE POLICY "storage_diary_media_read"
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'diary-media'
    AND (
        (string_to_array(name, '/'))[1] = auth.uid()::text
        OR owner = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.diary_entries
            WHERE user_id::text = (string_to_array(name, '/'))[1]
              AND (share_info->>'is_shared')::boolean = true
              AND share_info->'shared_with' ? auth.uid()::text
        )
    )
);


-- ============================================================
-- 7️⃣ GRANTS & FINAL CONFIRMATION
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_storage_usage(UUID) TO authenticated;
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION internal.is_chat_member(UUID, UUID) TO authenticated, service_role;

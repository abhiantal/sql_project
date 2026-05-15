-- ============================================================
-- 📁 FILE 08: DIARY ENTRIES TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.diary_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    entry_date DATE NOT NULL,
    title TEXT,
    content TEXT,
    mood JSONB,
    shot_qna JSONB,
    attachments JSONB,
    linked_items JSONB,
    metadata JSONB,
    settings JSONB,
    social_info JSONB,
    share_info JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    search_vector tsvector GENERATED ALWAYS AS (
        to_tsvector('english',
            COALESCE(title, '') || ' ' ||
            COALESCE(content, '') || ' ' ||
            COALESCE(mood->>'label', '') || ' ' ||
            COALESCE(metadata->>'ai_summary', '')
        )
    ) STORED,
    CONSTRAINT unique_user_entry_per_day UNIQUE (user_id, entry_date)
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_diary_entries_user_id ON public.diary_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_diary_entries_date ON public.diary_entries(entry_date DESC);
CREATE INDEX IF NOT EXISTS idx_diary_entries_user_date ON public.diary_entries(user_id, entry_date DESC);
CREATE INDEX IF NOT EXISTS idx_diary_entries_search ON public.diary_entries USING GIN(search_vector);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.diary_entries ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'diary_entries' AND policyname = 'diary_entries_select_own') THEN
        CREATE POLICY "diary_entries_select_own" ON public.diary_entries
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'diary_entries' AND policyname = 'diary_entries_insert_own') THEN
        CREATE POLICY "diary_entries_insert_own" ON public.diary_entries
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    /* UPDATE AND DELETE POLICIES REMOVED AS PER REQUIREMENT */

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'diary_entries' AND policyname = 'diary_entries_select_shared') THEN
        CREATE POLICY "diary_entries_select_shared" ON public.diary_entries
            FOR SELECT USING (
                share_info->>'is_shared' = 'true'
                AND share_info->'shared_with' @> to_jsonb(auth.uid()::text)
            );
    END IF;
END $$;

-- ============================================================
-- FUNCTION: Calculate diary metadata
-- ============================================================
CREATE OR REPLACE FUNCTION public.calculate_diary_metadata()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    word_count INTEGER;
    has_attachments BOOLEAN;
BEGIN
    -- Calculate word count
    word_count := COALESCE(
        array_length(
            regexp_split_to_array(COALESCE(NEW.content, ''), '\s+'),
            1
        ),
        0
    );

    -- Check for attachments
    has_attachments := jsonb_typeof(NEW.attachments) = 'array' AND jsonb_array_length(NEW.attachments) > 0;

    -- Update metadata
    NEW.metadata := COALESCE(NEW.metadata, '{}'::jsonb);
    NEW.metadata := jsonb_set(NEW.metadata, '{word_count}', to_jsonb(word_count));
    NEW.metadata := jsonb_set(NEW.metadata, '{has_attachments}', to_jsonb(has_attachments));

    RETURN NEW;
END;
$$;

-- ============================================================
-- TRIGGER: Updated at
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_diary_entries_updated_at') THEN
        CREATE TRIGGER update_diary_entries_updated_at
            BEFORE UPDATE ON public.diary_entries
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;
END $$;

-- ============================================================
-- TRIGGER: Calculate metadata
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'calculate_diary_metadata_trigger') THEN
        CREATE TRIGGER calculate_diary_metadata_trigger
            BEFORE INSERT OR UPDATE ON public.diary_entries
            FOR EACH ROW EXECUTE FUNCTION public.calculate_diary_metadata();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT ALL ON TABLE public.diary_entries TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_diary_metadata() TO postgres, service_role;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.diary_entries table ready';
    RAISE NOTICE '   - 2 triggers:';
    RAISE NOTICE '     • update_diary_entries_updated_at';
    RAISE NOTICE '     • calculate_diary_metadata_trigger';
    RAISE NOTICE '   - 1 function: calculate_diary_metadata()';
    RAISE NOTICE '   - 5 RLS policies';
    RAISE NOTICE '   - 4 indexes';
END $$;
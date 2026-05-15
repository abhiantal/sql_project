-- ============================================================
-- 📁 FILE 04: BUCKET MODELS TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.bucket_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    category_type TEXT,
    sub_types TEXT,
    title TEXT NOT NULL,
    details JSONB,
    checklist JSONB,
    timeline JSONB,
    metadata JSONB,
    social_info JSONB,
    share_info JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    search_vector tsvector GENERATED ALWAYS AS (
        to_tsvector('english', COALESCE(title, '') || ' ' || COALESCE(details->>'description', ''))
    ) STORED
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_bucket_models_user_id ON public.bucket_models(user_id);
CREATE INDEX IF NOT EXISTS idx_bucket_models_category ON public.bucket_models(category_id);
CREATE INDEX IF NOT EXISTS idx_bucket_models_created ON public.bucket_models(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bucket_models_search ON public.bucket_models USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS idx_bucket_models_user_created ON public.bucket_models(user_id, created_at DESC);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.bucket_models ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bucket_models' AND policyname = 'bucket_models_select_own') THEN
        CREATE POLICY "bucket_models_select_own" ON public.bucket_models
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bucket_models' AND policyname = 'bucket_models_insert_own') THEN
        CREATE POLICY "bucket_models_insert_own" ON public.bucket_models
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bucket_models' AND policyname = 'bucket_models_update_own') THEN
        CREATE POLICY "bucket_models_update_own" ON public.bucket_models
            FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bucket_models' AND policyname = 'bucket_models_delete_own') THEN
        CREATE POLICY "bucket_models_delete_own" ON public.bucket_models
            FOR DELETE USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================
-- TRIGGER: Updated at
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_bucket_models_updated_at') THEN
        CREATE TRIGGER update_bucket_models_updated_at
            BEFORE UPDATE ON public.bucket_models
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT ALL ON TABLE public.bucket_models TO authenticated;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.bucket_models table ready';
    RAISE NOTICE '   - 1 trigger: update_bucket_models_updated_at';
    RAISE NOTICE '   - 4 RLS policies';
    RAISE NOTICE '   - 5 indexes';
END $$;
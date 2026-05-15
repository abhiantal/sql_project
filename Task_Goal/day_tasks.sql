-- ============================================================
-- 📁 FILE 05: DAY TASKS TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.day_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    category_type TEXT,
    sub_types TEXT,
    about_task JSONB NOT NULL,
    indicators JSONB,
    timeline JSONB NOT NULL,
    feedback JSONB,
    metadata JSONB,
    social_info JSONB,
    share_info JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_day_tasks_user_id ON public.day_tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_day_tasks_category ON public.day_tasks(category_id);
CREATE INDEX IF NOT EXISTS idx_day_tasks_category_type ON public.day_tasks(category_type);
CREATE INDEX IF NOT EXISTS idx_day_tasks_created ON public.day_tasks(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_day_tasks_status ON public.day_tasks((metadata->>'is_complete'));
CREATE INDEX IF NOT EXISTS idx_day_tasks_task_date ON public.day_tasks((timeline->>'task_date'));
CREATE INDEX IF NOT EXISTS idx_day_tasks_priority ON public.day_tasks((indicators->>'priority'));
CREATE INDEX IF NOT EXISTS idx_day_tasks_social_posted ON public.day_tasks((social_info->>'is_posted'));
CREATE INDEX IF NOT EXISTS idx_day_tasks_share ON public.day_tasks((share_info->>'is_share'));

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.day_tasks ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'day_tasks' AND policyname = 'day_tasks_select_own') THEN
        CREATE POLICY "day_tasks_select_own" ON public.day_tasks
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'day_tasks' AND policyname = 'day_tasks_insert_own') THEN
        CREATE POLICY "day_tasks_insert_own" ON public.day_tasks
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'day_tasks' AND policyname = 'day_tasks_update_own') THEN
        CREATE POLICY "day_tasks_update_own" ON public.day_tasks
            FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'day_tasks' AND policyname = 'day_tasks_delete_own') THEN
        CREATE POLICY "day_tasks_delete_own" ON public.day_tasks
            FOR DELETE USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'day_tasks' AND policyname = 'day_tasks_select_shared') THEN
        CREATE POLICY "day_tasks_select_shared" ON public.day_tasks
            FOR SELECT USING (
                share_info->>'is_share' = 'true'
                AND share_info->'posted'->>'with_id' = auth.uid()::text
            );
    END IF;
END $$;

-- ============================================================
-- TRIGGER: Updated at
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_day_tasks_updated_at') THEN
        CREATE TRIGGER update_day_tasks_updated_at
            BEFORE UPDATE ON public.day_tasks
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT ALL ON TABLE public.day_tasks TO authenticated;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.day_tasks table ready';
    RAISE NOTICE '   - 1 trigger: update_day_tasks_updated_at';
    RAISE NOTICE '   - 5 RLS policies';
    RAISE NOTICE '   - 9 indexes';
END $$;
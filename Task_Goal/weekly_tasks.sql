-- ============================================================
-- 📁 FILE 06: WEEKLY TASKS TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.weekly_tasks (
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
CREATE INDEX IF NOT EXISTS idx_weekly_tasks_user_id ON public.weekly_tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_weekly_tasks_category ON public.weekly_tasks(category_id);
CREATE INDEX IF NOT EXISTS idx_weekly_tasks_category_type ON public.weekly_tasks(category_type);
CREATE INDEX IF NOT EXISTS idx_weekly_tasks_stack ON public.weekly_tasks((metadata->>'task_stack'));
CREATE INDEX IF NOT EXISTS idx_weekly_tasks_priority ON public.weekly_tasks((indicators->>'priority'));
CREATE INDEX IF NOT EXISTS idx_weekly_tasks_status ON public.weekly_tasks((indicators->>'status'));
CREATE INDEX IF NOT EXISTS idx_weekly_tasks_social_posted ON public.weekly_tasks((social_info->>'is_posted'));
CREATE INDEX IF NOT EXISTS idx_weekly_tasks_share ON public.weekly_tasks((share_info->>'is_share'));

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.weekly_tasks ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'weekly_tasks' AND policyname = 'weekly_tasks_select_own') THEN
        CREATE POLICY "weekly_tasks_select_own" ON public.weekly_tasks
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'weekly_tasks' AND policyname = 'weekly_tasks_insert_own') THEN
        CREATE POLICY "weekly_tasks_insert_own" ON public.weekly_tasks
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'weekly_tasks' AND policyname = 'weekly_tasks_update_own') THEN
        CREATE POLICY "weekly_tasks_update_own" ON public.weekly_tasks
            FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'weekly_tasks' AND policyname = 'weekly_tasks_delete_own') THEN
        CREATE POLICY "weekly_tasks_delete_own" ON public.weekly_tasks
            FOR DELETE USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'weekly_tasks' AND policyname = 'weekly_tasks_select_shared') THEN
        CREATE POLICY "weekly_tasks_select_shared" ON public.weekly_tasks
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
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_weekly_tasks_updated_at') THEN
        CREATE TRIGGER update_weekly_tasks_updated_at
            BEFORE UPDATE ON public.weekly_tasks
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT ALL ON TABLE public.weekly_tasks TO authenticated;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.weekly_tasks table ready';
    RAISE NOTICE '   - 1 trigger: update_weekly_tasks_updated_at';
    RAISE NOTICE '   - 5 RLS policies';
    RAISE NOTICE '   - 8 indexes';
END $$;
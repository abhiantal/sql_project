-- ============================================================
-- 📁 FILE 07: LONG GOALS TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.long_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    category_type TEXT,
    sub_types TEXT,
    description JSONB NOT NULL,
    timeline JSONB NOT NULL,
    indicators JSONB,
    metrics JSONB,
    analysis JSONB,
    goal_log JSONB,
    social_info JSONB,
    share_info JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    search_vector tsvector GENERATED ALWAYS AS (
        to_tsvector('english',
            COALESCE(title, '') || ' ' ||
            COALESCE(description->>'need', '') || ' ' ||
            COALESCE(description->>'motivation', '') || ' ' ||
            COALESCE(description->>'outcome', '') || ' ' ||
            COALESCE(category_type, '') || ' ' ||
            COALESCE(sub_types, '')
        )
    ) STORED
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_long_goals_user_id ON public.long_goals(user_id);
CREATE INDEX IF NOT EXISTS idx_long_goals_category ON public.long_goals(category_id);
CREATE INDEX IF NOT EXISTS idx_long_goals_category_type ON public.long_goals(category_type);
CREATE INDEX IF NOT EXISTS idx_long_goals_sub_types ON public.long_goals(sub_types);
CREATE INDEX IF NOT EXISTS idx_long_goals_status ON public.long_goals((indicators->>'status'));
CREATE INDEX IF NOT EXISTS idx_long_goals_priority ON public.long_goals((metrics->>'priority'));
CREATE INDEX IF NOT EXISTS idx_long_goals_search ON public.long_goals USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS idx_long_goals_timeline ON public.long_goals((timeline->>'start_date'), (timeline->>'end_date'));
CREATE INDEX IF NOT EXISTS idx_long_goals_created_at ON public.long_goals(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_long_goals_social_posted ON public.long_goals((social_info->>'is_posted'));
CREATE INDEX IF NOT EXISTS idx_long_goals_share ON public.long_goals((share_info->>'is_share'));
CREATE INDEX IF NOT EXISTS idx_long_goals_goal_log ON public.long_goals USING GIN(goal_log);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.long_goals ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'long_goals' AND policyname = 'long_goals_select_own') THEN
        CREATE POLICY "long_goals_select_own" ON public.long_goals
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'long_goals' AND policyname = 'long_goals_insert_own') THEN
        CREATE POLICY "long_goals_insert_own" ON public.long_goals
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'long_goals' AND policyname = 'long_goals_update_own') THEN
        CREATE POLICY "long_goals_update_own" ON public.long_goals
            FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'long_goals' AND policyname = 'long_goals_delete_own') THEN
        CREATE POLICY "long_goals_delete_own" ON public.long_goals
            FOR DELETE USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'long_goals' AND policyname = 'long_goals_select_shared') THEN
        CREATE POLICY "long_goals_select_shared" ON public.long_goals
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
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_long_goals_updated_at') THEN
        CREATE TRIGGER update_long_goals_updated_at
            BEFORE UPDATE ON public.long_goals
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
GRANT ALL ON TABLE public.long_goals TO authenticated;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.long_goals table ready';
    RAISE NOTICE '   - 1 trigger: update_long_goals_updated_at';
    RAISE NOTICE '   - 5 RLS policies';
    RAISE NOTICE '   - 12 indexes';
END $$;
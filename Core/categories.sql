-- ============================================================
-- 📁 FILE 01: CATEGORIES TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- CORE UTILITIES
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = public;

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    category_for TEXT NOT NULL CHECK (category_for IN ('long_goal', 'bucket', 'day_task', 'weekly_task', 'community', 'group')),
    category_type TEXT NOT NULL,
    sub_types JSONB DEFAULT '{"items": []}'::jsonb,
    description TEXT,
    color TEXT DEFAULT '#6366f1',
    icon TEXT DEFAULT '📁',
    is_global BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    sort_order INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_categories_user_id ON public.categories(user_id);
CREATE INDEX IF NOT EXISTS idx_categories_global ON public.categories(is_global) WHERE is_global = TRUE;
CREATE INDEX IF NOT EXISTS idx_categories_type ON public.categories(category_for, category_type);
CREATE INDEX IF NOT EXISTS idx_categories_active ON public.categories(is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_categories_user_for ON public.categories(user_id, category_for);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'categories' AND policyname = 'categories_select_global_own') THEN
        CREATE POLICY "categories_select_global_own" ON public.categories
            FOR SELECT USING (is_global = TRUE OR auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'categories' AND policyname = 'categories_insert_own') THEN
        CREATE POLICY "categories_insert_own" ON public.categories
            FOR INSERT WITH CHECK (auth.uid() = user_id AND is_global = FALSE);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'categories' AND policyname = 'categories_update_own') THEN
        CREATE POLICY "categories_update_own" ON public.categories
            FOR UPDATE USING (auth.uid() = user_id AND is_global = FALSE)
            WITH CHECK (auth.uid() = user_id AND is_global = FALSE);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'categories' AND policyname = 'categories_delete_own') THEN
        CREATE POLICY "categories_delete_own" ON public.categories
            FOR DELETE USING (auth.uid() = user_id AND is_global = FALSE);
    END IF;
END $$;

-- ============================================================
-- FUNCTION: Get categories for type
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_categories_for_type(
    p_category_for TEXT,
    p_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    category_type TEXT,
    sub_types JSONB,
    description TEXT,
    color TEXT,
    icon TEXT,
    is_global BOOLEAN,
    is_user_owned BOOLEAN
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id,
        c.category_type,
        c.sub_types,
        c.description,
        c.color,
        c.icon,
        c.is_global,
        (c.user_id = p_user_id) as is_user_owned
    FROM public.categories c
    WHERE c.category_for = p_category_for
      AND c.is_active = TRUE
      AND (c.is_global = TRUE OR c.user_id = p_user_id)
    ORDER BY c.is_global DESC, c.sort_order ASC, c.category_type ASC;
END;
$$;

-- ============================================================
-- TRIGGER: Updated at
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_categories_updated_at') THEN
        CREATE TRIGGER update_categories_updated_at
            BEFORE UPDATE ON public.categories
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT ALL ON TABLE public.categories TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_categories_for_type(TEXT, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.categories table ready';
    RAISE NOTICE '   - 1 trigger: update_categories_updated_at';
    RAISE NOTICE '   - 1 function: get_categories_for_type()';
    RAISE NOTICE '   - 4 RLS policies';
    RAISE NOTICE '   - 5 indexes';
END $$;
-- ============================================================
-- 📁 FILE 02: REACTIONS TABLE
-- Multi-reaction system (LinkedIn style)
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    target_type TEXT NOT NULL CHECK (target_type IN ('post', 'comment')),
    target_id UUID NOT NULL,
    reaction_type TEXT NOT NULL CHECK (reaction_type IN (
        'like', 'love', 'celebrate', 'support', 'insightful', 'curious', 'haha', 'wow', 'sad', 'angry'
    )),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, target_type, target_id)
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_reactions_user ON public.reactions(user_id);
CREATE INDEX IF NOT EXISTS idx_reactions_target ON public.reactions(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_reactions_type ON public.reactions(reaction_type);
CREATE INDEX IF NOT EXISTS idx_reactions_post ON public.reactions(target_id) WHERE target_type = 'post';
CREATE INDEX IF NOT EXISTS idx_reactions_comment ON public.reactions(target_id) WHERE target_type = 'comment';
CREATE INDEX IF NOT EXISTS idx_reactions_user_target ON public.reactions(user_id, target_type, target_id);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'reactions' AND policyname = 'reactions_select_all') THEN
        CREATE POLICY "reactions_select_all" ON public.reactions
            FOR SELECT USING (true);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'reactions' AND policyname = 'reactions_insert_own') THEN
        CREATE POLICY "reactions_insert_own" ON public.reactions
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'reactions' AND policyname = 'reactions_update_own') THEN
        CREATE POLICY "reactions_update_own" ON public.reactions
            FOR UPDATE USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'reactions' AND policyname = 'reactions_delete_own') THEN
        CREATE POLICY "reactions_delete_own" ON public.reactions
            FOR DELETE USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================
-- FUNCTION: Toggle reaction (add/change/remove)
-- ============================================================
CREATE OR REPLACE FUNCTION public.toggle_reaction(
    p_user_id UUID,
    p_target_type TEXT,
    p_target_id UUID,
    p_reaction_type TEXT
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing RECORD;
    v_action TEXT;
    v_old_reaction TEXT;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Check existing reaction
    SELECT * INTO v_existing
    FROM public.reactions
    WHERE user_id = p_user_id
    AND target_type = p_target_type
    AND target_id = p_target_id;

    IF FOUND THEN
        IF v_existing.reaction_type = p_reaction_type THEN
            -- Same reaction - remove it
            DELETE FROM public.reactions WHERE id = v_existing.id;
            v_action := 'removed';
            v_old_reaction := v_existing.reaction_type;
        ELSE
            -- Different reaction - update it
            v_old_reaction := v_existing.reaction_type;
            UPDATE public.reactions
            SET reaction_type = p_reaction_type, updated_at = NOW()
            WHERE id = v_existing.id;
            v_action := 'changed';
        END IF;
    ELSE
        -- No existing - add new
        INSERT INTO public.reactions (user_id, target_type, target_id, reaction_type)
        VALUES (p_user_id, p_target_type, p_target_id, p_reaction_type);
        v_action := 'added';
        v_old_reaction := NULL;
    END IF;

    -- Update counts on target
    IF p_target_type = 'post' THEN
        PERFORM internal.update_post_reaction_counts(p_target_id);
    ELSIF p_target_type = 'comment' THEN
        PERFORM internal.update_comment_reaction_counts(p_target_id);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'action', v_action,
        'reaction_type', CASE WHEN v_action = 'removed' THEN NULL ELSE p_reaction_type END,
        'old_reaction', v_old_reaction
    );
END;
$$;

-- ============================================================
-- INTERNAL COUNTER FUNCTIONS (Relocated to internal schema)
-- ============================================================
CREATE OR REPLACE FUNCTION internal.update_post_reaction_counts(p_post_id UUID)
RETURNS VOID SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE v_counts JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total', COUNT(*),
        'like', COUNT(*) FILTER (WHERE reaction_type = 'like'),
        'love', COUNT(*) FILTER (WHERE reaction_type = 'love'),
        'celebrate', COUNT(*) FILTER (WHERE reaction_type = 'celebrate'),
        'support', COUNT(*) FILTER (WHERE reaction_type = 'support'),
        'insightful', COUNT(*) FILTER (WHERE reaction_type = 'insightful'),
        'curious', COUNT(*) FILTER (WHERE reaction_type = 'curious'),
        'haha', COUNT(*) FILTER (WHERE reaction_type = 'haha'),
        'wow', COUNT(*) FILTER (WHERE reaction_type = 'wow'),
        'sad', COUNT(*) FILTER (WHERE reaction_type = 'sad'),
        'angry', COUNT(*) FILTER (WHERE reaction_type = 'angry')
    ) INTO v_counts FROM public.reactions WHERE target_type = 'post' AND target_id = p_post_id;
    UPDATE public.posts SET reactions_count = v_counts, updated_at = NOW() WHERE id = p_post_id;
END; $$;

CREATE OR REPLACE FUNCTION internal.update_comment_reaction_counts(p_comment_id UUID)
RETURNS VOID SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE v_counts JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total', COUNT(*),
        'like', COUNT(*) FILTER (WHERE reaction_type = 'like'),
        'love', COUNT(*) FILTER (WHERE reaction_type = 'love'),
        'celebrate', COUNT(*) FILTER (WHERE reaction_type = 'celebrate'),
        'support', COUNT(*) FILTER (WHERE reaction_type = 'support'),
        'insightful', COUNT(*) FILTER (WHERE reaction_type = 'insightful'),
        'curious', COUNT(*) FILTER (WHERE reaction_type = 'curious')
    ) INTO v_counts FROM public.reactions WHERE target_type = 'comment' AND target_id = p_comment_id;
    UPDATE public.comments SET reactions_count = v_counts, updated_at = NOW() WHERE id = p_comment_id;
END; $$;

-- ============================================================
-- FUNCTION: Get reaction users
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_reaction_users(
    p_target_type TEXT,
    p_target_id UUID,
    p_reaction_type TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    user_id UUID,
    username TEXT,
    display_name TEXT,
    profile_url TEXT,
    reaction_type TEXT,
    reacted_at TIMESTAMPTZ
)
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.user_id,
        up.username,
        up.display_name,
        up.profile_url,
        r.reaction_type,
        r.created_at as reacted_at
    FROM public.reactions r
    JOIN public.user_profiles up ON up.user_id = r.user_id
    WHERE r.target_type = p_target_type
    AND r.target_id = p_target_id
    AND (p_reaction_type IS NULL OR r.reaction_type = p_reaction_type)
    ORDER BY r.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ============================================================
-- TRIGGER FUNCTION: Update counts on target
-- ============================================================
CREATE OR REPLACE FUNCTION internal.fn_on_reaction_change()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.target_type = 'post' THEN PERFORM internal.update_post_reaction_counts(NEW.target_id);
        ELSIF NEW.target_type = 'comment' THEN PERFORM internal.update_comment_reaction_counts(NEW.target_id); END IF;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.target_type = 'post' THEN PERFORM internal.update_post_reaction_counts(OLD.target_id);
        ELSIF OLD.target_type = 'comment' THEN PERFORM internal.update_comment_reaction_counts(OLD.target_id); END IF;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- ============================================================
-- CREATE TRIGGERS
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_on_reaction_change') THEN
        CREATE TRIGGER trg_on_reaction_change
            AFTER INSERT OR DELETE ON public.reactions
            FOR EACH ROW
            EXECUTE FUNCTION internal.fn_on_reaction_change();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_reactions_updated_at') THEN
        CREATE TRIGGER update_reactions_updated_at
            BEFORE UPDATE ON public.reactions
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT EXECUTE ON FUNCTION public.toggle_reaction(UUID, TEXT, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_reaction_users(TEXT, UUID, TEXT, INTEGER, INTEGER) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.reactions table ready';
    RAISE NOTICE '   - 1 trigger: update_reactions_updated_at';
    RAISE NOTICE '   - 4 functions:';
    RAISE NOTICE '     • toggle_reaction()';
    RAISE NOTICE '     • update_post_reaction_counts()';
    RAISE NOTICE '     • update_comment_reaction_counts()';
    RAISE NOTICE '     • get_reaction_users()';
    RAISE NOTICE '   - 4 RLS policies';
    RAISE NOTICE '   - 6 indexes';
END $$;
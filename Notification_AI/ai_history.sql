-- ============================================================
-- 📁 FILE 13: AI HISTORY TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.ai_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    context_type TEXT NOT NULL,
    ai_usage_source TEXT NOT NULL,
    source_table TEXT,
    source_record_id TEXT,
    chat_id UUID,
    api_provider TEXT NOT NULL,
    model_name TEXT NOT NULL,
    prompt_tokens INTEGER DEFAULT 0,
    completion_tokens INTEGER DEFAULT 0,
    tokens_used INTEGER NOT NULL DEFAULT 0,
    token_quota INTEGER NOT NULL DEFAULT 10000,
    response_time_ms INTEGER,
    success BOOLEAN DEFAULT true,
    error_message TEXT,
    request_metadata JSONB DEFAULT '{}'::jsonb,
    response_metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_ai_history_user_id ON public.ai_history(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_history_created_at ON public.ai_history(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_history_user_created ON public.ai_history(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_history_context_type ON public.ai_history(context_type);
CREATE INDEX IF NOT EXISTS idx_ai_history_ai_usage_source ON public.ai_history(ai_usage_source);
CREATE INDEX IF NOT EXISTS idx_ai_history_source ON public.ai_history(source_table, source_record_id);
CREATE INDEX IF NOT EXISTS idx_ai_history_chat_id ON public.ai_history(chat_id) WHERE chat_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ai_history_provider ON public.ai_history(api_provider);
CREATE INDEX IF NOT EXISTS idx_ai_history_success ON public.ai_history(success) WHERE success = FALSE;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.ai_history ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'ai_history' AND policyname = 'ai_history_select_own') THEN
        CREATE POLICY "ai_history_select_own" ON public.ai_history
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'ai_history' AND policyname = 'ai_history_insert_own') THEN
        CREATE POLICY "ai_history_insert_own" ON public.ai_history
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'ai_history' AND policyname = 'ai_history_delete_old') THEN
        CREATE POLICY "ai_history_delete_old" ON public.ai_history
            FOR DELETE USING (auth.uid() = user_id AND created_at < NOW() - INTERVAL '30 days');
    END IF;
END $$;

-- ============================================================
-- FUNCTION 1: Log AI usage
-- ============================================================
CREATE OR REPLACE FUNCTION public.log_ai_usage(
    p_user_id UUID,
    p_context_type TEXT,
    p_ai_usage_source TEXT,
    p_api_provider TEXT,
    p_model_name TEXT,
    p_tokens_used INTEGER,
    p_prompt_tokens INTEGER DEFAULT 0,
    p_completion_tokens INTEGER DEFAULT 0,
    p_token_quota INTEGER DEFAULT 10000,
    p_response_time_ms INTEGER DEFAULT NULL,
    p_success BOOLEAN DEFAULT TRUE,
    p_error_message TEXT DEFAULT NULL,
    p_source_table TEXT DEFAULT NULL,
    p_source_record_id TEXT DEFAULT NULL,
    p_chat_id UUID DEFAULT NULL,
    p_request_metadata JSONB DEFAULT '{}'::jsonb,
    p_response_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    INSERT INTO public.ai_history (
        user_id,
        context_type,
        ai_usage_source,
        api_provider,
        model_name,
        tokens_used,
        prompt_tokens,
        completion_tokens,
        token_quota,
        response_time_ms,
        success,
        error_message,
        source_table,
        source_record_id,
        chat_id,
        request_metadata,
        response_metadata
    )
    VALUES (
        p_user_id,
        p_context_type,
        p_ai_usage_source,
        p_api_provider,
        p_model_name,
        p_tokens_used,
        p_prompt_tokens,
        p_completion_tokens,
        p_token_quota,
        p_response_time_ms,
        p_success,
        p_error_message,
        p_source_table,
        p_source_record_id,
        p_chat_id,
        p_request_metadata,
        p_response_metadata
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- ============================================================
-- FUNCTION 2: Get AI usage stats
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_ai_usage_stats(
    p_user_id UUID,
    p_days INTEGER DEFAULT 30
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_result JSONB;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT jsonb_build_object(
        'total_requests', COUNT(*),
        'total_tokens', COALESCE(SUM(tokens_used), 0),
        'successful_requests', COUNT(*) FILTER (WHERE success = TRUE),
        'failed_requests', COUNT(*) FILTER (WHERE success = FALSE),
        'avg_response_time_ms', COALESCE(ROUND(AVG(response_time_ms)::numeric, 2), 0),
        'by_context_type', (
            SELECT COALESCE(jsonb_object_agg(context_type, cnt), '{}'::jsonb)
            FROM (
                SELECT context_type, COUNT(*) as cnt
                FROM public.ai_history
                WHERE user_id = p_user_id
                  AND created_at > NOW() - (p_days || ' days')::interval
                GROUP BY context_type
            ) t
        ),
        'by_provider', (
            SELECT COALESCE(jsonb_object_agg(api_provider, tokens), '{}'::jsonb)
            FROM (
                SELECT api_provider, SUM(tokens_used) as tokens
                FROM public.ai_history
                WHERE user_id = p_user_id
                  AND created_at > NOW() - (p_days || ' days')::interval
                GROUP BY api_provider
            ) t
        ),
        'period_days', p_days
    ) INTO v_result
    FROM public.ai_history
    WHERE user_id = p_user_id
      AND created_at > NOW() - (p_days || ' days')::interval;

    RETURN COALESCE(v_result, jsonb_build_object(
        'total_requests', 0,
        'total_tokens', 0,
        'successful_requests', 0,
        'failed_requests', 0,
        'avg_response_time_ms', 0,
        'by_context_type', '{}'::jsonb,
        'by_provider', '{}'::jsonb,
        'period_days', p_days
    ));
END;
$$;

-- ============================================================
-- TRIGGER: Updated at
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_ai_history_updated_at') THEN
        CREATE TRIGGER update_ai_history_updated_at
            BEFORE UPDATE ON public.ai_history
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT ALL ON TABLE public.ai_history TO authenticated;
GRANT EXECUTE ON FUNCTION public.log_ai_usage(UUID, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER, INTEGER, INTEGER, INTEGER, BOOLEAN, TEXT, TEXT, TEXT, UUID, JSONB, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_ai_usage_stats(UUID, INTEGER) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.ai_history table ready';
    RAISE NOTICE '   - 1 trigger: update_ai_history_updated_at';
    RAISE NOTICE '   - 2 functions:';
    RAISE NOTICE '     • log_ai_usage()';
    RAISE NOTICE '     • get_ai_usage_stats()';
    RAISE NOTICE '   - 3 RLS policies';
    RAISE NOTICE '   - 9 indexes';
END $$;
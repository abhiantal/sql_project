-- ============================================================
-- 📁 FILE 12: FCM TOKENS TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.fcm_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    device_info JSONB DEFAULT '{}'::jsonb,
    app_version TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, token)
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user_id ON public.fcm_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_platform ON public.fcm_tokens(platform);
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_updated ON public.fcm_tokens(updated_at);
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_active ON public.fcm_tokens(user_id) WHERE is_active = TRUE;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'fcm_tokens' AND policyname = 'fcm_tokens_all_own') THEN
        CREATE POLICY "fcm_tokens_all_own" ON public.fcm_tokens
            FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================
-- FUNCTION 1: Upsert FCM token
-- ============================================================
CREATE OR REPLACE FUNCTION public.upsert_fcm_token(
    p_user_id UUID,
    p_token TEXT,
    p_platform TEXT,
    p_device_info JSONB DEFAULT NULL,
    p_app_version TEXT DEFAULT NULL
)
RETURNS void
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    INSERT INTO public.fcm_tokens (
        user_id,
        token,
        platform,
        device_info,
        app_version
    )
    VALUES (
        p_user_id,
        p_token,
        p_platform,
        COALESCE(p_device_info, '{}'::jsonb),
        p_app_version
    )
    ON CONFLICT (user_id, token)
    DO UPDATE SET
        platform = EXCLUDED.platform,
        device_info = EXCLUDED.device_info,
        app_version = EXCLUDED.app_version,
        is_active = TRUE,
        updated_at = NOW();
END;
$$;

-- ============================================================
-- FUNCTION 2: Remove FCM token
-- ============================================================
CREATE OR REPLACE FUNCTION public.remove_fcm_token(
    p_user_id UUID,
    p_token TEXT DEFAULT NULL
)
RETURNS void
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    IF p_token IS NULL THEN
        -- Deactivate all tokens for user
        UPDATE public.fcm_tokens
        SET is_active = FALSE, updated_at = NOW()
        WHERE user_id = p_user_id;
    ELSE
        -- Deactivate specific token
        UPDATE public.fcm_tokens
        SET is_active = FALSE, updated_at = NOW()
        WHERE user_id = p_user_id AND token = p_token;
    END IF;
END;
$$;

-- ============================================================
-- FUNCTION 3: Get user FCM tokens
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_user_fcm_tokens(p_user_id UUID)
RETURNS TABLE (token TEXT, platform TEXT)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    RETURN QUERY
    SELECT ft.token, ft.platform
    FROM public.fcm_tokens ft
    WHERE ft.user_id = p_user_id AND ft.is_active = TRUE;
END;
$$;

-- ============================================================
-- TRIGGER: Updated at
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_fcm_tokens_updated_at') THEN
        CREATE TRIGGER trg_update_fcm_tokens_updated_at
            BEFORE UPDATE ON public.fcm_tokens
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT ALL ON TABLE public.fcm_tokens TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_fcm_token(UUID, TEXT, TEXT, JSONB, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.remove_fcm_token(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_user_fcm_tokens(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.fcm_tokens table ready';
    RAISE NOTICE '   - 1 trigger: trg_update_fcm_tokens_updated_at';
    RAISE NOTICE '   - 3 functions:';
    RAISE NOTICE '     • upsert_fcm_token()';
    RAISE NOTICE '     • remove_fcm_token()';
    RAISE NOTICE '     • get_user_fcm_tokens()';
    RAISE NOTICE '   - 1 RLS policy';
    RAISE NOTICE '   - 4 indexes';
END $$;
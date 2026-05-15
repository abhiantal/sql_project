-- ============================================================
-- 📁 FILE 02: USER PROFILES TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- SCHEMAS
-- ============================================================
CREATE SCHEMA IF NOT EXISTS internal;
REVOKE ALL ON SCHEMA internal FROM PUBLIC;
GRANT USAGE ON SCHEMA internal TO authenticated, anon, service_role;

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    username TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    profile_url TEXT,
    address TEXT,
    organization JSONB DEFAULT '{}',
    influencer JSONB DEFAULT '{}',
    user_info JSONB DEFAULT '{}',
    is_profile_public BOOLEAN DEFAULT TRUE,
    subscription_tier TEXT DEFAULT 'free',
    onboarding_completed BOOLEAN DEFAULT FALSE,
    open_to_chat BOOLEAN DEFAULT TRUE,
    social_stats JSONB DEFAULT '{"followers_count":0,"following_count":0,"posts_count":0}'::jsonb,
    created_community_id UUID,
    promoted_community_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_user_profiles_user_id ON public.user_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_profiles_email ON public.user_profiles(email);
CREATE INDEX IF NOT EXISTS idx_user_profiles_username ON public.user_profiles(username);
CREATE INDEX IF NOT EXISTS idx_user_profiles_public ON public.user_profiles(is_profile_public) WHERE is_profile_public = TRUE;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_profiles' AND policyname = 'user_profiles_select_own') THEN
        CREATE POLICY "user_profiles_select_own" ON public.user_profiles
            FOR SELECT TO authenticated
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_profiles' AND policyname = 'user_profiles_insert_own') THEN
        CREATE POLICY "user_profiles_insert_own" ON public.user_profiles
            FOR INSERT TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_profiles' AND policyname = 'user_profiles_update_own') THEN
        CREATE POLICY "user_profiles_update_own" ON public.user_profiles
            FOR UPDATE TO authenticated
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_profiles' AND policyname = 'user_profiles_delete_own') THEN
        CREATE POLICY "user_profiles_delete_own" ON public.user_profiles
            FOR DELETE TO authenticated
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_profiles' AND policyname = 'user_profiles_select_public') THEN
        CREATE POLICY "user_profiles_select_public" ON public.user_profiles
            FOR SELECT TO anon, authenticated
            USING (is_profile_public = TRUE);
    END IF;
END $$;

-- ============================================================
-- FUNCTION: Handle new user (auto-create profile on signup)
-- ============================================================
CREATE OR REPLACE FUNCTION internal.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    new_username TEXT;
    new_display_name TEXT;
BEGIN
    new_username := COALESCE(
        NEW.raw_user_meta_data->>'username',
        split_part(NEW.email, '@', 1)
    );

    new_username := regexp_replace(new_username, '[^a-zA-Z0-9_]', '', 'g');

    IF length(new_username) < 3 THEN
        new_username := 'user_' || substr(NEW.id::text, 1, 8);
    END IF;

    IF EXISTS (SELECT 1 FROM public.user_profiles WHERE username = new_username) THEN
        new_username := new_username || '_' || substr(md5(random()::text), 1, 4);
    END IF;

    new_display_name := COALESCE(
        NEW.raw_user_meta_data->>'full_name',
        NEW.raw_user_meta_data->>'display_name',
        new_username
    );

    INSERT INTO public.user_profiles (
        id,
        user_id,
        email,
        username,
        display_name,
        created_at,
        updated_at
    ) VALUES (
        NEW.id,
        NEW.id,
        NEW.email,
        new_username,
        new_display_name,
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        email = EXCLUDED.email,
        updated_at = NOW();

    RETURN NEW;

EXCEPTION
    WHEN unique_violation THEN
        BEGIN
            INSERT INTO public.user_profiles (
                id,
                user_id,
                email,
                username,
                display_name,
                created_at,
                updated_at
            ) VALUES (
                NEW.id,
                NEW.id,
                NEW.email,
                'user_' || substr(NEW.id::text, 1, 8) || '_' || substr(md5(random()::text), 1, 4),
                new_display_name,
                NOW(),
                NOW()
            )
            ON CONFLICT (user_id) DO NOTHING;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE WARNING 'Failed to create profile for user %: %', NEW.id, SQLERRM;
        END;
        RETURN NEW;

    WHEN OTHERS THEN
        RAISE WARNING 'Profile creation error for user %: %', NEW.id, SQLERRM;
        RETURN NEW;
END;
$$;

-- Media cleanup functions removed. 
-- See selective_storage_cleanup.sql for automated media management.

-- ============================================================
-- TRIGGERS
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_user_profiles_updated_at') THEN
        CREATE TRIGGER update_user_profiles_updated_at
            BEFORE UPDATE ON public.user_profiles
            FOR EACH ROW
            EXECUTE FUNCTION public.update_updated_at_column();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'on_auth_user_created' AND tgrelid = 'auth.users'::regclass) THEN
        CREATE TRIGGER on_auth_user_created
            AFTER INSERT ON auth.users
            FOR EACH ROW
            EXECUTE FUNCTION internal.handle_new_user();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT ALL ON TABLE public.user_profiles TO authenticated;
GRANT SELECT ON TABLE public.user_profiles TO anon;

-- [Administrative/Internal]
GRANT EXECUTE ON FUNCTION internal.handle_new_user() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;
-- No need to revoke from public/auth because schema usage is restricted

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.user_profiles table ready';
    RAISE NOTICE '   - 2 triggers:';
    RAISE NOTICE '     • update_user_profiles_updated_at';
    RAISE NOTICE '     • on_auth_user_created (on auth.users)';
    RAISE NOTICE '   - 1 function:';
    RAISE NOTICE '     • handle_new_user()';
    RAISE NOTICE '   - 5 RLS policies';
    RAISE NOTICE '   - 4 indexes';
END $$;
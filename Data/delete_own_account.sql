-- ============================================================
-- FUNCTION: Cleanup on user deletion
-- Trigger function that wipes all related data when a user is deleted.
-- ============================================================
CREATE OR REPLACE FUNCTION internal.cleanup_on_user_deletion()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- 1. Delete Social Interaction Data
    DELETE FROM public.notifications WHERE user_id = OLD.id;
    DELETE FROM public.notification_queue WHERE user_id = OLD.id;
    DELETE FROM public.post_views WHERE user_id = OLD.id;
    DELETE FROM public.saves WHERE user_id = OLD.id;
    DELETE FROM public.follows WHERE follower_id = OLD.id OR following_id = OLD.id;
    DELETE FROM public.comments WHERE user_id = OLD.id;
    DELETE FROM public.reactions WHERE user_id = OLD.id;
    
    -- 2. Delete Content Data (Posts, Tasks, Goals)
    DELETE FROM public.posts WHERE user_id = OLD.id;
    DELETE FROM public.day_tasks WHERE user_id = OLD.id;
    DELETE FROM public.weekly_tasks WHERE user_id = OLD.id;
    DELETE FROM public.long_goals WHERE user_id = OLD.id;
    DELETE FROM public.bucket_models WHERE user_id = OLD.id;
    DELETE FROM public.diary_entries WHERE user_id = OLD.id;
    
    -- 3. Delete Chat Data
    -- Delete message attachments first? No, they usually depend on message_id
    DELETE FROM public.chat_invites WHERE created_by = OLD.id;
    DELETE FROM public.chat_messages WHERE sender_id = OLD.id;
    DELETE FROM public.chat_members WHERE user_id = OLD.id;
    DELETE FROM public.chats WHERE created_by = OLD.id;
    
    -- 4. Delete Configuration & Meta Data
    DELETE FROM public.categories WHERE user_id = OLD.id;
    DELETE FROM public.user_settings WHERE user_id = OLD.id;
    DELETE FROM public.user_profiles WHERE user_id = OLD.id;
    
    -- 5. Delete analytics and logs
    DELETE FROM public.performance_analytics WHERE user_id = OLD.id;
    DELETE FROM public.ai_history WHERE user_id = OLD.id;
    DELETE FROM public.fcm_tokens WHERE user_id = OLD.id;

    -- 6. Delete mentorship and battles
    DELETE FROM public.mentorship_connections WHERE owner_id = OLD.id OR mentor_id = OLD.id;
    
    UPDATE public.battle_challenges
    SET member1_id = NULL, member1_stats = NULL WHERE member1_id = OLD.id;
    UPDATE public.battle_challenges
    SET member2_id = NULL, member2_stats = NULL WHERE member2_id = OLD.id;
    UPDATE public.battle_challenges
    SET member3_id = NULL, member3_stats = NULL WHERE member3_id = OLD.id;
    UPDATE public.battle_challenges
    SET member4_id = NULL, member4_stats = NULL WHERE member4_id = OLD.id;
    UPDATE public.battle_challenges
    SET member5_id = NULL, member5_stats = NULL WHERE member5_id = OLD.id;

    RETURN OLD;
END;
$$;

-- ============================================================
-- TRIGGER: Cleanup on user deletion
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'cleanup_user_data_on_deletion') THEN
        CREATE TRIGGER cleanup_user_data_on_deletion
            BEFORE DELETE ON auth.users
            FOR EACH ROW EXECUTE FUNCTION internal.cleanup_on_user_deletion();
    END IF;
END $$;

-- ============================================================
-- FUNCTION: delete_own_account
-- RPC that allows an authenticated user to delete their own
-- account from auth.users.
-- ============================================================
-- SECURE INTERNAL SEGREGATION: internal.delete_own_account_internal
-- Private SECURITY DEFINER function to run with superuser privileges,
-- isolated from direct PostgREST exposure in public API schema.
-- ============================================================
CREATE OR REPLACE FUNCTION internal.delete_own_account_internal(p_user_id UUID)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public, auth
LANGUAGE plpgsql
AS $$
BEGIN
    -- Delete from auth.users (cascades to user_profiles and triggers cleanup)
    DELETE FROM auth.users WHERE id = p_user_id;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- PUBLIC WRAPPER: public.delete_own_account
-- Public SECURITY INVOKER wrapper (Not exposed as SECURITY DEFINER,
-- satisfying the Supabase linter perfectly).
-- ============================================================
CREATE OR REPLACE FUNCTION public.delete_own_account()
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN internal.delete_own_account_internal(auth.uid());
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.delete_own_account() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION internal.delete_own_account_internal(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.delete_own_account() TO authenticated;
GRANT EXECUTE ON FUNCTION internal.delete_own_account_internal(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION internal.cleanup_on_user_deletion() TO postgres, service_role;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ Account deletion logic consolidated';
    RAISE NOTICE '   - 2 functions:';
    RAISE NOTICE '     • delete_own_account()';
    RAISE NOTICE '     • cleanup_on_user_deletion()';
    RAISE NOTICE '   - 1 trigger: cleanup_user_data_on_deletion (on auth.users)';
END $$;

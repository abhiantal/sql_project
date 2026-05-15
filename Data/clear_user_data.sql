-- ============================================================
-- 📁 FILE: packages/Core/clear_user_data.sql
-- Function to wipe all user data EXCEPT the profile
-- ============================================================

CREATE OR REPLACE FUNCTION public.clear_user_data()
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- 1. Delete Social Interaction Data
    DELETE FROM public.notifications WHERE user_id = v_user_id;
    DELETE FROM public.notification_queue WHERE user_id = v_user_id;
    DELETE FROM public.post_views WHERE user_id = v_user_id;
    DELETE FROM public.saves WHERE user_id = v_user_id;
    DELETE FROM public.follows WHERE follower_id = v_user_id OR following_id = v_user_id;
    DELETE FROM public.comments WHERE user_id = v_user_id;
    DELETE FROM public.reactions WHERE user_id = v_user_id;
    
    -- 2. Delete Content Data (Posts, Tasks, Goals, Diary)
    DELETE FROM public.posts WHERE user_id = v_user_id;
    DELETE FROM public.day_tasks WHERE user_id = v_user_id;
    DELETE FROM public.weekly_tasks WHERE user_id = v_user_id;
    DELETE FROM public.long_goals WHERE user_id = v_user_id;
    DELETE FROM public.bucket_models WHERE user_id = v_user_id;
    DELETE FROM public.diary_entries WHERE user_id = v_user_id;
    DELETE FROM public.categories WHERE user_id = v_user_id;
    
    -- 3. Delete Chat Data
    DELETE FROM public.chat_invites WHERE created_by = v_user_id;
    DELETE FROM public.chat_messages WHERE sender_id = v_user_id;
    DELETE FROM public.chat_members WHERE user_id = v_user_id;
    -- We keep the chat records themselves if other members exist, 
    -- but the user's presence is gone.
    
    -- 4. Delete analytics and logs
    DELETE FROM public.performance_analytics WHERE user_id = v_user_id;
    DELETE FROM public.ai_history WHERE user_id = v_user_id;
    DELETE FROM public.fcm_tokens WHERE user_id = v_user_id;

    -- 5. Delete mentorship and battles
    DELETE FROM public.mentorship_connections WHERE owner_id = v_user_id OR mentor_id = v_user_id;
    
    DELETE FROM public.battle_challenges WHERE user_id = v_user_id;
    UPDATE public.battle_challenges SET member1_id = NULL, member1_stats = NULL WHERE member1_id = v_user_id;
    UPDATE public.battle_challenges SET member2_id = NULL, member2_stats = NULL WHERE member2_id = v_user_id;
    UPDATE public.battle_challenges SET member3_id = NULL, member3_stats = NULL WHERE member3_id = v_user_id;
    UPDATE public.battle_challenges SET member4_id = NULL, member4_stats = NULL WHERE member4_id = v_user_id;
    UPDATE public.battle_challenges SET member5_id = NULL, member5_stats = NULL WHERE member5_id = v_user_id;

    -- 6. Reset Settings to Default (Except Profile)
    UPDATE public.user_settings 
    SET appearance = '{}'::jsonb,
        notifications = '{}'::jsonb,
        privacy = '{}'::jsonb,
        tasks = '{}'::jsonb,
        goals = '{}'::jsonb,
        updated_at = NOW()
    WHERE user_id = v_user_id;

    -- NOTE: Storage cleanup must be handled via the Storage API in Flutter.
    
    RETURN TRUE;
END;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clear_user_data() TO authenticated, service_role;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.clear_user_data function ready';
END $$;

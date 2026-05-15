-- ============================================================
-- 📢 POWERSYNC PUBLICATION — UPDATED FOR NEW CHAT SCHEMA
-- ============================================================
-- Removed: chat_message_media, chat_message_reactions,
--          chat_message_read_receipts, chat_pinned_messages,
--          chat_drafts, chat_typing_indicators,
--          activity_feed_logs, progress_sharing
-- Added:   chat_message_attachments
-- Fixed:   likes → reactions, views → post_views
-- ============================================================

DROP PUBLICATION IF EXISTS powersync;

CREATE PUBLICATION powersync FOR TABLE
    -- Core user tables
    public.user_profiles,
    public.user_settings,
    public.categories,

    -- Task & goal tables
    public.bucket_models,
    public.day_tasks,
    public.weekly_tasks,
    public.long_goals,
    public.diary_entries,

    -- Social tables
    public.posts,
    public.reactions,
    public.comments,
    public.follows,
    public.saves,
    public.post_views,
    
    -- Notification tables
    public.notifications,
   
    -- Chat tables (5 core tables)
    public.chats,
    public.chat_members,
    public.chat_messages,
    public.chat_message_attachments,
    public.chat_invites,

    -- Competition, Mentorship and Analytics
    public.performance_analytics,
    public.battle_challenges,
    public.mentorship_connections;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
DECLARE
    v_count INTEGER;
    v_tables TEXT[];
BEGIN
    SELECT array_agg(tablename ORDER BY tablename)
    INTO v_tables
    FROM pg_publication_tables
    WHERE pubname = 'powersync';

    v_count := array_length(v_tables, 1);

    RAISE NOTICE '--- PowerSync Publication Verified ---';
    RAISE NOTICE '    Total tables included: %', v_count;
    RAISE NOTICE '    Tables: %', v_tables;
    RAISE NOTICE '--- End Verification ---';
END $$;
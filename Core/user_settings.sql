-- ============================================================
-- 📁 FILE 03: USER SETTINGS TABLE
-- Complete table with all functions and triggers
-- ============================================================

-- ============================================================
-- TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.user_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,

    appearance JSONB DEFAULT '{
        "theme": "system",
        "color_scheme": "default",
        "accent_color": "#6366f1",
        "font_size": "medium",
        "font_family": "system",
        "reduce_motion": false,
        "high_contrast": false,
        "compact_mode": false
    }'::jsonb,

    notifications JSONB DEFAULT '{
        "enabled": true,
        "sound": true,
        "vibration": true,
        "badge_count": true,
        "preview_content": true,
        "quiet_hours": {
            "enabled": false,
            "start": "22:00",
            "end": "07:00",
            "days": ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        },
        "channels": {
            "tasks": {"enabled": true, "reminders": true, "due_soon": true, "overdue": true, "completed": false},
            "goals": {"enabled": true, "milestones": true, "progress_updates": true, "weekly_summary": true},
            "social": {"enabled": true, "likes": true, "comments": true, "follows": true, "mentions": true, "shares": true},
            "chat": {"enabled": true, "messages": true, "group_messages": true, "mentions": true, "reactions": false},
            "diary": {"enabled": true, "daily_reminder": true, "reminder_time": "21:00"},
            "ai": {"enabled": true, "suggestions": true, "insights": true},
            "system": {"enabled": true, "updates": true, "security": true, "promotions": false}
        }
    }'::jsonb,

    privacy JSONB DEFAULT '{
        "profile_visibility": "public",
        "show_online_status": true,
        "show_last_seen": true,
        "show_activity_status": true,
        "show_read_receipts": true,
        "show_typing_indicator": true,
        "allow_messages_from": "everyone",
        "allow_follows_from": "everyone",
        "allow_comments_from": "everyone",
        "show_in_search": true,
        "show_in_suggestions": true,
        "allow_tagging": true,
        "allow_mentions": true,
        "hide_from_users": [],
        "blocked_users": [],
        "restricted_users": [],
        "data_sharing": {"analytics": true, "personalization": true, "third_party": false}
    }'::jsonb,

    tasks JSONB DEFAULT '{
        "default_view": "list",
        "show_completed": true,
        "auto_archive_completed": false,
        "archive_after_days": 7,
        "default_priority": "medium",
        "default_reminder": 30,
        "week_starts_on": "monday",
        "working_days": ["monday", "tuesday", "wednesday", "thursday", "friday"],
        "working_hours": {"start": "09:00", "end": "17:00"},
        "show_subtasks": true,
        "show_time_estimates": true,
        "auto_schedule": false,
        "rollover_incomplete": true,
        "daily_task_limit": null,
        "default_category": null,
        "quick_add_defaults": {"priority": "medium", "add_to_today": true}
    }'::jsonb,

    goals JSONB DEFAULT '{
        "default_view": "grid",
        "show_archived": false,
        "progress_calculation": "automatic",
        "milestone_notifications": true,
        "weekly_review_day": "sunday",
        "weekly_review_time": "10:00",
        "show_streak": true,
        "goal_templates": true,
        "ai_suggestions": true
    }'::jsonb,

    bucket_list JSONB DEFAULT '{
        "default_view": "grid",
        "show_completed": true,
        "show_cost_estimates": true,
        "default_visibility": "private",
        "inspiration_feed": true,
        "location_suggestions": true
    }'::jsonb,

    diary JSONB DEFAULT '{
        "daily_prompt": true,
        "prompt_time": "21:00",
        "default_mood_tracking": true,
        "show_word_count": true,
        "auto_save": true,
        "auto_save_interval": 30,
        "show_linked_items": true,
        "default_visibility": "private",
        "enable_rich_text": true,
        "show_weather": true,
        "show_location": false,
        "templates": [],
        "favorite_prompts": []
    }'::jsonb,

    chat JSONB DEFAULT '{
        "enter_to_send": true,
        "media_auto_download": "wifi",
        "save_to_gallery": false,
        "link_preview": true,
        "emoji_suggestions": true,
        "sticker_suggestions": true,
        "chat_backup": {"enabled": false, "frequency": "weekly", "include_media": false},
        "default_disappearing": null,
        "bubble_style": "default",
        "font_size": "medium",
        "chat_wallpaper": null,
        "swipe_actions": {"left": "reply", "right": "archive"}
    }'::jsonb,

    social JSONB DEFAULT '{
        "default_post_visibility": "public",
        "auto_share_achievements": false,
        "show_activity_on_profile": true,
        "feed_preferences": {"show_from": "all", "content_types": ["posts", "achievements", "goals", "buckets"], "sort_by": "recent"},
        "auto_play_videos": "wifi",
        "reduce_data_usage": false,
        "hide_seen_posts": false,
        "muted_words": [],
        "muted_accounts": []
    }'::jsonb,

    ai JSONB DEFAULT '{
        "enabled": true,
        "auto_suggestions": true,
        "suggestion_frequency": "moderate",
        "preferred_model": "default",
        "response_style": "balanced",
        "use_for": {"task_suggestions": true, "goal_planning": true, "diary_prompts": true, "productivity_insights": true, "writing_assistance": true},
        "data_usage": {"learn_from_history": true, "personalized_suggestions": true},
        "daily_token_limit": null,
        "show_usage_stats": true
    }'::jsonb,

    competition JSONB DEFAULT '{
        "allow_challenges": true,
        "auto_accept_from_friends": false,
        "show_on_leaderboard": true,
        "share_stats": true,
        "notifications": {"challenge_received": true, "challenge_updates": true, "leaderboard_changes": true}
    }'::jsonb,

    security JSONB DEFAULT '{
        "biometric_lock": false,
        "app_lock_enabled": false,
        "app_lock_timeout": 0,
        "require_auth_for": {"diary": false, "chat": false, "settings": false, "export": true},
        "two_factor_enabled": false,
        "trusted_devices": [],
        "login_alerts": true,
        "session_timeout": null,
        "auto_logout": false
    }'::jsonb,

    data_storage JSONB DEFAULT '{
        "auto_sync": true,
        "sync_on_wifi_only": false,
        "offline_mode": true,
        "cache_size_limit": 500,
        "auto_clear_cache": true,
        "clear_cache_after_days": 30,
        "backup": {"enabled": false, "frequency": "weekly", "include_media": true, "cloud_provider": null},
        "export_format": "json"
    }'::jsonb,

    localization JSONB DEFAULT '{
        "language": "en",
        "region": null,
        "timezone": "auto",
        "date_format": "auto",
        "time_format": "12h",
        "first_day_of_week": "auto",
        "currency": "USD",
        "measurement_unit": "metric"
    }'::jsonb,

    accessibility JSONB DEFAULT '{
        "screen_reader_optimized": false,
        "reduce_motion": false,
        "increase_contrast": false,
        "larger_text": false,
        "bold_text": false,
        "reduce_transparency": false,
        "haptic_feedback": true,
        "audio_descriptions": false,
        "closed_captions": true,
        "mono_audio": false,
        "shake_to_undo": true
    }'::jsonb,

    experimental JSONB DEFAULT '{
        "beta_features": false,
        "early_access": false,
        "developer_mode": false,
        "debug_logging": false,
        "features": {}
    }'::jsonb,

    widgets JSONB DEFAULT '{
        "home_widgets": [
            {"type": "today_tasks", "size": "medium", "position": 0},
            {"type": "active_goals", "size": "small", "position": 1},
            {"type": "streak", "size": "small", "position": 2}
        ],
        "quick_actions": ["add_task", "add_diary", "start_timer", "voice_note"],
        "dashboard_layout": "default"
    }'::jsonb,

    analytics JSONB DEFAULT '{
        "weekly_report": true,
        "weekly_report_day": "sunday",
        "monthly_insights": true,
        "productivity_tracking": true,
        "mood_analytics": true,
        "goal_analytics": true,
        "share_anonymous_data": false
    }'::jsonb,

    mentoring JSONB DEFAULT '{
        "mentoring_enabled": true,
        "is_public": true,
        "allow_mentoring_requests": true,
        "default_permissions": {
            "show_points": true,
            "show_streak": true,
            "show_rank": true,
            "show_tasks": false,
            "show_task_details": false,
            "show_goals": false,
            "show_goal_details": false,
            "show_mood": false,
            "show_diary": false,
            "show_rewards": true,
            "show_progress": true
        }
    }'::jsonb,

    integrations JSONB DEFAULT '{
        "calendar": {"enabled": false, "provider": null, "sync_tasks": false, "sync_goals": false, "sync_events": false},
        "health": {"enabled": false, "provider": null, "sync_activities": false, "sync_sleep": false},
        "cloud_storage": {"enabled": false, "provider": null, "auto_backup": false},
        "social_accounts": {},
        "webhooks": []
    }'::jsonb,

    settings_version INTEGER DEFAULT 1,
    last_synced_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_user_settings_user_id ON public.user_settings(user_id);
CREATE INDEX IF NOT EXISTS idx_user_settings_updated ON public.user_settings(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_settings_notifications_enabled ON public.user_settings(user_id) WHERE (notifications->>'enabled')::boolean = true;
CREATE INDEX IF NOT EXISTS idx_user_settings_beta_users ON public.user_settings(user_id) WHERE (experimental->>'beta_features')::boolean = true;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_settings' AND policyname = 'user_settings_select_own') THEN
        CREATE POLICY "user_settings_select_own" ON public.user_settings
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_settings' AND policyname = 'user_settings_insert_own') THEN
        CREATE POLICY "user_settings_insert_own" ON public.user_settings
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_settings' AND policyname = 'user_settings_update_own') THEN
        CREATE POLICY "user_settings_update_own" ON public.user_settings
            FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'user_settings' AND policyname = 'user_settings_delete_own') THEN
        CREATE POLICY "user_settings_delete_own" ON public.user_settings
            FOR DELETE USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================
-- FUNCTION: Initialize user settings
-- ============================================================
CREATE OR REPLACE FUNCTION public.initialize_user_settings()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.user_settings (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Log the error but allow the user to be created in auth.users
    -- The profile/settings can be fixed or auto-created on first login
    RAISE WARNING 'Failed to initialize settings for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

-- ============================================================
-- FUNCTION: Get user setting
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_user_setting(
    p_user_id UUID,
    p_category TEXT
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_settings JSONB;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- [SECURITY] Whitelist validation
    IF p_category NOT IN (
        'appearance', 'notifications', 'privacy', 'tasks', 'goals',
        'bucket_list', 'diary', 'chat', 'social', 'ai', 'competition',
        'security', 'data_storage', 'localization', 'accessibility',
        'experimental', 'widgets', 'analytics', 'integrations'
    ) THEN
        RAISE EXCEPTION 'Invalid settings category: %', p_category;
    END IF;

    EXECUTE format('SELECT %I FROM public.user_settings WHERE user_id = $1', p_category)
    INTO v_settings
    USING p_user_id;

    RETURN v_settings;
END;
$$;

-- ============================================================
-- FUNCTION: Update user setting
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_user_setting(
    p_user_id UUID,
    p_category TEXT,
    p_settings JSONB
)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_updated JSONB;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    IF p_category NOT IN (
        'appearance', 'notifications', 'privacy', 'tasks', 'goals',
        'bucket_list', 'diary', 'chat', 'social', 'ai', 'competition',
        'security', 'data_storage', 'localization', 'accessibility',
        'experimental', 'widgets', 'analytics', 'integrations'
    ) THEN
        RAISE EXCEPTION 'Invalid settings category: %', p_category;
    END IF;

    EXECUTE format(
        'UPDATE public.user_settings
         SET %I = %I || $2, updated_at = NOW()
         WHERE user_id = $1
         RETURNING %I',
        p_category, p_category, p_category
    )
    INTO v_updated
    USING p_user_id, p_settings;

    RETURN v_updated;
END;
$$;

-- ============================================================
-- FUNCTION: Reset user settings
-- ============================================================
CREATE OR REPLACE FUNCTION public.reset_user_settings(
    p_user_id UUID,
    p_category TEXT DEFAULT NULL
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    IF p_category IS NULL THEN
        DELETE FROM public.user_settings WHERE user_id = p_user_id;
        INSERT INTO public.user_settings (user_id) VALUES (p_user_id);
    ELSE
        EXECUTE format(
            'UPDATE public.user_settings SET %I = (
                SELECT %I FROM public.user_settings WHERE user_id IS NULL LIMIT 1
            ) WHERE user_id = $1',
            p_category, p_category
        )
        USING p_user_id;
    END IF;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION: Should send notification
-- ============================================================
CREATE OR REPLACE FUNCTION public.should_send_notification(
    p_user_id UUID,
    p_channel TEXT,
    p_type TEXT DEFAULT NULL
)
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_settings JSONB;
    v_now TIME;
    v_quiet_start TIME;
    v_quiet_end TIME;
    v_current_day TEXT;
BEGIN
    SELECT notifications INTO v_settings
    FROM public.user_settings
    WHERE user_id = p_user_id;

    IF NOT (v_settings->>'enabled')::boolean THEN
        RETURN FALSE;
    END IF;

    IF (v_settings->'quiet_hours'->>'enabled')::boolean THEN
        v_now := CURRENT_TIME;
        v_quiet_start := (v_settings->'quiet_hours'->>'start')::time;
        v_quiet_end := (v_settings->'quiet_hours'->>'end')::time;
        v_current_day := LOWER(to_char(CURRENT_DATE, 'day'));

        IF v_settings->'quiet_hours'->'days' ? trim(v_current_day) THEN
            IF v_quiet_start > v_quiet_end THEN
                IF v_now >= v_quiet_start OR v_now <= v_quiet_end THEN
                    RETURN FALSE;
                END IF;
            ELSE
                IF v_now >= v_quiet_start AND v_now <= v_quiet_end THEN
                    RETURN FALSE;
                END IF;
            END IF;
        END IF;
    END IF;

    IF NOT (v_settings->'channels'->p_channel->>'enabled')::boolean THEN
        RETURN FALSE;
    END IF;

    IF p_type IS NOT NULL THEN
        IF v_settings->'channels'->p_channel ? p_type THEN
            RETURN (v_settings->'channels'->p_channel->>p_type)::boolean;
        END IF;
    END IF;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- FUNCTION: Export user settings
-- ============================================================
CREATE OR REPLACE FUNCTION public.export_user_settings(p_user_id UUID)
RETURNS JSONB
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_settings RECORD;
BEGIN
    SELECT * INTO v_settings
    FROM public.user_settings
    WHERE user_id = p_user_id;

    RETURN jsonb_build_object(
        'appearance', v_settings.appearance,
        'notifications', v_settings.notifications,
        'privacy', v_settings.privacy,
        'tasks', v_settings.tasks,
        'goals', v_settings.goals,
        'bucket_list', v_settings.bucket_list,
        'diary', v_settings.diary,
        'chat', v_settings.chat,
        'social', v_settings.social,
        'ai', v_settings.ai,
        'competition', v_settings.competition,
        'security', v_settings.security,
        'data_storage', v_settings.data_storage,
        'localization', v_settings.localization,
        'accessibility', v_settings.accessibility,
        'widgets', v_settings.widgets,
        'analytics', v_settings.analytics,
        'integrations', v_settings.integrations,
        'exported_at', NOW()
    );
END;
$$;

-- ============================================================
-- FUNCTION: Import user settings
-- ============================================================
CREATE OR REPLACE FUNCTION public.import_user_settings(
    p_user_id UUID,
    p_settings JSONB
)
RETURNS BOOLEAN
SECURITY INVOKER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.user_settings
    SET
        appearance = COALESCE(p_settings->'appearance', appearance),
        notifications = COALESCE(p_settings->'notifications', notifications),
        privacy = COALESCE(p_settings->'privacy', privacy),
        tasks = COALESCE(p_settings->'tasks', tasks),
        goals = COALESCE(p_settings->'goals', goals),
        bucket_list = COALESCE(p_settings->'bucket_list', bucket_list),
        diary = COALESCE(p_settings->'diary', diary),
        chat = COALESCE(p_settings->'chat', chat),
        social = COALESCE(p_settings->'social', social),
        ai = COALESCE(p_settings->'ai', ai),
        competition = COALESCE(p_settings->'competition', competition),
        security = COALESCE(p_settings->'security', security),
        data_storage = COALESCE(p_settings->'data_storage', data_storage),
        localization = COALESCE(p_settings->'localization', localization),
        accessibility = COALESCE(p_settings->'accessibility', accessibility),
        widgets = COALESCE(p_settings->'widgets', widgets),
        analytics = COALESCE(p_settings->'analytics', analytics),
        integrations = COALESCE(p_settings->'integrations', integrations),
        updated_at = NOW()
    WHERE user_id = p_user_id;

    RETURN FOUND;
END;
$$;

-- ============================================================
-- TRIGGERS
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_user_settings_updated_at') THEN
        CREATE TRIGGER update_user_settings_updated_at
            BEFORE UPDATE ON public.user_settings
            FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'create_user_settings_on_signup' AND tgrelid = 'auth.users'::regclass) THEN
        CREATE TRIGGER create_user_settings_on_signup
            AFTER INSERT ON auth.users
            FOR EACH ROW EXECUTE FUNCTION public.initialize_user_settings();
    END IF;
END $$;

-- ============================================================
-- GRANTS
-- ============================================================
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT ALL ON TABLE public.user_settings TO authenticated;

-- [API Functions]
GRANT EXECUTE ON FUNCTION public.get_user_setting(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_user_setting(UUID, TEXT, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reset_user_settings(UUID, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.export_user_settings(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.import_user_settings(UUID, JSONB) TO authenticated, service_role;

-- [Administrative/Internal]
GRANT EXECUTE ON FUNCTION public.initialize_user_settings() TO postgres, service_role;
GRANT EXECUTE ON FUNCTION public.should_send_notification(UUID, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role, postgres;
REVOKE EXECUTE ON FUNCTION public.initialize_user_settings() FROM authenticated, anon;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.user_settings table ready';
    RAISE NOTICE '   - 2 triggers:';
    RAISE NOTICE '     • update_user_settings_updated_at';
    RAISE NOTICE '     • create_user_settings_on_signup (on auth.users)';
    RAISE NOTICE '   - 7 functions:';
    RAISE NOTICE '     • initialize_user_settings()';
    RAISE NOTICE '     • get_user_setting()';
    RAISE NOTICE '     • update_user_setting()';
    RAISE NOTICE '     • reset_user_settings()';
    RAISE NOTICE '     • should_send_notification()';
    RAISE NOTICE '     • export_user_settings()';
    RAISE NOTICE '     • import_user_settings()';
    RAISE NOTICE '   - 4 RLS policies';
    RAISE NOTICE '   - 4 indexes';
END $$;
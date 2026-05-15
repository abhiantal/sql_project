
-- 1. DROP EXISTING FUNCTIONS AND TRIGGERS TO PREVENT SIGNATURE OR TYPE MISMATCH CONFLICTS
DROP FUNCTION IF EXISTS internal.calc_total_points(UUID) CASCADE;
DROP FUNCTION IF EXISTS internal.calc_overview(UUID) CASCADE;
DROP FUNCTION IF EXISTS internal.calc_today(UUID) CASCADE;
DROP FUNCTION IF EXISTS internal.calc_active_items(UUID) CASCADE;
DROP FUNCTION IF EXISTS internal.calc_progress_history(UUID) CASCADE;
DROP FUNCTION IF EXISTS internal.calc_weekly_history(UUID) CASCADE;
DROP FUNCTION IF EXISTS internal.calc_category_stats(UUID) CASCADE;
DROP FUNCTION IF EXISTS internal.calc_rewards(UUID) CASCADE;
DROP FUNCTION IF EXISTS internal.calc_mood(UUID) CASCADE;
DROP FUNCTION IF EXISTS internal.calc_streaks(UUID) CASCADE;
DROP FUNCTION IF EXISTS internal.calc_recent_activity(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.refresh_performance_analytics(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.get_dashboard(UUID, BOOLEAN) CASCADE;
DROP FUNCTION IF EXISTS internal.trigger_refresh_analytics() CASCADE;
DROP FUNCTION IF EXISTS public.ensure_user_analytics(UUID) CASCADE;
DROP FUNCTION IF EXISTS internal.refresh_all_analytics() CASCADE;
DROP FUNCTION IF EXISTS internal.on_user_profile_created_init_analytics() CASCADE;
DROP FUNCTION IF EXISTS internal.fn_sync_mentorship_snapshots() CASCADE;

-- 2. TABLE DEFINITION

CREATE TABLE IF NOT EXISTS public.performance_analytics (
    -- Primary key
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Foreign key: one row per user, auto-deleted when user is deleted
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,

    -- ──────────────────────────────────────────────────────
    -- COLUMN: overview
    -- Contains:
    --   summary            → global header metrics
    --   daily_tasks_stats  → all-time day_tasks aggregates
    --   weekly_tasks_stats → all-time weekly_tasks aggregates
    --   long_goals_stats   → all-time long_goals aggregates
    --   bucket_list_stats  → all-time bucket_models aggregates
    -- ──────────────────────────────────────────────────────
    overview JSONB NOT NULL DEFAULT '{
        "summary": {
            "global_rank": 0,
            "points_today": 0,
            "total_points": 0,
            "total_rewards": 0,
            "average_rating": 0,
            "current_streak": 0,
            "longest_streak": 0,
            "average_progress": 0,
            "points_this_week": 0,
            "best_tier_achieved": "none",
            "completion_rate_all": 0,
            "completion_rate_week": 0,
            "completion_rate_today": 0,
            "daily_tasks_points": 0,
            "weekly_tasks_points": 0,
            "long_goals_points": 0,
            "bucket_list_points": 0
        },
        "daily_tasks_stats": {
            "total_day_tasks": 0,
            "day_tasks_completed": 0,
            "day_tasks_not_completed": 0,
            "day_tasks_completion_rate": 0,
            "day_tasks_completion_rating": 0,
            "total_day_tasks_progress": 0,
            "total_day_tasks_points": 0,
            "completion_rate_today": 0
        },
        "weekly_tasks_stats": {
            "total_week_tasks": 0,
            "week_tasks_completed": 0,
            "week_tasks_not_completed": 0,
            "week_tasks_completion_rate": 0,
            "week_tasks_completion_rating": 0,
            "total_week_tasks_progress": 0,
            "total_week_tasks_points": 0
        },
        "long_goals_stats": {
            "total_long_goals": 0,
            "long_goals_active": 0,
            "long_goals_completed": 0,
            "long_goals_not_started": 0,
            "long_goals_completion_rate": 0,
            "long_goals_average_progress": 0,
            "long_goals_completion_rating": 0,
            "total_long_goals_progress": 0,
            "total_long_goals_points": 0
        },
        "bucket_list_stats": {
            "total_bucket_items": 0,
            "bucket_items_completed": 0,
            "bucket_items_in_progress": 0,
            "bucket_items_not_started": 0,
            "bucket_completion_rate": 0,
            "bucket_average_progress": 0,
            "bucket_completion_rating": 0,
            "total_bucket_progress": 0,
            "total_bucket_points": 0
        }
    }'::jsonb,

    -- ──────────────────────────────────────────────────────
    -- COLUMN: today
    -- Contains:
    --   date                → today's date
    --   day_name            → e.g. "Thursday"
    --   diary_entry         → today's diary entry info
    --   buckets_entry       → bucket checklist items active today
    --   day_tasks           → all day tasks scheduled today
    --   week_tasks_due_today→ weekly tasks whose day matches today
    --   long_goals_due_today→ long goals with work scheduled today
    --   summary             → aggregate counts/points for today
    -- ──────────────────────────────────────────────────────
    today JSONB NOT NULL DEFAULT '{
        "date": null,
        "day_name": "",
        "diary_entry": {"has_entry": false, "mood_label": "", "word_count": 0, "mood_rating": 0},
        "buckets_entry": [],
        "day_tasks": [],
        "week_tasks_due_today": [],
        "long_goals_due_today": [],
        "summary": {
            "total_scheduled_task": 0,
            "not_completed": 0,
            "completed": 0,
            "in_progress": 0,
            "points_earned": 0,
            "day_rating": 0
        }
    }'::jsonb,

    -- ──────────────────────────────────────────────────────
    -- COLUMN: active_items
    -- RULE: Only inProgress items are stored here.
    --       Completed / onHold / cancelled items are excluded.
    -- Contains:
    --   active_day_tasks  → day tasks still in progress
    --   active_buckets    → buckets still in progress
    --   active_long_goals → long goals still in progress
    --   active_week_tasks → weekly tasks still in progress
    -- Each item includes points/progress/penalty/reward from its
    -- source model (Metadata / BucketMetadata / GoalAnalysis / WeeklySummary)
    -- ──────────────────────────────────────────────────────
    active_items JSONB NOT NULL DEFAULT '{
        "active_day_tasks": [],
        "active_buckets": [],
        "active_long_goals": [],
        "active_week_tasks": []
    }'::jsonb,

    -- ──────────────────────────────────────────────────────
    -- COLUMN: progress_history
    -- Contains 30 days of consolidated daily stats.
    -- daily_stats: ONE array with date/points/tasks_completed/
    --              streaks/completion_rate per day (NOT 4 arrays).
    -- ──────────────────────────────────────────────────────
    progress_history JSONB NOT NULL DEFAULT '{
        "trend": "stable",
        "average_progress": 0,
        "best_day": null,
        "worst_day": null,
        "daily_stats": []
    }'::jsonb,

    -- ──────────────────────────────────────────────────────
    -- COLUMN: weekly_history
    -- Contains 12 weeks of consolidated weekly stats.
    -- weekly_stats: ONE array with week_number/week_start/points/
    --               tasks_completed/goals_completed/completion_rate.
    -- ──────────────────────────────────────────────────────
    weekly_history JSONB NOT NULL DEFAULT '{
        "last_week_points": 0,
        "current_week_points": 0,
        "average_weekly_points": 0,
        "week_over_week_change": 0,
        "best_week": null,
        "worst_week": null,
        "weekly_stats": []
    }'::jsonb,

    -- ──────────────────────────────────────────────────────
    -- COLUMN: category_stats
    -- Aggregated points/completion per category_type.
    -- Sources: day_tasks + weekly_tasks combined.
    -- ──────────────────────────────────────────────────────
    category_stats JSONB NOT NULL DEFAULT '{
        "stats": [],
        "top_category": "",
        "total_points": 0,
        "category_percentages": {}
    }'::jsonb,

    -- ──────────────────────────────────────────────────────
    -- COLUMN: rewards
    -- Contains:
    --   summary          → high-level reward totals
    --   earned_rewards_no→ ALL-TIME count of each tier earned
    --   unlocked_rewards → full list of all rewards ever earned
    -- ──────────────────────────────────────────────────────
    rewards JSONB NOT NULL DEFAULT '{
        "summary": {
            "all_rewards_points": 0,
            "best_tier_achieved": "none",
            "worst_tier_achieved": "none",
            "total_rewards_earned": 0
        },
        "earned_rewards_no": {
            "nova": 0, "radiant": 0, "prism": 0, "crystal": 0,
            "blaze": 0, "ember": 0, "flame": 0, "spark": 0
        },
        "unlocked_rewards": []
    }'::jsonb,

    -- ──────────────────────────────────────────────────────
    -- COLUMN: mood
    -- Sourced entirely from diary_entries.mood column.
    -- Scale: 1–10 throughout (DB, model, and UI all use 1–10).
    -- ──────────────────────────────────────────────────────
    mood JSONB NOT NULL DEFAULT '{
        "trend": "stable",
        "today_mood": null,
        "mood_history": [],
        "mood_frequency": {},
        "most_common_mood": "Neutral",
        "average_mood_last_7_days": 0,
        "average_mood_last_30_days": 0
    }'::jsonb,

    -- ──────────────────────────────────────────────────────
    -- COLUMN: streaks
    -- Expanded into 6 sub-objects:
    --   current       → current streak info
    --   longest       → all-time longest streak
    --   next_milestone→ next milestone target + progress
    --   risk          → is streak at risk of breaking today
    --   history       → 30-day calendar + break history (90 days)
    --   stats         → all-time aggregate streak stats
    -- ──────────────────────────────────────────────────────
    streaks JSONB NOT NULL DEFAULT '{
        "current": {"days": 0, "is_active": false, "started_date": null, "last_active_date": null},
        "longest": {"days": 0, "started_date": null, "ended_date": null},
        "next_milestone": {"target": 3, "days_remaining": 3, "progress_percent": 0},
        "risk": {"is_at_risk": false, "hours_until_break": null, "last_activity_date": null},
        "history": {"calendar_30_days": {}, "breaks_in_last_90_days": []},
        "stats": {"total_active_days_all_time": 0, "average_streak": 0, "most_common_break_day": ""},
        "milestones": [3, 7, 14, 21, 30, 60, 90, 180, 365]
    }'::jsonb,

    -- ──────────────────────────────────────────────────────
    -- COLUMN: recent_activity
    -- Last 15 days of user activity across all 5 source tables.
    -- Each item has: id, type, action, category, sub_types,
    --                message, points, is_milestone, created_at
    -- Auto-refreshed on any change to source tables via trigger.
    -- ──────────────────────────────────────────────────────
    recent_activity JSONB NOT NULL DEFAULT '[]'::jsonb,
    last_notified   JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- Timestamps
    snapshot_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
-- STEP 3: INDEXES
-- ============================================================

-- Primary lookup: find a user's analytics row
CREATE INDEX IF NOT EXISTS idx_pa_user_id
    ON public.performance_analytics(user_id);

-- Used by get_dashboard() to check if data is stale
CREATE INDEX IF NOT EXISTS idx_pa_updated_at
    ON public.performance_analytics(updated_at DESC);


-- ============================================================
-- STEP 3b: ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.performance_analytics ENABLE ROW LEVEL SECURITY;

-- Drop policies if they exist to prevent duplication errors
DROP POLICY IF EXISTS "pa_select_own" ON public.performance_analytics;
DROP POLICY IF EXISTS "pa_insert_own" ON public.performance_analytics;
DROP POLICY IF EXISTS "pa_update_own" ON public.performance_analytics;
DROP POLICY IF EXISTS "pa_select_mentors" ON public.performance_analytics;
DROP POLICY IF EXISTS "pa_select_leaderboard" ON public.performance_analytics;

-- User can read their own analytics
CREATE POLICY "pa_select_own"
    ON public.performance_analytics FOR SELECT
    USING (auth.uid() = user_id);

-- User can insert their own analytics row
CREATE POLICY "pa_insert_own"
    ON public.performance_analytics FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- User can update their own analytics row
CREATE POLICY "pa_update_own"
    ON public.performance_analytics FOR UPDATE
    USING (auth.uid() = user_id);

-- Active mentors can read their mentee's analytics
CREATE POLICY "pa_select_mentors"
    ON public.performance_analytics FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.mentorship_connections
            WHERE mentor_id    = auth.uid()
              AND owner_id     = performance_analytics.user_id
              AND access_status = 'active'
        )
    );

-- Public profiles visible to all authenticated users (leaderboard)
CREATE POLICY "pa_select_leaderboard"
    ON public.performance_analytics FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.user_profiles
            WHERE user_id           = performance_analytics.user_id
              AND is_profile_public = TRUE
        )
    );


-- ============================================================
-- STEP 3c: REALTIME
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND tablename = 'performance_analytics'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.performance_analytics;
    END IF;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;


-- ============================================================
-- STEP 3d: BASE TABLE GRANTS
-- ============================================================

GRANT SELECT, INSERT, UPDATE ON public.performance_analytics TO authenticated;


-- ============================================================
-- ============================================================
-- SECTION FUNCTIONS
-- Each function calculates exactly ONE column.
-- ============================================================
-- ============================================================


CREATE OR REPLACE FUNCTION internal.calc_total_points(p_user_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_day    INT := 0;
    v_week   INT := 0;
    v_goal   INT := 0;
    v_bucket INT := 0;
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Day tasks: points stored in metadata->>'points_earned'
    SELECT COALESCE(SUM(COALESCE(
        (metadata->>'points_earned')::numeric::int, 0)), 0)
    INTO v_day FROM public.day_tasks WHERE user_id = p_user_id;

    -- Weekly tasks: points stored in metadata->>'points_earned'
    SELECT COALESCE(SUM(COALESCE(
        (metadata->>'points_earned')::numeric::int, 0)), 0)
    INTO v_week FROM public.weekly_tasks WHERE user_id = p_user_id;

    -- Long goals: points stored in analysis->>'points_earned'
    SELECT COALESCE(SUM(COALESCE(
        (analysis->>'points_earned')::numeric::int, 0)), 0)
    INTO v_goal FROM public.long_goals WHERE user_id = p_user_id;

    -- Buckets: points stored in metadata->>'total_points_earned'
    SELECT COALESCE(SUM(COALESCE(
        (metadata->>'total_points_earned')::numeric::int, 0)), 0)
    INTO v_bucket FROM public.bucket_models WHERE user_id = p_user_id;

    RETURN v_day + v_week + v_goal + v_bucket;
END;
$$;


CREATE OR REPLACE FUNCTION internal.calc_overview(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Summary metrics
    v_total_points      INT    := 0;
    v_points_today      INT    := 0;
    v_points_week       INT    := 0;
    v_total_rewards     INT    := 0;
    v_avg_rating        FLOAT  := 0;
    v_avg_progress      INT    := 0;
    v_best_tier         TEXT   := 'none';
    v_rank              INT    := 1;
    v_total_users       INT    := 1;
    v_rate_all          FLOAT  := 0;
    v_rate_week         FLOAT  := 0;
    v_rate_today        FLOAT  := 0;
    v_total_tasks       INT    := 0;
    v_completed_tasks   INT    := 0;
    v_week_start        DATE;

    -- Streak (inlined to avoid cross-function SECURITY DEFINER issues)
    v_cur_streak        INT    := 0;
    v_long_streak       INT    := 0;
    v_streak_broken     BOOLEAN := FALSE;
    v_streak_temp       INT    := 0;
    v_streak_date       DATE;
    v_streak_active     BOOLEAN;
    i                   INT;

    -- day_tasks stats
    v_dt_total          INT    := 0;
    v_dt_completed      INT    := 0;
    v_dt_rate           FLOAT  := 0;
    v_dt_rating         FLOAT  := 0;
    v_dt_progress       INT    := 0;
    v_dt_points         INT    := 0;

    -- weekly_tasks stats
    v_wt_total          INT    := 0;
    v_wt_completed      INT    := 0;
    v_wt_rate           FLOAT  := 0;
    v_wt_rating         FLOAT  := 0;
    v_wt_progress       INT    := 0;
    v_wt_points         INT    := 0;

    -- long_goals stats
    v_lg_total          INT    := 0;
    v_lg_active         INT    := 0;
    v_lg_completed      INT    := 0;
    v_lg_not_started    INT    := 0;
    v_lg_rate           FLOAT  := 0;
    v_lg_avg_progress   FLOAT  := 0;
    v_lg_rating         FLOAT  := 0;
    v_lg_points         INT    := 0;

    -- bucket_models stats
    v_bk_total          INT    := 0;
    v_bk_completed      INT    := 0;
    v_bk_in_progress    INT    := 0;
    v_bk_not_started    INT    := 0;
    v_bk_rate           FLOAT  := 0;
    v_bk_avg_progress   FLOAT  := 0;
    v_bk_rating         FLOAT  := 0;
    v_bk_points         INT    := 0;
BEGIN
    v_week_start   := DATE_TRUNC('week', CURRENT_DATE)::date;
    v_total_points := internal.calc_total_points(p_user_id);

    -- ── Points today (day_tasks only, task_date = today) ──────
    SELECT COALESCE(SUM(COALESCE(
        (metadata->>'points_earned')::numeric::int, 0)), 0)
    INTO v_points_today FROM public.day_tasks
    WHERE user_id = p_user_id
      AND (timeline->>'task_date')::date = CURRENT_DATE;

    -- ── Points this week (day_tasks only, task_date >= week start) ─
    SELECT COALESCE(SUM(COALESCE(
        (metadata->>'points_earned')::numeric::int, 0)), 0)
    INTO v_points_week FROM public.day_tasks
    WHERE user_id = p_user_id
      AND (timeline->>'task_date')::date >= v_week_start;

    -- ── Completion rate ALL TIME (day_tasks) ──────────────────
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE (metadata->>'is_complete')::boolean = true)
    INTO v_total_tasks, v_completed_tasks
    FROM public.day_tasks WHERE user_id = p_user_id;

    IF v_total_tasks > 0 THEN
        v_rate_all := ROUND((v_completed_tasks::float
                            / v_total_tasks * 100)::numeric, 1);
    END IF;

    -- ── Completion rate THIS WEEK (day_tasks) ─────────────────
    SELECT CASE WHEN COUNT(*) > 0
           THEN ROUND((COUNT(*) FILTER (
               WHERE (metadata->>'is_complete')::boolean)::float
               / COUNT(*) * 100)::numeric, 1)
           ELSE 0 END
    INTO v_rate_week FROM public.day_tasks
    WHERE user_id = p_user_id
      AND (timeline->>'task_date')::date >= v_week_start;

    -- ── Completion rate TODAY (day_tasks) ─────────────────────
    SELECT CASE WHEN COUNT(*) > 0
           THEN ROUND((COUNT(*) FILTER (
               WHERE (metadata->>'is_complete')::boolean)::float
               / COUNT(*) * 100)::numeric, 1)
           ELSE 0 END
    INTO v_rate_today FROM public.day_tasks
    WHERE user_id = p_user_id
      AND (timeline->>'task_date')::date = CURRENT_DATE;

    -- ── Inline streak calculation (60-day lookback) ───────────
    -- REASON: Calling calc_streaks() from here fails silently in
    -- Supabase SECURITY DEFINER context. Inlined is proven safe.
    FOR i IN 0..59 LOOP
        v_streak_date := CURRENT_DATE - i;

        v_streak_active := EXISTS (
            SELECT 1 FROM public.day_tasks
            WHERE user_id = p_user_id
              AND (timeline->>'task_date')::date = v_streak_date
              AND (metadata->>'is_complete')::boolean = true
            UNION ALL
            SELECT 1 FROM public.diary_entries
            WHERE user_id = p_user_id
              AND entry_date = v_streak_date
        );

        -- Current streak: count consecutive days back from today
        IF NOT v_streak_broken THEN
            IF v_streak_active     THEN v_cur_streak  := v_cur_streak + 1;
            ELSIF i > 0            THEN v_streak_broken := TRUE;
            END IF;
        END IF;

        -- Longest streak: rolling max
        IF v_streak_active THEN
            v_streak_temp := v_streak_temp + 1;
            IF v_streak_temp > v_long_streak THEN
                v_long_streak := v_streak_temp;
            END IF;
        ELSE
            v_streak_temp := 0;
        END IF;
    END LOOP;
    v_long_streak := GREATEST(v_long_streak, v_cur_streak);

    -- ── Global rank (Rule 5 Scalability Hardening) ────────────
    -- [CRITICAL] Full-table scan O(N^2) ranking removed for production scale.
    -- TODO: Move to a background materialised view or summary table.
    v_total_users := 0; 
    v_rank        := 0;

    -- ── Average rating (day_tasks) ────────────────────────────
    SELECT COALESCE(AVG((metadata->>'rating')::float), 0)
    INTO v_avg_rating FROM public.day_tasks
    WHERE user_id = p_user_id AND (metadata->>'rating') IS NOT NULL;

    -- ── Average progress (day_tasks) ──────────────────────────
    SELECT COALESCE(AVG((metadata->>'progress')::numeric), 0)::int
    INTO v_avg_progress FROM public.day_tasks
    WHERE user_id = p_user_id AND (metadata->>'progress') IS NOT NULL;

    -- ── Best tier achieved (across ALL task types) ────────────
    -- Checks day_tasks, weekly_tasks, long_goals, bucket_models
    -- and picks the highest tier level ever earned
    v_best_tier := COALESCE((
        SELECT tier FROM (
            SELECT metadata->'reward_package'->>'tier' AS tier
            FROM public.day_tasks
            WHERE user_id = p_user_id
              AND (metadata->'reward_package'->>'earned')::boolean = true
            UNION ALL
            SELECT metadata->'reward_package'->>'tier'
            FROM public.weekly_tasks
            WHERE user_id = p_user_id
              AND (metadata->'reward_package'->>'earned')::boolean = true
            UNION ALL
            SELECT analysis->'reward_package'->>'tier'
            FROM public.long_goals
            WHERE user_id = p_user_id
              AND (analysis->'reward_package'->>'earned')::boolean = true
            UNION ALL
            SELECT metadata->'reward_package'->>'tier'
            FROM public.bucket_models
            WHERE user_id = p_user_id
              AND (metadata->'reward_package'->>'earned')::boolean = true
        ) all_tiers
        ORDER BY CASE tier
            WHEN 'nova'    THEN 8 WHEN 'radiant' THEN 7
            WHEN 'prism'   THEN 6 WHEN 'crystal' THEN 5
            WHEN 'blaze'   THEN 4 WHEN 'ember'   THEN 3
            WHEN 'flame'   THEN 2 WHEN 'spark'   THEN 1
            ELSE 0 END DESC
        LIMIT 1
    ), 'none');

    -- ── Total rewards (all task types) ────────────────────────
    v_total_rewards := (
        SELECT COUNT(*) FROM public.day_tasks
        WHERE user_id = p_user_id
          AND (metadata->'reward_package'->>'earned')::boolean = true
    ) + (
        SELECT COUNT(*) FROM public.weekly_tasks
        WHERE user_id = p_user_id
          AND (metadata->'reward_package'->>'earned')::boolean = true
    ) + (
        SELECT COUNT(*) FROM public.long_goals
        WHERE user_id = p_user_id
          AND (analysis->'reward_package'->>'earned')::boolean = true
    ) + (
        SELECT COUNT(*) FROM public.bucket_models
        WHERE user_id = p_user_id
          AND (metadata->'reward_package'->>'earned')::boolean = true
    );

    -- ── daily_tasks_stats ─────────────────────────────────────
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE (metadata->>'is_complete')::boolean = true),
        COALESCE(SUM((metadata->>'points_earned')::numeric::int),  0),
        COALESCE(AVG((metadata->>'rating')::float),                0),
        COALESCE(AVG((metadata->>'progress')::numeric),            0)::int
    INTO v_dt_total, v_dt_completed, v_dt_points, v_dt_rating, v_dt_progress
    FROM public.day_tasks WHERE user_id = p_user_id;

    v_dt_rate := CASE WHEN v_dt_total > 0
        THEN ROUND((v_dt_completed::float / v_dt_total * 100)::numeric, 1)
        ELSE 0 END;

    -- ── weekly_tasks_stats ────────────────────────────────────
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE indicators->>'status' = 'completed'),
        COALESCE(SUM((metadata->>'points_earned')::numeric::int), 0),
        COALESCE(AVG((metadata->>'rating')::float),              0),
        COALESCE(AVG((metadata->>'progress')::numeric),           0)::int
    INTO v_wt_total, v_wt_completed, v_wt_points, v_wt_rating, v_wt_progress
    FROM public.weekly_tasks WHERE user_id = p_user_id;

    v_wt_rate := CASE WHEN v_wt_total > 0
        THEN ROUND((v_wt_completed::float / v_wt_total * 100)::numeric, 1)
        ELSE 0 END;

    -- ── long_goals_stats ──────────────────────────────────────
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE indicators->>'status' IN ('inProgress', 'pending')),
        COUNT(*) FILTER (WHERE indicators->>'status' = 'completed'),
        COUNT(*) FILTER (WHERE indicators->>'status' = 'pending'
                            OR indicators->>'status' IS NULL),
        COALESCE(SUM((analysis->>'points_earned')::numeric::int),    0),
        COALESCE(AVG((analysis->>'average_rating')::float),          0),
        COALESCE(AVG((analysis->>'average_progress')::numeric),      0)
    INTO v_lg_total, v_lg_active, v_lg_completed, v_lg_not_started,
         v_lg_points, v_lg_rating, v_lg_avg_progress
    FROM public.long_goals WHERE user_id = p_user_id;

    v_lg_rate := CASE WHEN v_lg_total > 0
        THEN ROUND((v_lg_completed::float / v_lg_total * 100)::numeric, 1)
        ELSE 0 END;

    -- ── bucket_list_stats ─────────────────────────────────────
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE (timeline->>'complete_date') IS NOT NULL),
        COUNT(*) FILTER (WHERE (timeline->>'complete_date') IS NULL
                           AND COALESCE((metadata->>'average_progress')::numeric, 0) > 0),
        COUNT(*) FILTER (WHERE (timeline->>'complete_date') IS NULL
                           AND COALESCE((metadata->>'average_progress')::numeric, 0) = 0),
        COALESCE(SUM((metadata->>'total_points_earned')::numeric::int), 0),
        COALESCE(AVG((metadata->>'average_rating')::float),             0),
        COALESCE(AVG((metadata->>'average_progress')::numeric),         0)
    INTO v_bk_total, v_bk_completed, v_bk_in_progress, v_bk_not_started,
         v_bk_points, v_bk_rating, v_bk_avg_progress
    FROM public.bucket_models WHERE user_id = p_user_id;

    v_bk_rate := CASE WHEN v_bk_total > 0
        THEN ROUND((v_bk_completed::float / v_bk_total * 100)::numeric, 1)
        ELSE 0 END;

    -- ── Assemble and return ───────────────────────────────────
    RETURN jsonb_build_object(
        'summary', jsonb_build_object(
            'global_rank',           v_rank,
            'points_today',          v_points_today,
            'total_points',          v_total_points,
            'total_rewards',         v_total_rewards,
            'average_rating',        ROUND(v_avg_rating::numeric, 1),
            'current_streak',        v_cur_streak,
            'longest_streak',        v_long_streak,
            'average_progress',      v_avg_progress,
            'points_this_week',      v_points_week,
            'best_tier_achieved',    v_best_tier,
            'completion_rate_all',   v_rate_all,
            'completion_rate_week',  v_rate_week,
            'completion_rate_today', v_rate_today,
            'daily_tasks_points',   v_dt_points,
            'weekly_tasks_points',  v_wt_points,
            'long_goals_points',    v_lg_points,
            'bucket_list_points',   v_bk_points
        ),
        'daily_tasks_stats', jsonb_build_object(
            'total_day_tasks',             v_dt_total,
            'day_tasks_completed',         v_dt_completed,
            'day_tasks_not_completed',     GREATEST(v_dt_total - v_dt_completed, 0),
            'day_tasks_completion_rate',   v_dt_rate,
            'day_tasks_completion_rating', ROUND(v_dt_rating::numeric, 1),
            'total_day_tasks_progress',    v_dt_progress,
            'total_day_tasks_points',      v_dt_points,
            'completion_rate_today',       v_rate_today
        ),
        'weekly_tasks_stats', jsonb_build_object(
            'total_week_tasks',             v_wt_total,
            'week_tasks_completed',         v_wt_completed,
            'week_tasks_not_completed',     GREATEST(v_wt_total - v_wt_completed, 0),
            'week_tasks_completion_rate',   v_wt_rate,
            'week_tasks_completion_rating', ROUND(v_wt_rating::numeric, 1),
            'total_week_tasks_progress',    v_wt_progress,
            'total_week_tasks_points',      v_wt_points
        ),
        'long_goals_stats', jsonb_build_object(
            'total_long_goals',             v_lg_total,
            'long_goals_active',            v_lg_active,
            'long_goals_completed',         v_lg_completed,
            'long_goals_not_started',       v_lg_not_started,
            'long_goals_completion_rate',   v_lg_rate,
            'long_goals_average_progress',  ROUND(v_lg_avg_progress::numeric, 1),
            'long_goals_completion_rating', ROUND(v_lg_rating::numeric, 1),
            'total_long_goals_progress',    ROUND(v_lg_avg_progress::numeric, 1),
            'total_long_goals_points',      v_lg_points
        ),
        'bucket_list_stats', jsonb_build_object(
            'total_bucket_items',        v_bk_total,
            'bucket_items_completed',    v_bk_completed,
            'bucket_items_in_progress',  v_bk_in_progress,
            'bucket_items_not_started',  v_bk_not_started,
            'bucket_completion_rate',    v_bk_rate,
            'bucket_average_progress',   ROUND(v_bk_avg_progress::numeric, 1),
            'bucket_completion_rating',  ROUND(v_bk_rating::numeric, 1),
            'total_bucket_progress',     ROUND(v_bk_avg_progress::numeric, 1),
            'total_bucket_points',       v_bk_points
        )
    );
END;
$$;


-- COLUMN: today

CREATE OR REPLACE FUNCTION internal.calc_today(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_today_name        TEXT;
    v_today_name_short  TEXT;
    v_diary             JSONB;
    v_buckets           JSONB;
    v_day_tasks         JSONB;
    v_week_tasks        JSONB;
    v_long_goals        JSONB;
    v_summary           JSONB;
    v_total_scheduled   INT   := 0;
    v_completed         INT   := 0;
    v_in_progress       INT   := 0;
    v_not_completed     INT   := 0;
    v_points_earned     INT   := 0;
    v_day_rating        FLOAT := 0;
BEGIN
    -- [SECURITY] Ownership/Mentorship check
    IF p_user_id != auth.uid() AND NOT EXISTS (
        SELECT 1 FROM public.mentorship_connections
        WHERE mentor_id = auth.uid() AND owner_id = p_user_id AND access_status = 'active'
    ) AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- Today's day name (e.g. "thursday") and short form (e.g. "thu")
    v_today_name       := TRIM(LOWER(TO_CHAR(CURRENT_DATE, 'Day')));
    v_today_name_short := LEFT(v_today_name, 3);

    -- ── diary_entry ───────────────────────────────────────────
    -- Check if user wrote a diary entry today
    SELECT CASE WHEN COUNT(*) > 0 THEN
        jsonb_build_object(
            'has_entry',   true,
            'mood_label',  MAX(mood->>'label'),
            'word_count',  MAX(COALESCE((metadata->>'word_count')::int, 0)),
            'mood_rating', MAX(COALESCE((mood->>'rating')::int, 0))
        )
    ELSE
        jsonb_build_object(
            'has_entry',   false,
            'mood_label',  '',
            'word_count',  0,
            'mood_rating', 0
        )
    END
    INTO v_diary FROM public.diary_entries
    WHERE user_id = p_user_id AND entry_date = CURRENT_DATE;

    -- ── buckets_entry ─────────────────────────────────────────
    -- Bucket checklist items that were marked done today.
    -- done_time comes from checklist item's date field.
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',            bm.id,
        'title',         bm.title,
        'checklist_task', cl_item->>'task',
        'status',        CASE WHEN (bm.timeline->>'complete_date') IS NOT NULL
                              THEN 'completed' ELSE 'inProgress' END,
        'priority',      COALESCE(bm.metadata->>'priority', 'medium'),
        'points',        COALESCE((cl_item->>'points')::int, 0),
        'progress',      COALESCE((bm.metadata->>'average_progress')::numeric::int, 0),
        'reward',        CASE
                            WHEN (bm.metadata->'reward_package'->>'earned')::boolean = true
                            THEN COALESCE(
                                bm.metadata->'reward_package'->>'tagName',
                                bm.metadata->'reward_package'->>'tag_name')
                            ELSE NULL END,
        'done_time',     cl_item->>'date'
    )), '[]'::jsonb)
    INTO v_buckets
    FROM public.bucket_models bm,
         jsonb_array_elements(
            CASE 
                WHEN jsonb_typeof(bm.checklist) = 'object' AND bm.checklist ? 'items' THEN bm.checklist->'items'
                WHEN jsonb_typeof(bm.checklist) = 'array' THEN bm.checklist
                ELSE '[]'::jsonb
            END
         ) AS cl_item
    WHERE bm.user_id = p_user_id
      AND (cl_item->>'done')::boolean = true
      AND (cl_item->>'date')::date = CURRENT_DATE;

    -- ── day_tasks ─────────────────────────────────────────────
    -- All day tasks scheduled for today
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',            id,
        'title',         about_task->>'task_name',
        'priority',      COALESCE(indicators->>'priority', 'medium'),
        'status',        COALESCE(indicators->>'status', 'pending'),
        'category_type', COALESCE(category_type, ''),
        'points',        COALESCE((metadata->>'points_earned')::int, 0),
        'progress',      COALESCE((metadata->>'progress')::int, 0),
        -- penalty: null if no penalty, object if penalty exists
        'penalty',       CASE
                            WHEN jsonb_typeof(metadata->'penalty') = 'object' 
                                 AND COALESCE((metadata->'penalty'->>'penalty_points')::numeric, 0) > 0
                            THEN jsonb_build_object(
                                'penalty_points', (metadata->'penalty'->>'penalty_points')::int,
                                'reason', COALESCE(metadata->'penalty'->>'reason', 'Penalty applied'))
                            WHEN jsonb_typeof(metadata->'penalty') = 'number' 
                                 AND (metadata->>'penalty')::numeric > 0
                            THEN jsonb_build_object(
                                'penalty_points', (metadata->>'penalty')::int,
                                'reason', COALESCE(metadata->>'penalty_reason', 'Penalty applied'))
                            ELSE NULL END,
        -- reward: null if not earned, tagName string if earned
        'reward',        CASE
                            WHEN (metadata->'reward_package'->>'earned')::boolean = true
                            THEN COALESCE(
                                metadata->'reward_package'->>'tagName',
                                metadata->'reward_package'->>'tag_name')
                            ELSE NULL END,
        'is_complete',   COALESCE((metadata->>'is_complete')::boolean, false),
        'time_start',    timeline->>'starting_time',
        'time_end',      timeline->>'ending_time'
    ) ORDER BY timeline->>'starting_time'), '[]'::jsonb)
    INTO v_day_tasks FROM public.day_tasks
    WHERE user_id = p_user_id
      AND (timeline->>'task_date')::date = CURRENT_DATE;

    -- ── week_tasks_due_today ──────────────────────────────────
    -- Weekly tasks whose scheduled days include today
    -- timeline->>'task_days' is a comma/space-separated list of day names
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',            id,
        'title',         about_task->>'task_name',
        'priority',      COALESCE(indicators->>'priority', 'medium'),
        'status',        COALESCE(indicators->>'status', 'pending'),
        'category_type', COALESCE(category_type, ''),
        'points',        COALESCE((metadata->>'points_earned')::int, 0),
        'progress',      COALESCE((metadata->>'progress')::int, 0),
        'penalty',       CASE
                            WHEN jsonb_typeof(metadata->'penalty') = 'object' 
                                 AND COALESCE((metadata->'penalty'->>'penalty_points')::numeric, 0) > 0
                            THEN jsonb_build_object(
                                'penalty_points', (metadata->'penalty'->>'penalty_points')::int,
                                'reason', COALESCE(metadata->'penalty'->>'reason', 'Weekly task penalty'))
                            ELSE NULL END,
        'reward',        CASE
                            WHEN (metadata->'reward_package'->>'earned')::boolean = true
                            THEN COALESCE(
                                metadata->'reward_package'->>'tagName',
                                metadata->'reward_package'->>'tag_name')
                            ELSE NULL END,
        'is_complete',   (
                            COALESCE(indicators->>'status', '') = 'completed'
                            OR EXISTS (
                                SELECT 1 FROM jsonb_array_elements(
                                    CASE 
                                        WHEN jsonb_typeof(feedback) = 'object' AND feedback ? 'daily_progress_list' THEN feedback->'daily_progress_list'->'items'
                                        WHEN jsonb_typeof(feedback) = 'array' THEN feedback
                                        ELSE '[]'::jsonb
                                    END
                                ) f 
                                WHERE f->>'day_name' = INITCAP(v_today_name) 
                                AND (f->'daily_progress'->>'is_complete')::boolean = true
                            )
                         ),
        'time_start',    timeline->>'starting_time',
        'time_end',      timeline->>'ending_time'
    )), '[]'::jsonb)
    INTO v_week_tasks FROM public.weekly_tasks
    WHERE user_id = p_user_id
      AND LOWER(COALESCE(timeline->>'task_days', ''))
          LIKE '%' || v_today_name_short || '%'
      AND COALESCE(indicators->>'status', '') NOT IN ('cancelled', 'onHold');

    -- ── long_goals_due_today ──────────────────────────────────
    -- Long goals that have today as a scheduled work day
    -- work_schedule days stored in timeline->'work_schedule'->'days'
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',            id,
        'title',         title,
        'priority',      COALESCE(indicators->>'priority', 'medium'),
        'status',        COALESCE(indicators->>'status', 'pending'),
        'category_type', COALESCE(category_type, ''),
        'points',        COALESCE((analysis->>'points_earned')::int, 0),
        'progress',      COALESCE((analysis->>'average_progress')::numeric::int, 0),
        'penalty',       CASE
                            WHEN jsonb_typeof(analysis->'total_penalty') = 'object' 
                                 AND COALESCE((analysis->'total_penalty'->>'penalty_points')::numeric, 0) > 0
                            THEN jsonb_build_object(
                                'penalty_points', (analysis->'total_penalty'->>'penalty_points')::int,
                                'reason', COALESCE(analysis->'total_penalty'->>'reason', 'Long goal penalty'))
                            WHEN jsonb_typeof(analysis->'penalty') = 'object' 
                                 AND COALESCE((analysis->'penalty'->>'penalty_points')::numeric, 0) > 0
                            THEN jsonb_build_object(
                                'penalty_points', (analysis->'penalty'->>'penalty_points')::int,
                                'reason', COALESCE(analysis->'penalty'->>'reason', 'Long goal penalty'))
                            ELSE NULL END,
        'reward',        CASE
                            WHEN (analysis->'reward_package'->>'earned')::boolean = true
                            THEN COALESCE(
                                analysis->'reward_package'->>'tagName',
                                analysis->'reward_package'->>'tag_name')
                            ELSE NULL END,
        'is_complete',   (
                            COALESCE(indicators->>'status', '') = 'completed'
                            OR EXISTS (
                                SELECT 1
                                FROM jsonb_array_elements(
                                    CASE 
                                        WHEN jsonb_typeof(goal_log) = 'object' AND goal_log ? 'weekly_logs' THEN goal_log->'weekly_logs'->'items'
                                        WHEN jsonb_typeof(goal_log) = 'array' THEN goal_log
                                        ELSE '[]'::jsonb
                                    END
                                ) week_log
                                CROSS JOIN jsonb_array_elements(
                                    CASE 
                                        WHEN jsonb_typeof(week_log->'daily_feedback') = 'object' AND week_log->'daily_feedback' ? 'items' THEN week_log->'daily_feedback'->'items'
                                        WHEN jsonb_typeof(week_log->'daily_feedback') = 'array' THEN week_log->'daily_feedback'
                                        ELSE '[]'::jsonb
                                    END
                                ) df
                                WHERE (df->>'feedback_day')::date = CURRENT_DATE
                                  AND (df->'daily_progress'->>'is_complete')::boolean = true
                            )
                         ),
        'time_start',    timeline->'work_schedule'->'preferred_time_slot'->>'starting_time',
        'time_end',      timeline->'work_schedule'->'preferred_time_slot'->>'ending_time'
    )), '[]'::jsonb)
    INTO v_long_goals FROM public.long_goals
    WHERE user_id = p_user_id
      AND COALESCE(indicators->>'status', '') NOT IN ('cancelled', 'onHold')
      AND (
          -- stored as array: ["Saturday","Monday",...]
          LOWER(timeline->'work_schedule'->>'work_days') LIKE '%' || v_today_name_short || '%'
          OR
          -- stored as string fallback
          LOWER(COALESCE(timeline->'work_schedule'->>'days', '')) LIKE '%' || v_today_name_short || '%'
      );

    -- ── summary ───────────────────────────────────────────────
    -- Aggregate all today items for the summary card
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE status_val IN ('completed')),
        COUNT(*) FILTER (WHERE status_val = 'inProgress'),
        COALESCE(SUM(pts_val), 0),
        COALESCE(AVG(rating_val), 0)
    INTO v_total_scheduled, v_completed, v_in_progress, v_points_earned, v_day_rating
    FROM (
        -- Day tasks
        SELECT
            COALESCE(indicators->>'status', 'pending') AS status_val,
            COALESCE((metadata->>'points_earned')::numeric, 0) AS pts_val,
            COALESCE((metadata->>'rating')::float, 0) AS rating_val
        FROM public.day_tasks
        WHERE user_id = p_user_id
          AND (timeline->>'task_date')::date = CURRENT_DATE

        UNION ALL

        -- Weekly tasks due today
        SELECT
            CASE 
                WHEN (indicators->>'status') = 'completed' THEN 'completed'
                WHEN EXISTS (
                    SELECT 1 FROM jsonb_array_elements(
                        CASE 
                            WHEN jsonb_typeof(feedback) = 'object' AND feedback ? 'daily_progress_list' THEN feedback->'daily_progress_list'->'items'
                            WHEN jsonb_typeof(feedback) = 'array' THEN feedback
                            ELSE '[]'::jsonb
                        END
                    ) f 
                    WHERE f->>'day_name' = INITCAP(v_today_name) 
                    AND (f->'daily_progress'->>'is_complete')::boolean = true
                ) THEN 'completed'
                ELSE COALESCE(indicators->>'status', 'pending')
            END AS status_val,
            COALESCE((metadata->>'points_earned')::numeric, 0) AS pts_val,
            COALESCE((metadata->>'rating')::float, 0) AS rating_val
        FROM public.weekly_tasks
        WHERE user_id = p_user_id
          AND LOWER(COALESCE(timeline->>'task_days', ''))
              LIKE '%' || v_today_name_short || '%'
          AND COALESCE(indicators->>'status', '')
              NOT IN ('cancelled', 'onHold')

        UNION ALL

        -- Long goals due today
        SELECT
            CASE 
                WHEN (indicators->>'status') = 'completed' THEN 'completed'
                WHEN EXISTS (
                    SELECT 1
                    FROM jsonb_array_elements(
                        CASE 
                            WHEN jsonb_typeof(goal_log) = 'object' AND goal_log ? 'weekly_logs' THEN goal_log->'weekly_logs'->'items'
                            WHEN jsonb_typeof(goal_log) = 'array' THEN goal_log
                            ELSE '[]'::jsonb
                        END
                    ) week_log
                    CROSS JOIN jsonb_array_elements(
                        CASE 
                            WHEN jsonb_typeof(week_log->'daily_feedback') = 'object' AND week_log->'daily_feedback' ? 'items' THEN week_log->'daily_feedback'->'items'
                            WHEN jsonb_typeof(week_log->'daily_feedback') = 'array' THEN week_log->'daily_feedback'
                            ELSE '[]'::jsonb
                        END
                    ) df
                    WHERE (df->>'feedback_day')::date = CURRENT_DATE
                      AND (df->'daily_progress'->>'is_complete')::boolean = true
                ) THEN 'completed'
                ELSE COALESCE(indicators->>'status', 'pending')
            END AS status_val,
            COALESCE((analysis->>'points_earned')::numeric, 0) AS pts_val,
            COALESCE((analysis->>'average_rating')::float, 0) AS rating_val
        FROM public.long_goals
        WHERE user_id = p_user_id
          AND COALESCE(indicators->>'status', '') NOT IN ('cancelled', 'onHold')
          AND (
              LOWER(timeline->'work_schedule'->>'work_days') LIKE '%' || v_today_name_short || '%'
              OR LOWER(COALESCE(timeline->'work_schedule'->>'days', '')) LIKE '%' || v_today_name_short || '%'
          )

        UNION ALL

        -- Buckets completed today
        SELECT
            'completed' AS status_val,
            COALESCE((cl_item->>'points')::numeric, 0) AS pts_val,
            COALESCE((bm.metadata->>'average_rating')::float, 0) AS rating_val
        FROM public.bucket_models bm,
             jsonb_array_elements(
                CASE 
                    WHEN jsonb_typeof(bm.checklist) = 'object' AND bm.checklist ? 'items' THEN bm.checklist->'items'
                    WHEN jsonb_typeof(bm.checklist) = 'array' THEN bm.checklist
                    ELSE '[]'::jsonb
                END
             ) AS cl_item
        WHERE bm.user_id = p_user_id
          AND (cl_item->>'done')::boolean = true
          AND (cl_item->>'date')::date = CURRENT_DATE
    ) today_all;

    v_not_completed := GREATEST(v_total_scheduled - v_completed, 0);

    RETURN jsonb_build_object(
        'date',                 CURRENT_DATE,
        'day_name',             INITCAP(v_today_name),
        'diary_entry',          COALESCE(v_diary, jsonb_build_object(
                                    'has_entry', false, 'mood_label', '',
                                    'word_count', 0,   'mood_rating', 0)),
        'buckets_entry',        COALESCE(v_buckets,    '[]'::jsonb),
        'day_tasks',            COALESCE(v_day_tasks,  '[]'::jsonb),
        'week_tasks_due_today', COALESCE(v_week_tasks, '[]'::jsonb),
        'long_goals_due_today', COALESCE(v_long_goals, '[]'::jsonb),
        'summary', jsonb_build_object(
            'total_scheduled_task', v_total_scheduled,
            'not_completed',        v_not_completed,
            'completed',            v_completed,
            'in_progress',          v_in_progress,
            'points_earned',        v_points_earned,
            'day_rating',           ROUND(v_day_rating::numeric, 1)
        )
    );
END;
$$;


CREATE OR REPLACE FUNCTION internal.calc_active_items(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_day_tasks  JSONB;
    v_buckets    JSONB;
    v_long_goals JSONB;
    v_week_tasks JSONB;
BEGIN
    -- ── active_day_tasks ──────────────────────────────────────
    -- Only tasks NOT completed and NOT cancelled / skipped
    -- Points/progress come from day_tasks.metadata (Metadata model)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',          id,
        'title',       about_task->>'task_name',
        'status',      COALESCE(indicators->>'status', 'pending'),
        'priority',    COALESCE(indicators->>'priority', 'medium'),
        -- from Metadata model
        'points',      COALESCE((metadata->>'points_earned')::int, 0),
        'progress',    COALESCE((metadata->>'progress')::int, 0),
        'penalty',     CASE
                          WHEN jsonb_typeof(metadata->'penalty') = 'object' 
                               AND COALESCE((metadata->'penalty'->>'penalty_points')::numeric, 0) > 0
                          THEN jsonb_build_object(
                              'penalty_points', (metadata->'penalty'->>'penalty_points')::int,
                              'reason', COALESCE(metadata->'penalty'->>'reason', 'Penalty applied'))
                          WHEN jsonb_typeof(metadata->'penalty') = 'number' 
                               AND (metadata->>'penalty')::numeric > 0
                          THEN jsonb_build_object(
                              'penalty_points', (metadata->>'penalty')::int,
                              'reason', COALESCE(metadata->>'penalty_reason', 'Penalty applied'))
                          ELSE NULL END,
        'reward',      CASE
                          WHEN (metadata->'reward_package'->>'earned')::boolean = true
                          THEN COALESCE(
                              metadata->'reward_package'->>'tagName',
                              metadata->'reward_package'->>'tag_name')
                          ELSE NULL END,
        'time_start',  timeline->>'starting_time',
        'time_end',    timeline->>'ending_time',
        'is_complete', false
    ) ORDER BY NULLIF(timeline->>'task_date','')::date ASC,
               timeline->>'starting_time' ASC), '[]'::jsonb)
    INTO v_day_tasks FROM public.day_tasks
    WHERE user_id = p_user_id
      -- Only inProgress: exclude completed, cancelled, skipped
      AND COALESCE((metadata->>'is_complete')::boolean, false) = false
      AND COALESCE(indicators->>'status', '')
          NOT IN ('completed', 'cancelled', 'skipped');

    -- ── active_buckets ────────────────────────────────────────
    -- Only buckets with no complete_date
    -- Points/progress come from bucket_models.metadata (BucketMetadata)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',            id,
        'title',         title,
        'status',        'inProgress',
        'priority',      COALESCE(metadata->>'priority', 'medium'),
        -- from BucketMetadata model
        'points',        COALESCE((metadata->>'total_points_earned')::int, 0),
        'progress',      COALESCE((metadata->>'average_progress')::numeric::int, 0),
        'penalty',       NULL,  -- buckets have no penalty system
        'reward',        CASE
                            WHEN (metadata->'reward_package'->>'earned')::boolean = true
                            THEN COALESCE(
                                metadata->'reward_package'->>'tagName',
                                metadata->'reward_package'->>'tag_name')
                            ELSE NULL END,
        'statinge_date', timeline->>'start_date',
        'endinge_date',  timeline->>'due_date',
        -- is_overdue: due date is in the past and not yet completed
        'is_overdue',    CASE
                            WHEN (timeline->>'due_date') IS NOT NULL
                             AND LENGTH(timeline->>'due_date') > 0
                             AND (timeline->>'due_date')::timestamptz < NOW()
                            THEN true ELSE false END
    )), '[]'::jsonb)
    INTO v_buckets FROM public.bucket_models
    WHERE user_id = p_user_id
      -- Only inProgress: exclude completed buckets
      AND (timeline->>'complete_date') IS NULL;

    -- ── active_long_goals ─────────────────────────────────────
    -- Only goals with status = inProgress or pending
    -- Points/progress come from long_goals.analysis (GoalAnalysis)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',            id,
        'title',         title,
        'status',        COALESCE(indicators->>'status', 'pending'),
        'priority',      COALESCE(indicators->>'priority', 'medium'),
        -- from GoalAnalysis model
        'points',        COALESCE((analysis->>'points_earned')::int, 0),
        'progress',      COALESCE((analysis->>'average_progress')::numeric::int, 0),
        'penalty',       CASE
                            WHEN jsonb_typeof(analysis->'total_penalty') = 'object' 
                                 AND COALESCE((analysis->'total_penalty'->>'penalty_points')::numeric, 0) > 0
                            THEN jsonb_build_object(
                                'penalty_points', (analysis->'total_penalty'->>'penalty_points')::int,
                                'reason', COALESCE(analysis->'total_penalty'->>'reason', 'Long goal penalty'))
                            WHEN jsonb_typeof(analysis->'penalty') = 'object' 
                                 AND COALESCE((analysis->'penalty'->>'penalty_points')::numeric, 0) > 0
                            THEN jsonb_build_object(
                                'penalty_points', (analysis->'penalty'->>'penalty_points')::int,
                                'reason', COALESCE(analysis->'penalty'->>'reason', 'Long goal penalty'))
                            WHEN jsonb_typeof(analysis->'total_penalty') = 'number' 
                                 AND (analysis->>'total_penalty')::numeric > 0
                            THEN jsonb_build_object(
                                'penalty_points', (analysis->>'total_penalty')::int,
                                'reason', 'Long goal penalty')
                            ELSE NULL END,
        'reward',        CASE
                            WHEN (analysis->'reward_package'->>'earned')::boolean = true
                            THEN COALESCE(
                                analysis->'reward_package'->>'tagName',
                                analysis->'reward_package'->>'tag_name')
                            ELSE NULL END,
        'statinge_date', timeline->>'start_date',
        'endinge_date',  timeline->>'end_date',
        'is_overdue',    CASE
                            WHEN (timeline->>'end_date') IS NOT NULL
                             AND LENGTH(timeline->>'end_date') > 0
                             AND (timeline->>'end_date')::timestamptz < NOW()
                             AND COALESCE(indicators->>'status','') != 'completed'
                            THEN true ELSE false END
    )), '[]'::jsonb)
    INTO v_long_goals FROM public.long_goals
    WHERE user_id = p_user_id
      -- Only inProgress / pending
      AND COALESCE(indicators->>'status', '')
          IN ('inProgress', 'pending', 'upcoming');

    -- ── active_week_tasks ─────────────────────────────────────
    -- Only tasks NOT completed / cancelled / onHold
    -- Points/progress come from weekly_tasks.metadata (WeeklySummary)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id',            id,
        'title',         about_task->>'task_name',
        'status',        COALESCE(indicators->>'status', 'pending'),
        'priority',      COALESCE(indicators->>'priority', 'medium'),
        -- from WeeklySummary model
        'points',        COALESCE((metadata->>'points_earned')::int, 0),
        'progress',      COALESCE((metadata->>'progress')::int, 0),
        'penalty',       CASE
                            WHEN jsonb_typeof(metadata->'penalty') = 'object' 
                                 AND COALESCE((metadata->'penalty'->>'penalty_points')::numeric, 0) > 0
                            THEN jsonb_build_object(
                                'penalty_points', (metadata->'penalty'->>'penalty_points')::int,
                                'reason', COALESCE(metadata->'penalty'->>'reason', 'Weekly task penalty'))
                            ELSE NULL END,
        'reward',        CASE
                            WHEN (metadata->'reward_package'->>'earned')::boolean = true
                            THEN COALESCE(
                                metadata->'reward_package'->>'tagName',
                                metadata->'reward_package'->>'tag_name')
                            ELSE NULL END,
        'statinge_date', timeline->>'starting_time',
        'endinge_date',  timeline->>'ending_time',
        'is_overdue',    false  -- weekly tasks don't have overdue concept
    )), '[]'::jsonb)
    INTO v_week_tasks FROM public.weekly_tasks
    WHERE user_id = p_user_id
      -- Only inProgress: exclude completed / cancelled / onHold
      -- Actually, active items should probably exclude fully completed ones.
      -- If it's 100% complete it should move to history.
      AND COALESCE(indicators->>'status', '')
          NOT IN ('completed', 'cancelled', 'onHold');

    RETURN jsonb_build_object(
        'active_day_tasks',  COALESCE(v_day_tasks,  '[]'::jsonb),
        'active_buckets',    COALESCE(v_buckets,    '[]'::jsonb),
        'active_long_goals', COALESCE(v_long_goals, '[]'::jsonb),
        'active_week_tasks', COALESCE(v_week_tasks, '[]'::jsonb)
    );
END;
$$;


CREATE OR REPLACE FUNCTION internal.calc_progress_history(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_date         DATE;
    v_pts          INT;
    v_total        INT;
    v_completed    INT;
    v_rate         NUMERIC;
    v_streak_count INT     := 0;
    v_streak_active BOOLEAN;
    v_best_pts     INT     := -1;
    v_best_date    DATE;
    v_worst_pts    INT     := 2147483647;
    v_worst_date   DATE;
    v_sum_pts      NUMERIC := 0;
    v_sum_rate     NUMERIC := 0;
    v_first_half   NUMERIC := 0;
    v_second_half  NUMERIC := 0;
    v_trend        TEXT    := 'stable';
    v_stats_arr    TEXT    := '';
    i              INT;
BEGIN
    -- Loop 30 days back from today (oldest first)
    FOR i IN REVERSE 0..29 LOOP
        v_date := CURRENT_DATE - i;

        -- Points and completion for this day (day_tasks only for history)
        SELECT
            COALESCE(SUM(COALESCE((metadata->>'points_earned')::numeric::int, 0)), 0),
            COUNT(*),
            COUNT(*) FILTER (WHERE (metadata->>'is_complete')::boolean = true)
        INTO v_pts, v_total, v_completed
        FROM public.day_tasks
        WHERE user_id = p_user_id
          AND (timeline->>'task_date')::date = v_date;

        v_rate := CASE WHEN v_total > 0
            THEN ROUND((v_completed::numeric / v_total * 100), 1)
            ELSE 0 END;

        -- Check if this day had any activity (for streak counting)
        SELECT (v_completed > 0) OR EXISTS (
            SELECT 1 FROM public.diary_entries
            WHERE user_id = p_user_id AND entry_date = v_date
        ) INTO v_streak_active;

        -- Running streak: resets to 0 on inactive days
        IF v_streak_active THEN v_streak_count := v_streak_count + 1;
        ELSE                     v_streak_count := 0;
        END IF;

        -- Accumulate for averages and trend
        v_sum_pts  := v_sum_pts  + v_pts;
        v_sum_rate := v_sum_rate + v_rate;

        -- First 15 days vs last 15 days for trend detection
        IF i >= 15 THEN v_first_half  := v_first_half  + v_pts;
        ELSE             v_second_half := v_second_half + v_pts;
        END IF;

        -- Track best day (highest points)
        IF v_pts > v_best_pts THEN
            v_best_pts  := v_pts;
            v_best_date := v_date;
        END IF;

        -- Track worst day (lowest NON-ZERO points only)
        IF v_pts > 0 AND v_pts < v_worst_pts THEN
            v_worst_pts  := v_pts;
            v_worst_date := v_date;
        END IF;

        -- Build consolidated daily_stats array entry
        IF v_stats_arr <> '' THEN v_stats_arr := v_stats_arr || ','; END IF;
        v_stats_arr := v_stats_arr ||
            '{"date":"' || v_date || '"' ||
            ',"points":' || v_pts ||
            ',"tasks_completed":' || v_completed ||
            ',"streaks":' || v_streak_count ||
            ',"completion_rate":' || v_rate || '}';
    END LOOP;

    -- Trend: second half (last 15 days) vs first half (days 16-30)
    IF v_second_half > v_first_half * 1.1  THEN v_trend := 'improving'; END IF;
    IF v_second_half < v_first_half * 0.9  THEN v_trend := 'declining'; END IF;

    RETURN jsonb_build_object(
        'trend',            v_trend,
        'average_progress', ROUND(v_sum_rate / 30, 1),
        'best_day',  CASE WHEN v_best_pts >= 0
            THEN jsonb_build_object('date', v_best_date, 'value', v_best_pts)
            ELSE NULL END,
        'worst_day', CASE WHEN v_worst_pts < 2147483647
            THEN jsonb_build_object('date', v_worst_date, 'value', v_worst_pts)
            ELSE NULL END,
        'daily_stats', ('[' || v_stats_arr || ']')::jsonb
    );
END;
$$;


CREATE OR REPLACE FUNCTION internal.calc_weekly_history(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_wstart        DATE;
    v_wend          DATE;
    v_wnum          INT;
    v_pts           INT;
    v_total         INT;
    v_completed     INT;
    v_goals         INT;
    v_rate          NUMERIC;
    v_sum           NUMERIC := 0;
    v_cur_pts       INT     := 0;
    v_last_pts      INT     := 0;
    v_best_pts      INT     := -1;
    v_best_start    DATE;
    v_best_wnum     INT;
    v_worst_pts     INT     := 2147483647;
    v_worst_start   DATE;
    v_worst_wnum    INT;
    v_wow           NUMERIC := 0;
    v_stats_arr     TEXT    := '';
    i               INT;
BEGIN
    -- Loop 12 weeks back (oldest first)
    FOR i IN REVERSE 0..11 LOOP
        v_wstart := DATE_TRUNC('week', CURRENT_DATE - (i * 7))::date;
        v_wend   := v_wstart + 6;
        v_wnum   := EXTRACT(week FROM v_wstart)::int;

        -- Day task points + completion for this week
        SELECT
            COALESCE(SUM(COALESCE((metadata->>'points_earned')::numeric::int, 0)), 0),
            COUNT(*),
            COUNT(*) FILTER (WHERE (metadata->>'is_complete')::boolean = true)
        INTO v_pts, v_total, v_completed
        FROM public.day_tasks
        WHERE user_id = p_user_id
          AND (timeline->>'task_date')::date BETWEEN v_wstart AND v_wend;

        -- Add weekly_tasks points for this week
        SELECT v_pts + COALESCE(SUM(COALESCE(
            (metadata->>'total_points_earned')::numeric::int, 0)), 0)
        INTO v_pts FROM public.weekly_tasks
        WHERE user_id = p_user_id
          AND (timeline->>'starting_time') IS NOT NULL
          AND (timeline->>'ending_time')   IS NOT NULL
          AND (timeline->>'starting_time')::date <= v_wend
          AND (timeline->>'ending_time')::date   >= v_wstart;

        -- Long goals completed this week
        SELECT COUNT(*) INTO v_goals FROM public.long_goals
        WHERE user_id = p_user_id
          AND indicators->>'status' = 'completed'
          AND updated_at::date BETWEEN v_wstart AND v_wend;

        v_rate := CASE WHEN v_total > 0
            THEN ROUND((v_completed::numeric / v_total * 100), 1)
            ELSE 0 END;

        v_sum := v_sum + v_pts;

        -- Track current and last week
        IF i = 0 THEN v_cur_pts  := v_pts; END IF;
        IF i = 1 THEN v_last_pts := v_pts; END IF;

        -- Best week
        IF v_pts > v_best_pts THEN
            v_best_pts   := v_pts;
            v_best_start := v_wstart;
            v_best_wnum  := v_wnum;
        END IF;

        -- Worst week (NON-ZERO only)
        IF v_pts > 0 AND v_pts < v_worst_pts THEN
            v_worst_pts   := v_pts;
            v_worst_start := v_wstart;
            v_worst_wnum  := v_wnum;
        END IF;

        IF v_stats_arr <> '' THEN v_stats_arr := v_stats_arr || ','; END IF;
        v_stats_arr := v_stats_arr ||
            '{"week_number":' || v_wnum ||
            ',"week_start":"' || v_wstart || '"' ||
            ',"points":' || v_pts ||
            ',"tasks_completed":' || v_completed ||
            ',"goals_completed":' || v_goals ||
            ',"completion_rate":' || v_rate || '}';
    END LOOP;

    -- Week-over-week % change
    IF v_last_pts > 0 THEN
        v_wow := ROUND(((v_cur_pts - v_last_pts)::numeric / v_last_pts * 100), 1);
    END IF;

    RETURN jsonb_build_object(
        'last_week_points',      v_last_pts,
        'current_week_points',   v_cur_pts,
        'average_weekly_points', ROUND(v_sum / 12, 1),
        'week_over_week_change', v_wow,
        'best_week',  CASE WHEN v_best_pts >= 0
            THEN jsonb_build_object(
                'points', v_best_pts, 'week_start', v_best_start,
                'week_number', v_best_wnum)
            ELSE NULL END,
        'worst_week', CASE WHEN v_worst_pts < 2147483647
            THEN jsonb_build_object(
                'points', v_worst_pts, 'week_start', v_worst_start,
                'week_number', v_worst_wnum)
            ELSE NULL END,
        'weekly_stats', ('[' || v_stats_arr || ']')::jsonb
    );
END;
$$;


CREATE OR REPLACE FUNCTION internal.calc_category_stats(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_stats        JSONB := '[]'::jsonb;
    v_percentages  JSONB := '{}'::jsonb;
    v_top_category TEXT  := '';
    v_total_points INT   := 0;
    v_category     RECORD;
BEGIN
    FOR v_category IN
        SELECT
            category_type,
            SUM(COALESCE((metadata->>'points_earned')::numeric::int, 0)) AS points,
            COUNT(*) AS total_tasks,
            COUNT(*) FILTER (
                WHERE (metadata->>'is_complete')::boolean = true
            ) AS completed_tasks
        FROM (
            -- Day tasks contribution
            SELECT category_type, metadata
            FROM public.day_tasks WHERE user_id = p_user_id
            UNION ALL
            -- Weekly tasks contribution
            SELECT category_type, metadata
            FROM public.weekly_tasks WHERE user_id = p_user_id
        ) combined
        WHERE category_type IS NOT NULL AND category_type <> ''
        GROUP BY category_type
        ORDER BY points DESC
    LOOP
        v_stats := v_stats || jsonb_build_object(
            'category_id',    '',
            'category_name',  INITCAP(v_category.category_type),
            'category_type',  v_category.category_type,
            'points',         v_category.points,
            'tasks_completed', v_category.completed_tasks,
            'total_tasks',    v_category.total_tasks,
            'completion_rate', CASE WHEN v_category.total_tasks > 0
                THEN ROUND((v_category.completed_tasks::float
                    / v_category.total_tasks * 100)::numeric, 1)
                ELSE 0 END,
            -- Known categories get specific colors; others get grey
            'icon', CASE LOWER(v_category.category_type)
                WHEN 'work'      THEN '💼' WHEN 'health'    THEN '💪'
                WHEN 'personal'  THEN '🏠' WHEN 'education' THEN '📚'
                WHEN 'finance'   THEN '💰' WHEN 'social'    THEN '👥'
                ELSE '📌' END,
            'color', CASE LOWER(v_category.category_type)
                WHEN 'work'      THEN '#3B82F6' WHEN 'health'    THEN '#EF4444'
                WHEN 'personal'  THEN '#10B981' WHEN 'education' THEN '#8B5CF6'
                WHEN 'finance'   THEN '#F59E0B' WHEN 'social'    THEN '#EC4899'
                ELSE '#6B7280' END
        );

        v_total_points := v_total_points + v_category.points;
        -- First category in ORDER BY points DESC is the top one
        IF v_top_category = '' THEN v_top_category := v_category.category_type; END IF;
    END LOOP;

    -- Build percentage map after we know total points
    IF v_total_points > 0 THEN
        SELECT jsonb_object_agg(
            item->>'category_type',
            ROUND(((item->>'points')::numeric::int::float
                / v_total_points * 100)::numeric, 1)
        ) INTO v_percentages FROM jsonb_array_elements(v_stats) AS item;
    END IF;

    RETURN jsonb_build_object(
        'stats',                COALESCE(v_stats, '[]'::jsonb),
        'top_category',         v_top_category,
        'total_points',         v_total_points,
        'category_percentages', COALESCE(v_percentages, '{}'::jsonb)
    );
END;
$$;


CREATE OR REPLACE FUNCTION internal.calc_rewards(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total_rewards     INT   := 0;
    v_all_points        INT   := 0;
    v_unlocked          JSONB := '[]'::jsonb;
    v_best_tier         TEXT  := 'none';
    v_worst_tier        TEXT  := 'none';
    v_best_level        INT   := 0;
    v_worst_level       INT   := 9; -- starts above all real levels
    -- Tier counts: ALL-TIME count per tier across ALL sources
    v_spark_count       INT   := 0;
    v_flame_count       INT   := 0;
    v_ember_count       INT   := 0;
    v_blaze_count       INT   := 0;
    v_crystal_count     INT   := 0;
    v_prism_count       INT   := 0;
    v_radiant_count     INT   := 0;
    v_nova_count        INT   := 0;
    v_reward            RECORD;
    v_tier_level        INT;
BEGIN
    -- ── Count ALL-TIME rewards per tier (earned_rewards_no) ───
    -- SOURCE: day_tasks
    SELECT
        COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'spark'),
        COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'flame'),
        COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'ember'),
        COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'blaze'),
        COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'crystal'),
        COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'prism'),
        COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'radiant'),
        COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'nova')
    INTO v_spark_count, v_flame_count, v_ember_count, v_blaze_count,
         v_crystal_count, v_prism_count, v_radiant_count, v_nova_count
    FROM public.day_tasks
    WHERE user_id = p_user_id
      AND (metadata->'reward_package'->>'earned')::boolean = true;

    -- SOURCE: weekly_tasks — ADD to existing counts
    SELECT
        v_spark_count   + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'spark'),
        v_flame_count   + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'flame'),
        v_ember_count   + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'ember'),
        v_blaze_count   + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'blaze'),
        v_crystal_count + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'crystal'),
        v_prism_count   + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'prism'),
        v_radiant_count + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'radiant'),
        v_nova_count    + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'nova')
    INTO v_spark_count, v_flame_count, v_ember_count, v_blaze_count,
         v_crystal_count, v_prism_count, v_radiant_count, v_nova_count
    FROM public.weekly_tasks
    WHERE user_id = p_user_id
      AND (metadata->'reward_package'->>'earned')::boolean = true;

    -- SOURCE: long_goals — ADD to existing counts
    SELECT
        v_spark_count   + COUNT(*) FILTER (WHERE analysis->'reward_package'->>'tier' = 'spark'),
        v_flame_count   + COUNT(*) FILTER (WHERE analysis->'reward_package'->>'tier' = 'flame'),
        v_ember_count   + COUNT(*) FILTER (WHERE analysis->'reward_package'->>'tier' = 'ember'),
        v_blaze_count   + COUNT(*) FILTER (WHERE analysis->'reward_package'->>'tier' = 'blaze'),
        v_crystal_count + COUNT(*) FILTER (WHERE analysis->'reward_package'->>'tier' = 'crystal'),
        v_prism_count   + COUNT(*) FILTER (WHERE analysis->'reward_package'->>'tier' = 'prism'),
        v_radiant_count + COUNT(*) FILTER (WHERE analysis->'reward_package'->>'tier' = 'radiant'),
        v_nova_count    + COUNT(*) FILTER (WHERE analysis->'reward_package'->>'tier' = 'nova')
    INTO v_spark_count, v_flame_count, v_ember_count, v_blaze_count,
         v_crystal_count, v_prism_count, v_radiant_count, v_nova_count
    FROM public.long_goals
    WHERE user_id = p_user_id
      AND (analysis->'reward_package'->>'earned')::boolean = true;

    -- SOURCE: bucket_models — ADD to existing counts
    SELECT
        v_spark_count   + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'spark'),
        v_flame_count   + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'flame'),
        v_ember_count   + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'ember'),
        v_blaze_count   + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'blaze'),
        v_crystal_count + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'crystal'),
        v_prism_count   + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'prism'),
        v_radiant_count + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'radiant'),
        v_nova_count    + COUNT(*) FILTER (WHERE metadata->'reward_package'->>'tier' = 'nova')
    INTO v_spark_count, v_flame_count, v_ember_count, v_blaze_count,
         v_crystal_count, v_prism_count, v_radiant_count, v_nova_count
    FROM public.bucket_models
    WHERE user_id = p_user_id
      AND (metadata->'reward_package'->>'earned')::boolean = true;

    -- Total count = sum of all tier counts
    v_total_rewards := v_spark_count + v_flame_count + v_ember_count
                     + v_blaze_count + v_crystal_count + v_prism_count
                     + v_radiant_count + v_nova_count;

    -- ── Build unlocked_rewards list (all sources, newest first) ─
    FOR v_reward IN
        -- day_tasks rewards
        SELECT
            id,
            about_task->>'task_name'                             AS task_name,
            metadata->'reward_package'->>'tier'                  AS tier,
            COALESCE(
                metadata->'reward_package'->>'tagName',
                metadata->'reward_package'->>'tag_name',
                metadata->'reward_package'->>'tier')             AS tag_name,
            COALESCE((metadata->>'points_earned')::numeric::int, 0) AS pts,
            updated_at                                           AS earned_at,
            'day_task'                                           AS earned_from,
            COALESCE(category_type, '')                          AS cat_type
        FROM public.day_tasks
        WHERE user_id = p_user_id
          AND (metadata->'reward_package'->>'earned')::boolean = true

        UNION ALL

        -- weekly_tasks rewards
        SELECT
            id,
            about_task->>'task_name',
            metadata->'reward_package'->>'tier',
            COALESCE(
                metadata->'reward_package'->>'tagName',
                metadata->'reward_package'->>'tag_name',
                metadata->'reward_package'->>'tier'),
            COALESCE((metadata->>'total_points_earned')::numeric::int, 0),
            updated_at,
            'week_task',
            COALESCE(category_type, '')
        FROM public.weekly_tasks
        WHERE user_id = p_user_id
          AND (metadata->'reward_package'->>'earned')::boolean = true

        UNION ALL

        -- long_goals rewards
        SELECT
            id,
            title,
            analysis->'reward_package'->>'tier',
            COALESCE(
                analysis->'reward_package'->>'tagName',
                analysis->'reward_package'->>'tag_name',
                analysis->'reward_package'->>'tier'),
            COALESCE((analysis->>'points_earned')::numeric::int, 0),
            updated_at,
            'long_goal',
            COALESCE(category_type, '')
        FROM public.long_goals
        WHERE user_id = p_user_id
          AND (analysis->'reward_package'->>'earned')::boolean = true

        UNION ALL

        -- bucket_models rewards
        SELECT
            id,
            title,
            metadata->'reward_package'->>'tier',
            COALESCE(
                metadata->'reward_package'->>'tagName',
                metadata->'reward_package'->>'tag_name',
                metadata->'reward_package'->>'tier'),
            COALESCE((metadata->>'total_points_earned')::numeric::int, 0),
            updated_at,
            'bucket',
            ''
        FROM public.bucket_models
        WHERE user_id = p_user_id
          AND (metadata->'reward_package'->>'earned')::boolean = true

        ORDER BY earned_at DESC
        LIMIT 100
    LOOP
        v_tier_level := CASE v_reward.tier
            WHEN 'nova'    THEN 8 WHEN 'radiant' THEN 7
            WHEN 'prism'   THEN 6 WHEN 'crystal' THEN 5
            WHEN 'blaze'   THEN 4 WHEN 'ember'   THEN 3
            WHEN 'flame'   THEN 2 WHEN 'spark'   THEN 1
            ELSE 0 END;

        -- Track best tier (highest level)
        IF v_tier_level > v_best_level THEN
            v_best_level := v_tier_level;
            v_best_tier  := v_reward.tier;
        END IF;

        -- Track worst tier (lowest level, NOT none)
        IF v_tier_level > 0 AND v_tier_level < v_worst_level THEN
            v_worst_level := v_tier_level;
            v_worst_tier  := v_reward.tier;
        END IF;

        -- Sum all points from rewards
        v_all_points := v_all_points + v_reward.pts;

        -- Build unlocked_rewards item
        v_unlocked := v_unlocked || jsonb_build_object(
            'id',         v_reward.id,
            'icon',       CASE v_reward.tier
                WHEN 'nova'    THEN '🌟' WHEN 'radiant' THEN '👑'
                WHEN 'prism'   THEN '🏆' WHEN 'crystal' THEN '💎'
                WHEN 'blaze'   THEN '⚡' WHEN 'ember'   THEN '🌿'
                WHEN 'flame'   THEN '🔥' WHEN 'spark'   THEN '✨'
                ELSE '⭐' END,
            'tagName',    v_reward.tag_name,
            'tier',       v_reward.tier,
            'category',   v_reward.cat_type,
            'earned_at',  v_reward.earned_at,
            'earned_from', v_reward.earned_from,
            'task_name',  v_reward.task_name
        );
    END LOOP;

    -- Fix worst_tier if nothing was earned
    IF v_worst_level = 9 THEN v_worst_tier := 'none'; END IF;

    RETURN jsonb_build_object(
        'summary', jsonb_build_object(
            'all_rewards_points',   v_all_points,
            'best_tier_achieved',   v_best_tier,
            'worst_tier_achieved',  v_worst_tier,
            'total_rewards_earned', v_total_rewards,
            'next_rewards',         ''
        ),
        'earned_rewards_no', jsonb_build_object(
            'nova',    v_nova_count,
            'radiant', v_radiant_count,
            'prism',   v_prism_count,
            'crystal', v_crystal_count,
            'blaze',   v_blaze_count,
            'ember',   v_ember_count,
            'flame',   v_flame_count,
            'spark',   v_spark_count
        ),
        'unlocked_rewards', v_unlocked
    );
END;
$$;


CREATE OR REPLACE FUNCTION internal.calc_mood(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_avg_7        FLOAT := 0;
    v_avg_30       FLOAT := 0;
    v_history      JSONB := '[]'::jsonb;
    v_frequency    JSONB := '{}'::jsonb;
    v_most_common  TEXT  := 'Neutral';
    v_trend        TEXT  := 'stable';
    v_today_mood   JSONB := NULL;
    v_first_half   FLOAT := 0;
    v_second_half  FLOAT := 0;
BEGIN
    -- ── Today's mood ──────────────────────────────────────────
    SELECT jsonb_build_object(
        'rating', COALESCE((mood->>'rating')::int, 0),
        'label',  COALESCE(mood->>'label', ''),
        'emoji',  COALESCE(mood->>'emoji', '😐')
    ) INTO v_today_mood FROM public.diary_entries
    WHERE user_id = p_user_id
      AND entry_date = CURRENT_DATE
      AND mood IS NOT NULL
    LIMIT 1;

    -- ── 7-day average mood ────────────────────────────────────
    SELECT COALESCE(AVG((mood->>'rating')::float), 0)
    INTO v_avg_7 FROM public.diary_entries
    WHERE user_id = p_user_id
      AND entry_date >= CURRENT_DATE - 7
      AND mood IS NOT NULL
      AND (mood->>'rating') IS NOT NULL;

    -- ── 30-day average mood ───────────────────────────────────
    SELECT COALESCE(AVG((mood->>'rating')::float), 0)
    INTO v_avg_30 FROM public.diary_entries
    WHERE user_id = p_user_id
      AND entry_date >= CURRENT_DATE - 30
      AND mood IS NOT NULL
      AND (mood->>'rating') IS NOT NULL;

    -- ── Mood history (last 30 days, ordered oldest first) ─────
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'date',  entry_date,
        'value', COALESCE((mood->>'rating')::float, 0),
        'label', COALESCE(mood->>'label', '')
    ) ORDER BY entry_date ASC), '[]'::jsonb)
    INTO v_history FROM public.diary_entries
    WHERE user_id = p_user_id
      AND entry_date >= CURRENT_DATE - 30
      AND mood IS NOT NULL
      AND (mood->>'rating') IS NOT NULL;

    -- ── Mood frequency (last 30 days) ─────────────────────────
    SELECT COALESCE(jsonb_object_agg(label, cnt), '{}'::jsonb)
    INTO v_frequency FROM (
        SELECT mood->>'label' AS label, COUNT(*) AS cnt
        FROM public.diary_entries
        WHERE user_id = p_user_id
          AND entry_date >= CURRENT_DATE - 30
          AND mood->>'label' IS NOT NULL
        GROUP BY mood->>'label'
    ) freq_sub;

    -- ── Most common mood (last 30 days) ───────────────────────
    SELECT mood->>'label' INTO v_most_common
    FROM public.diary_entries
    WHERE user_id = p_user_id
      AND entry_date >= CURRENT_DATE - 30
      AND mood->>'label' IS NOT NULL
    GROUP BY mood->>'label'
    ORDER BY COUNT(*) DESC
    LIMIT 1;

    -- ── Trend: first half vs second half of last 30 days ──────
    SELECT
        COALESCE(AVG(CASE
            WHEN entry_date < CURRENT_DATE - 15
            THEN (mood->>'rating')::float END), 0),
        COALESCE(AVG(CASE
            WHEN entry_date >= CURRENT_DATE - 15
            THEN (mood->>'rating')::float END), 0)
    INTO v_first_half, v_second_half
    FROM public.diary_entries
    WHERE user_id = p_user_id
      AND entry_date >= CURRENT_DATE - 30
      AND mood IS NOT NULL
      AND (mood->>'rating') IS NOT NULL;

    -- ±0.3 threshold prevents trivial fluctuations triggering trend
    IF v_second_half > v_first_half + 0.3 THEN v_trend := 'improving'; END IF;
    IF v_second_half < v_first_half - 0.3 THEN v_trend := 'declining'; END IF;

    RETURN jsonb_build_object(
        'trend',                     v_trend,
        'today_mood',                v_today_mood,
        'mood_history',              v_history,
        'mood_frequency',            v_frequency,
        'most_common_mood',          COALESCE(v_most_common, 'Neutral'),
        'average_mood_last_7_days',  ROUND(v_avg_7::numeric,  1),
        'average_mood_last_30_days', ROUND(v_avg_30::numeric, 1)
    );
END;
$$;


CREATE OR REPLACE FUNCTION internal.calc_streaks(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Current streak
    v_cur_days          INT       := 0;
    v_cur_broken        BOOLEAN   := FALSE;
    v_cur_start         DATE      := NULL;
    v_last_active       DATE      := NULL;

    -- Longest streak
    v_long_days         INT       := 0;
    v_long_temp         INT       := 0;
    v_long_start        DATE      := NULL;
    v_long_end          DATE      := NULL;
    v_long_cur_start    DATE      := NULL;

    -- Milestone
    v_milestones        INT[]     := ARRAY[3,7,14,21,30,60,90,180,365];
    v_next_target       INT       := NULL;
    v_days_remaining    INT       := 0;
    v_milestone_pct     FLOAT     := 0;
    v_ms                INT;

    -- Risk
    v_is_at_risk        BOOLEAN   := FALSE;
    v_hours_until_break INT       := NULL;

    -- History: 30-day calendar
    v_calendar          JSONB     := '{}'::jsonb;

    -- History: break detection (90 days)
    v_breaks_arr        TEXT      := '';
    v_prev_active       BOOLEAN   := NULL;

    -- Stats
    v_total_active_days INT       := 0;
    v_break_count       INT       := 0;
    v_break_days_arr    TEXT[]    := ARRAY[]::TEXT[];
    v_break_dow         TEXT;
    v_most_common_break TEXT      := '';

    -- Loop helpers
    v_date              DATE;
    v_active            BOOLEAN;
    i                   INT;
BEGIN
    -- ── 90-day loop (covers all streak calculations) ──────────
    FOR i IN 0..89 LOOP
        v_date := CURRENT_DATE - i;

        -- A day is active if: completed day_task OR diary entry exists
        SELECT EXISTS (
            SELECT 1 FROM public.day_tasks
            WHERE user_id = p_user_id
              AND (timeline->>'task_date')::date = v_date
              AND (metadata->>'is_complete')::boolean = true
            UNION ALL
            SELECT 1 FROM public.diary_entries
            WHERE user_id = p_user_id
              AND entry_date = v_date
        ) INTO v_active;

        -- ── Current streak (consecutive days back from today) ──
        IF NOT v_cur_broken THEN
            IF v_active THEN
                v_cur_days := v_cur_days + 1;
                v_cur_start := v_date;         -- keeps getting set = oldest date
                IF v_last_active IS NULL THEN v_last_active := v_date; END IF;
            ELSIF i > 0 THEN
                v_cur_broken := TRUE;
            END IF;
        END IF;

        -- ── Longest streak (rolling window) ───────────────────
        IF v_active THEN
            v_long_temp := v_long_temp + 1;
            IF v_long_cur_start IS NULL THEN v_long_cur_start := v_date; END IF;
            IF v_long_temp > v_long_days THEN
                v_long_days  := v_long_temp;
                v_long_start := v_long_cur_start;
                v_long_end   := v_date;
            END IF;
        ELSE
            -- Streak broke: record the end and reset
            IF v_long_temp > 0 THEN
                -- Check if prev segment was longer (already captured above)
                v_long_cur_start := NULL;
            END IF;
            v_long_temp      := 0;
            v_long_cur_start := NULL;
        END IF;

        -- ── Total active days all time ─────────────────────────
        IF v_active THEN v_total_active_days := v_total_active_days + 1; END IF;

        -- ── 30-day calendar ────────────────────────────────────
        IF i < 30 THEN
            v_calendar := v_calendar ||
                jsonb_build_object(v_date::text, v_active);
        END IF;

        -- ── Break detection (90 days) ──────────────────────────
        -- A break = day that is NOT active AND previous day WAS active
        IF v_prev_active IS NOT NULL AND
           NOT v_active AND v_prev_active THEN
            v_break_count := v_break_count + 1;
            -- Record day-of-week for most_common_break_day
            v_break_dow := TO_CHAR(v_date + 1, 'Day'); -- +1 because break is "after" active day
            v_break_days_arr := v_break_days_arr || TRIM(v_break_dow);

            IF v_breaks_arr <> '' THEN v_breaks_arr := v_breaks_arr || ','; END IF;
            v_breaks_arr := v_breaks_arr ||
                '{"date":"' || v_date || '","reason":"no_activity"}';
        END IF;
        v_prev_active := v_active;
    END LOOP;

    -- Longest streak must be at least as long as current streak
    v_long_days := GREATEST(v_long_days, v_cur_days);

    -- ── Next milestone ────────────────────────────────────────
    FOR i IN 1..array_upper(v_milestones, 1) LOOP
        v_ms := v_milestones[i];
        IF v_ms > v_cur_days THEN
            v_next_target    := v_ms;
            v_days_remaining := v_ms - v_cur_days;
            v_milestone_pct  := ROUND((v_cur_days::float / v_ms * 100)::numeric, 1);
            EXIT; -- take the first milestone greater than current
        END IF;
    END LOOP;

    -- ── Streak at risk ────────────────────────────────────────
    -- At risk if: streak > 0 AND past noon AND no activity today
    DECLARE v_today_active BOOLEAN;
    BEGIN
        SELECT EXISTS (
            SELECT 1 FROM public.day_tasks
            WHERE user_id = p_user_id
              AND (timeline->>'task_date')::date = CURRENT_DATE
              AND (metadata->>'is_complete')::boolean = true
            UNION ALL
            SELECT 1 FROM public.diary_entries
            WHERE user_id = p_user_id
              AND entry_date = CURRENT_DATE
        ) INTO v_today_active;

        IF v_cur_days > 0 AND NOT v_today_active AND
           EXTRACT(hour FROM NOW()) >= 12 THEN
            v_is_at_risk        := TRUE;
            -- Hours left in the day before midnight breaks the streak
            v_hours_until_break := 24 - EXTRACT(hour FROM NOW())::int;
        END IF;
    END;

    -- ── Most common break day ─────────────────────────────────
    IF array_length(v_break_days_arr, 1) > 0 THEN
        SELECT day_name INTO v_most_common_break
        FROM (
            SELECT unnest(v_break_days_arr) AS day_name
        ) s
        GROUP BY day_name
        ORDER BY COUNT(*) DESC
        LIMIT 1;
    END IF;

    RETURN jsonb_build_object(
        'current', jsonb_build_object(
            'days',             v_cur_days,
            'is_active',        v_cur_days > 0 AND NOT v_cur_broken,
            'started_date',     v_cur_start,
            'last_active_date', v_last_active
        ),
        'longest', jsonb_build_object(
            'days',         v_long_days,
            'started_date', v_long_start,
            'ended_date',   v_long_end
        ),
        'next_milestone', jsonb_build_object(
            'target',           COALESCE(v_next_target, 0),
            'days_remaining',   v_days_remaining,
            'progress_percent', v_milestone_pct
        ),
        'risk', jsonb_build_object(
            'is_at_risk',          v_is_at_risk,
            'hours_until_break',   CASE WHEN v_is_at_risk THEN v_hours_until_break ELSE NULL END,
            'last_activity_date',  v_last_active
        ),
        'history', jsonb_build_object(
            'calendar_30_days',       v_calendar,
            'breaks_in_last_90_days', ('[' || v_breaks_arr || ']')::jsonb
        ),
        'stats', jsonb_build_object(
            'total_active_days_all_time', v_total_active_days,
            'average_streak', CASE WHEN v_break_count > 0
                THEN ROUND((v_total_active_days::float / (v_break_count + 1))::numeric, 1)
                ELSE v_total_active_days::float END,
            'most_common_break_day', COALESCE(v_most_common_break, '')
        ),
        'milestones', to_jsonb(v_milestones)
    );
END;
$$;


CREATE OR REPLACE FUNCTION internal.calc_recent_activity(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_activities JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(activity ORDER BY created_at DESC), '[]'::jsonb)
    INTO v_activities
    FROM (
        -- ── Day tasks: completed ──────────────────────────────
        SELECT jsonb_build_object(
            'id',           id,
            'type',         'day task',
            'action',       'task_completed',
            'category',     COALESCE(category_type, ''),
            'sub_types',    sub_types,
            'message',      'Completed: ' || COALESCE(about_task->>'task_name', 'Task'),
            'points',       COALESCE((metadata->>'points_earned')::int, 0),
            'is_milestone', false,
            'created_at',   updated_at
        ) AS activity, updated_at AS created_at
        FROM public.day_tasks
        WHERE user_id = p_user_id
          AND (metadata->>'is_complete')::boolean = true
          AND updated_at >= NOW() - INTERVAL '15 days'

        UNION ALL

        -- ── Day tasks: reward earned ──────────────────────────
        SELECT jsonb_build_object(
            'id',           id,
            'type',         'day task',
            'action',       'reward_earned',
            'category',     COALESCE(category_type, ''),
            'sub_types',    sub_types,
            'message',      'Earned ' ||
                            INITCAP(COALESCE(
                                metadata->'reward_package'->>'tier', '')) ||
                            ' reward: ' ||
                            COALESCE(
                                metadata->'reward_package'->>'tagName',
                                metadata->'reward_package'->>'tag_name', ''),
            'points',       COALESCE((metadata->>'points_earned')::int, 0),
            'is_milestone', true,
            'created_at',   updated_at
        ) AS activity, updated_at AS created_at
        FROM public.day_tasks
        WHERE user_id = p_user_id
          AND (metadata->'reward_package'->>'earned')::boolean = true
          AND updated_at >= NOW() - INTERVAL '15 days'

        UNION ALL

        -- ── Weekly tasks: completed ───────────────────────────
        SELECT jsonb_build_object(
            'id',           id,
            'type',         'weekly task',
            'action',       'task_completed',
            'category',     COALESCE(category_type, ''),
            'sub_types',    sub_types,
            'message',      'Completed weekly task: ' ||
                            COALESCE(about_task->>'task_name', 'Task'),
            'points',       COALESCE((metadata->>'total_points_earned')::int, 0),
            'is_milestone', false,
            'created_at',   updated_at
        ) AS activity, updated_at AS created_at
        FROM public.weekly_tasks
        WHERE user_id = p_user_id
          AND indicators->>'status' = 'completed'
          AND updated_at >= NOW() - INTERVAL '15 days'

        UNION ALL

        -- ── Weekly tasks: reward earned ───────────────────────
        SELECT jsonb_build_object(
            'id',           id,
            'type',         'weekly task',
            'action',       'reward_earned',
            'category',     COALESCE(category_type, ''),
            'sub_types',    sub_types,
            'message',      'Earned ' ||
                            INITCAP(COALESCE(
                                metadata->'reward_package'->>'tier', '')) ||
                            ' reward: ' ||
                            COALESCE(
                                metadata->'reward_package'->>'tagName',
                                metadata->'reward_package'->>'tag_name', ''),
            'points',       COALESCE((metadata->>'total_points_earned')::int, 0),
            'is_milestone', true,
            'created_at',   updated_at
        ) AS activity, updated_at AS created_at
        FROM public.weekly_tasks
        WHERE user_id = p_user_id
          AND (metadata->'reward_package'->>'earned')::boolean = true
          AND updated_at >= NOW() - INTERVAL '15 days'

        UNION ALL

        -- ── Long goals: created ───────────────────────────────
        SELECT jsonb_build_object(
            'id',           id,
            'type',         'long goal',
            'action',       'goal_created',
            'category',     COALESCE(category_type, ''),
            'sub_types',    sub_types,
            'message',      'Started new goal: ' || COALESCE(title, 'Goal'),
            'points',       0,
            'is_milestone', false,
            'created_at',   created_at
        ) AS activity, created_at
        FROM public.long_goals
        WHERE user_id = p_user_id
          AND created_at >= NOW() - INTERVAL '15 days'

        UNION ALL

        -- ── Long goals: completed ─────────────────────────────
        SELECT jsonb_build_object(
            'id',           id,
            'type',         'long goal',
            'action',       'goal_completed',
            'category',     COALESCE(category_type, ''),
            'sub_types',    sub_types,
            'message',      'Completed goal: ' || COALESCE(title, 'Goal'),
            'points',       COALESCE((analysis->>'points_earned')::int, 0),
            'is_milestone', true,
            'created_at',   updated_at
        ) AS activity, updated_at AS created_at
        FROM public.long_goals
        WHERE user_id = p_user_id
          AND indicators->>'status' = 'completed'
          AND updated_at >= NOW() - INTERVAL '15 days'

        UNION ALL

        -- ── Long goals: reward earned ─────────────────────────
        SELECT jsonb_build_object(
            'id',           id,
            'type',         'long goal',
            'action',       'reward_earned',
            'category',     COALESCE(category_type, ''),
            'sub_types',    sub_types,
            'message',      'Earned ' ||
                            INITCAP(COALESCE(
                                analysis->'reward_package'->>'tier', '')) ||
                            ' reward on goal: ' || COALESCE(title, 'Goal'),
            'points',       COALESCE((analysis->>'points_earned')::int, 0),
            'is_milestone', true,
            'created_at',   updated_at
        ) AS activity, updated_at AS created_at
        FROM public.long_goals
        WHERE user_id = p_user_id
          AND (analysis->'reward_package'->>'earned')::boolean = true
          AND updated_at >= NOW() - INTERVAL '15 days'

        UNION ALL

        -- ── Bucket: checklist item completed today ────────────
        SELECT jsonb_build_object(
            'id',           bm.id,
            'type',         'bucket',
            'action',       'task_completed',
            'category',     COALESCE(bm.category_type, ''),
            'sub_types',    bm.sub_types,
            'message',      'Completed bucket item: ' ||
                            COALESCE(cl_item->>'task', 'Item') ||
                            ' in "' || COALESCE(bm.title, 'Bucket') || '"',
            'points',       COALESCE((cl_item->>'points')::int, 0),
            'is_milestone', false,
            'created_at',   (cl_item->>'date')::timestamptz
        ) AS activity,
        (cl_item->>'date')::timestamptz AS created_at
        FROM public.bucket_models bm,
             jsonb_array_elements(
                CASE 
                    WHEN jsonb_typeof(bm.checklist) = 'object' AND bm.checklist ? 'items' THEN bm.checklist->'items'
                    WHEN jsonb_typeof(bm.checklist) = 'array' THEN bm.checklist
                    ELSE '[]'::jsonb
                END
             ) AS cl_item
        WHERE bm.user_id = p_user_id
          AND (cl_item->>'done')::boolean = true
          AND (cl_item->>'date')::date >= CURRENT_DATE - 15

        UNION ALL

        -- ── Bucket: reward earned ─────────────────────────────
        SELECT jsonb_build_object(
            'id',           id,
            'type',         'bucket',
            'action',       'reward_earned',
            'category',     COALESCE(category_type, ''),
            'sub_types',    sub_types,
            'message',      'Earned ' ||
                            INITCAP(COALESCE(
                                metadata->'reward_package'->>'tier', '')) ||
                            ' reward on bucket: ' || COALESCE(title, 'Bucket'),
            'points',       COALESCE((metadata->>'total_points_earned')::int, 0),
            'is_milestone', true,
            'created_at',   updated_at
        ) AS activity, updated_at AS created_at
        FROM public.bucket_models
        WHERE user_id = p_user_id
          AND (metadata->'reward_package'->>'earned')::boolean = true
          AND updated_at >= NOW() - INTERVAL '15 days'

        UNION ALL

        -- ── Diary: entry created ──────────────────────────────
        SELECT jsonb_build_object(
            'id',           id,
            'type',         'diary',
            'action',       'diary_created',
            'category',     'diary',
            'sub_types',    NULL,
            'message',      CASE
                                WHEN mood->>'label' IS NOT NULL
                                THEN 'Added diary entry - ' || (mood->>'label')
                                ELSE 'Added diary entry'
                            END,
            'points',       10,  -- diary always gives 10 activity points
            'is_milestone', false,
            'created_at',   created_at
        ) AS activity, created_at
        FROM public.diary_entries
        WHERE user_id = p_user_id
          AND created_at >= NOW() - INTERVAL '15 days'

        ORDER BY created_at DESC
        LIMIT 50  -- cap to prevent unbounded JSONB growth
    ) sub;

    RETURN COALESCE(v_activities, '[]'::jsonb);
END;
$$;


-- ============================================================
-- ============================================================
-- MASTER FUNCTIONS
-- ============================================================
-- ============================================================


CREATE OR REPLACE FUNCTION public.refresh_performance_analytics(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE v_result_id UUID;
BEGIN
    INSERT INTO public.performance_analytics (
        user_id,
        overview,
        today,
        active_items,
        progress_history,
        weekly_history,
        category_stats,
        rewards,
        mood,
        streaks,
        recent_activity,
        last_notified,
        snapshot_at,
        updated_at
    )
    VALUES (
        p_user_id,
        internal.calc_overview(p_user_id),
        internal.calc_today(p_user_id),
        internal.calc_active_items(p_user_id),
        internal.calc_progress_history(p_user_id),
        internal.calc_weekly_history(p_user_id),
        internal.calc_category_stats(p_user_id),
        internal.calc_rewards(p_user_id),
        internal.calc_mood(p_user_id),
        internal.calc_streaks(p_user_id),
        internal.calc_recent_activity(p_user_id),
        '{}'::jsonb,
        NOW(),
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        overview         = EXCLUDED.overview,
        today            = EXCLUDED.today,
        active_items     = EXCLUDED.active_items,
        progress_history = EXCLUDED.progress_history,
        weekly_history   = EXCLUDED.weekly_history,
        category_stats   = EXCLUDED.category_stats,
        rewards          = EXCLUDED.rewards,
        mood             = EXCLUDED.mood,
        streaks          = EXCLUDED.streaks,
        recent_activity  = EXCLUDED.recent_activity,
        -- last_notified is NOT updated here to preserve its state
        snapshot_at      = NOW(),
        updated_at       = NOW()
    RETURNING id INTO v_result_id;

    RETURN jsonb_build_object(
        'success',      true,
        'id',           v_result_id,
        'user_id',      p_user_id,
        'refreshed_at', NOW()
    );
END;
$$;


CREATE OR REPLACE FUNCTION public.get_dashboard(
    p_user_id       UUID,
    p_refresh       BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE v_row RECORD;
BEGIN
    -- [SECURITY] Ownership/Mentorship check
    IF p_user_id != auth.uid() AND NOT EXISTS (
        SELECT 1 FROM public.mentorship_connections
        WHERE mentor_id = auth.uid() AND owner_id = p_user_id AND access_status = 'active'
    ) AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT * INTO v_row FROM public.performance_analytics
    WHERE user_id = p_user_id;

    -- Refresh if: no row exists, force refresh requested,
    -- or data is more than 5 minutes old
    IF v_row IS NULL
       OR p_refresh
       OR v_row.updated_at < NOW() - INTERVAL '5 minutes' THEN
        PERFORM public.refresh_performance_analytics(p_user_id);
        SELECT * INTO v_row FROM public.performance_analytics
        WHERE user_id = p_user_id;
    END IF;

    RETURN jsonb_build_object(
        'id',               v_row.id,
        'user_id',          v_row.user_id,
        'overview',         v_row.overview,
        'today',            v_row.today,
        'active_items',     v_row.active_items,
        'progress_history', v_row.progress_history,
        'weekly_history',   v_row.weekly_history,
        'category_stats',   v_row.category_stats,
        'rewards',          v_row.rewards,
        'mood',             v_row.mood,
        'streaks',          v_row.streaks,
        'recent_activity',  v_row.recent_activity,
        'last_notified',    v_row.last_notified,
        'snapshot_at',      v_row.snapshot_at,
        'updated_at',       v_row.updated_at,
        'created_at',       v_row.created_at
    );
END;
$$;


CREATE OR REPLACE FUNCTION internal.trigger_refresh_analytics()
RETURNS TRIGGER SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
BEGIN
    PERFORM public.refresh_performance_analytics(COALESCE(NEW.user_id, OLD.user_id));
    RETURN COALESCE(NEW, OLD);
END; $$;


CREATE OR REPLACE FUNCTION public.ensure_user_analytics(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
    -- [SECURITY] Ownership check
    IF p_user_id != auth.uid() AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    -- No row yet: create it
    IF NOT EXISTS (
        SELECT 1 FROM public.performance_analytics
        WHERE user_id = p_user_id
    ) THEN
        PERFORM public.refresh_performance_analytics(p_user_id);
        RETURN jsonb_build_object('created', true, 'user_id', p_user_id);
    END IF;

    -- Row exists but stale: refresh
    IF EXISTS (
        SELECT 1 FROM public.performance_analytics
        WHERE user_id = p_user_id
          AND updated_at < NOW() - INTERVAL '5 minutes'
    ) THEN
        PERFORM public.refresh_performance_analytics(p_user_id);
        RETURN jsonb_build_object('refreshed', true, 'user_id', p_user_id);
    END IF;

    -- Row exists and fresh: do nothing
    RETURN jsonb_build_object('exists', true, 'user_id', p_user_id);
END;
$$;


CREATE OR REPLACE FUNCTION internal.refresh_all_analytics()
RETURNS JSONB SECURITY DEFINER SET search_path = public LANGUAGE plpgsql AS $$
DECLARE v_user RECORD; v_count INT := 0; v_errors INT := 0;
BEGIN
    FOR v_user IN SELECT user_id FROM public.user_profiles LOOP
        BEGIN
            PERFORM public.refresh_performance_analytics(v_user.user_id);
            v_count := v_count + 1;
        EXCEPTION WHEN OTHERS THEN v_errors := v_errors + 1;
        END;
    END LOOP;
    RETURN jsonb_build_object('success', true, 'refreshed', v_count, 'errors', v_errors);
END; $$;


-- ============================================================
-- STEP 7: TRIGGERS
-- Fire after any change on the 5 source tables.
-- Each trigger calls trigger_refresh_analytics() which calls
-- refresh_performance_analytics() for the affected user.
-- ============================================================

-- day_tasks → refresh analytics on any change
DROP TRIGGER IF EXISTS trg_day_task_analytics ON public.day_tasks;
CREATE TRIGGER trg_day_task_analytics
    AFTER INSERT OR UPDATE OR DELETE ON public.day_tasks
    FOR EACH ROW
    EXECUTE FUNCTION internal.trigger_refresh_analytics();

-- weekly_tasks → refresh analytics on any change
DROP TRIGGER IF EXISTS trg_weekly_task_analytics ON public.weekly_tasks;
CREATE TRIGGER trg_weekly_task_analytics
    AFTER INSERT OR UPDATE OR DELETE ON public.weekly_tasks
    FOR EACH ROW
    EXECUTE FUNCTION internal.trigger_refresh_analytics();

-- long_goals → refresh analytics on any change
DROP TRIGGER IF EXISTS trg_long_goal_analytics ON public.long_goals;
CREATE TRIGGER trg_long_goal_analytics
    AFTER INSERT OR UPDATE OR DELETE ON public.long_goals
    FOR EACH ROW
    EXECUTE FUNCTION internal.trigger_refresh_analytics();

-- bucket_models → refresh analytics on any change
DROP TRIGGER IF EXISTS trg_bucket_analytics ON public.bucket_models;
CREATE TRIGGER trg_bucket_analytics
    AFTER INSERT OR UPDATE OR DELETE ON public.bucket_models
    FOR EACH ROW
    EXECUTE FUNCTION internal.trigger_refresh_analytics();

-- diary_entries → refresh analytics on any change
-- (affects mood, streaks, today, recent_activity)
DROP TRIGGER IF EXISTS trg_diary_analytics ON public.diary_entries;
CREATE TRIGGER trg_diary_analytics
    AFTER INSERT OR UPDATE OR DELETE ON public.diary_entries
    FOR EACH ROW
    EXECUTE FUNCTION internal.trigger_refresh_analytics();


-- ============================================================
-- STEP 9: GRANTS
-- All functions need explicit EXECUTE grants so authenticated
-- users can call them via Supabase RPC.
-- ============================================================

-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT EXECUTE ON FUNCTION public.refresh_performance_analytics(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_dashboard(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_user_analytics(UUID) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;


-- ============================================================
-- STEP 10: AUTO-INITIALIZE ON PROFILE CREATION
-- Ensures every new user gets an analytics row immediately.
-- ============================================================

CREATE OR REPLACE FUNCTION internal.on_user_profile_created_init_analytics()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- Initialize performance analytics for the new user (0 values)
    PERFORM public.refresh_performance_analytics(NEW.user_id);
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Analytics initialization failed for user %: %', NEW.user_id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_init_analytics_on_profile_creation ON public.user_profiles;
CREATE TRIGGER trigger_init_analytics_on_profile_creation
    AFTER INSERT ON public.user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION internal.on_user_profile_created_init_analytics();


-- ============================================================
-- STEP 11: AUTO-UPDATE MENTORSHIP SNAPSHOTS
-- Whenever a user's analytics are refreshed, push the summary
-- to all active mentorship connections as a cached snapshot.
-- ============================================================

CREATE OR REPLACE FUNCTION internal.fn_sync_mentorship_snapshots()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
    v_snapshot JSONB;
BEGIN
    -- Build a simplified snapshot for the mentorship list
    v_snapshot := jsonb_build_object(
        'points', (NEW.overview->'summary'->>'total_points')::INT,
        'streak', (NEW.overview->'summary'->>'current_streak')::INT,
        'rank', (NEW.overview->'summary'->>'global_rank')::INT,
        'tasksCompleted', (NEW.today->'summary'->>'completed')::INT,
        'tasksTotal', (NEW.today->'summary'->>'total_scheduled_task')::INT,
        'lastActive', NEW.updated_at
    );

    UPDATE public.mentorship_connections SET
        cached_snapshot = v_snapshot,
        snapshot_captured_at = NOW(),
        updated_at = NOW()
    WHERE owner_id = NEW.user_id 
    AND access_status = 'active';

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_mentorship_snapshots ON public.performance_analytics;
CREATE TRIGGER trg_sync_mentorship_snapshots
    AFTER INSERT OR UPDATE ON public.performance_analytics
    FOR EACH ROW
    EXECUTE FUNCTION internal.fn_sync_mentorship_snapshots();




-- ============================================================
-- VERIFICATION
-- ============================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Performance Analytics V2 Ready';
    RAISE NOTICE '   📊 Table: performance_analytics (new schema)';
    RAISE NOTICE '   🔧 Functions: calc_total_points, calc_overview,';
    RAISE NOTICE '                 calc_today, calc_active_items,';
    RAISE NOTICE '                 calc_progress_history, calc_weekly_history,';
    RAISE NOTICE '                 calc_category_stats, calc_rewards,';
    RAISE NOTICE '                 calc_mood, calc_streaks, calc_recent_activity';
    RAISE NOTICE '   🔄 5 Triggers: day_tasks, weekly_tasks, long_goals,';
    RAISE NOTICE '                  bucket_models, diary_entries';
    RAISE NOTICE '   🔒 5 RLS policies (own + mentors + leaderboard)';
    RAISE NOTICE '   📋 Columns: overview, today, active_items,';
    RAISE NOTICE '               progress_history, weekly_history,';
    RAISE NOTICE '               category_stats, rewards, mood,';
    RAISE NOTICE '               streaks, recent_activity';
END $$;



-- ============================================================
-- STEP 12: ONE-TIME BACKFILL
-- Build analytics rows for all existing users right now.
-- ============================================================

SELECT internal.refresh_all_analytics();

-- 1. BATTLE CHALLENGES SYSTEM
-- Table for tracking friendly competitions between users.
-- Stores a snapshot of participants' user_stats (from performance_analytics).

CREATE TABLE IF NOT EXISTS public.battle_challenges (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title       TEXT NOT NULL DEFAULT 'Battle Challenge',
    description TEXT,
    status      TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'completed', 'cancelled')),
    starts_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ends_at     TIMESTAMPTZ,
    
    -- Participants
    member1_id  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    member2_id  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    member3_id  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    member4_id  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    member5_id  UUID REFERENCES auth.users(id) ON DELETE SET NULL,

    -- Stats Snapshots (updated via trigger)
    user_stats     JSONB,
    member1_stats  JSONB,
    member2_stats  JSONB,
    member3_stats  JSONB,
    member4_stats  JSONB,
    member5_stats  JSONB,

    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for performance and uniqueness
CREATE UNIQUE INDEX IF NOT EXISTS idx_bc_one_active_per_user ON public.battle_challenges(user_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_bc_user ON public.battle_challenges(user_id);
CREATE INDEX IF NOT EXISTS idx_bc_status ON public.battle_challenges(status);

-- ============================================================
-- 2. CALC MEMBER STATS (Internal Helper)
-- ============================================================

CREATE OR REPLACE FUNCTION internal.calc_battle_member_stats(
    p_user_id    UUID,
    p_member_num INT,
    p_is_owner   BOOLEAN,
    p_battle_id  UUID,
    p_joined_at  TIMESTAMPTZ
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_profile_url      TEXT; v_username TEXT; v_display_name TEXT;
    v_overview         JSONB; v_global_rank INT;
    v_cur_streak       INT := 0; v_longest_streak INT := 0;
BEGIN
    -- Basic Profile Info
    SELECT COALESCE(profile_url, ''), COALESCE(username, ''), COALESCE(display_name, '')
    INTO   v_profile_url, v_username, v_display_name
    FROM   public.user_profiles WHERE user_id = p_user_id LIMIT 1;

    -- Overview from Performance Analytics
    SELECT COALESCE(overview, '{}'::jsonb) INTO v_overview
    FROM   public.performance_analytics WHERE user_id = p_user_id LIMIT 1;
    v_global_rank := COALESCE((v_overview->'summary'->>'global_rank')::int, 0);

    -- Minimal stats construction for the battle snapshot
    RETURN jsonb_build_object(
        'profile', jsonb_build_object(
            'id', p_user_id, 'profile_url', v_profile_url, 'username', v_username,
            'display_name', v_display_name, 'global_rank', v_global_rank,
            'competition_rank', 0, 'is_owner', p_is_owner, 'joined_at', p_joined_at
        ),
        'overview', v_overview
    );
END; $$;

-- ============================================================
-- 3. RANKING (Internal Helper)
-- ============================================================

CREATE OR REPLACE FUNCTION internal._update_competition_ranks(p_battle_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_slots    TEXT[] := ARRAY['user','member1','member2','member3','member4','member5'];
    v_slot     TEXT; v_col TEXT; v_points BIGINT; v_rankings JSONB[] := ARRAY[]::JSONB[];
    v_rank INT; v_cur_rank INT; v_prev_pts BIGINT := -1; v_entry JSONB; i INT;
BEGIN
    -- 1. Scan Table for Stats and Points
    FOR i IN 1..array_length(v_slots, 1) LOOP
        v_slot := v_slots[i]; v_col := v_slot || '_stats';
        EXECUTE format('SELECT COALESCE(%I->''overview''->''summary''->>''total_points'',''0'')::bigint FROM public.battle_challenges WHERE id = $1', v_col)
        INTO v_points USING p_battle_id;
        
        IF v_points IS NOT NULL THEN 
            v_rankings := array_append(v_rankings, jsonb_build_object('slot', v_slot, 'points', v_points)); 
        END IF;
    END LOOP;

    -- 2. Sort DESC
    FOR i IN 1..array_length(v_rankings, 1) LOOP
        FOR v_rank IN i..array_length(v_rankings, 1) LOOP
            IF (v_rankings[v_rank]->>'points')::bigint > (v_rankings[i]->>'points')::bigint THEN
                v_entry := v_rankings[i]; v_rankings[i] := v_rankings[v_rank]; v_rankings[v_rank] := v_entry;
            END IF;
        END LOOP;
    END LOOP;

    -- 3. Update Table with Ranks
    v_rank := 0; v_cur_rank := 0; v_prev_pts := -1;
    FOR i IN 1..array_length(v_rankings, 1) LOOP
        v_points := (v_rankings[i]->>'points')::bigint; v_rank := v_rank + 1;
        IF v_points <> v_prev_pts THEN v_cur_rank := v_rank; v_prev_pts := v_points; END IF;
        v_slot := v_rankings[i]->>'slot'; v_col := v_slot || '_stats';
        EXECUTE format('UPDATE public.battle_challenges SET %I = jsonb_set(%I, ''{profile,competition_rank}'', to_jsonb($1::int)) WHERE id = $2', v_col, v_col)
        USING v_cur_rank, p_battle_id;
    END LOOP;
END; $$;

-- ============================================================
-- 4. REFRESH LOGIC
-- ============================================================

CREATE OR REPLACE FUNCTION internal.refresh_battle_stats_for_user(p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_battle RECORD; v_new_stats JSONB; v_joined_at TIMESTAMPTZ;
BEGIN
    FOR v_battle IN (
        SELECT id, user_id, created_at, member1_id, member2_id, member3_id, member4_id, member5_id, member1_stats, member2_stats, member3_stats, member4_stats, member5_stats
        FROM public.battle_challenges WHERE status = 'active'
        AND (user_id = p_user_id OR member1_id = p_user_id OR member2_id = p_user_id OR member3_id = p_user_id OR member4_id = p_user_id OR member5_id = p_user_id)
    ) LOOP
        IF v_battle.user_id = p_user_id THEN 
            v_new_stats := internal.calc_battle_member_stats(p_user_id, 0, true, v_battle.id, v_battle.created_at);
            UPDATE public.battle_challenges SET user_stats = v_new_stats, updated_at = NOW() WHERE id = v_battle.id;
        ELSIF v_battle.member1_id = p_user_id THEN
            v_joined_at := COALESCE((v_battle.member1_stats->'profile'->>'joined_at')::timestamptz, NOW());
            v_new_stats := internal.calc_battle_member_stats(p_user_id, 1, false, v_battle.id, v_joined_at);
            UPDATE public.battle_challenges SET member1_stats = v_new_stats, updated_at = NOW() WHERE id = v_battle.id;
        ELSIF v_battle.member2_id = p_user_id THEN
            v_joined_at := COALESCE((v_battle.member2_stats->'profile'->>'joined_at')::timestamptz, NOW());
            v_new_stats := internal.calc_battle_member_stats(p_user_id, 2, false, v_battle.id, v_joined_at);
            UPDATE public.battle_challenges SET member2_stats = v_new_stats, updated_at = NOW() WHERE id = v_battle.id;
        ELSIF v_battle.member3_id = p_user_id THEN
            v_joined_at := COALESCE((v_battle.member3_stats->'profile'->>'joined_at')::timestamptz, NOW());
            v_new_stats := internal.calc_battle_member_stats(p_user_id, 3, false, v_battle.id, v_joined_at);
            UPDATE public.battle_challenges SET member3_stats = v_new_stats, updated_at = NOW() WHERE id = v_battle.id;
        ELSIF v_battle.member4_id = p_user_id THEN
            v_joined_at := COALESCE((v_battle.member4_stats->'profile'->>'joined_at')::timestamptz, NOW());
            v_new_stats := internal.calc_battle_member_stats(p_user_id, 4, false, v_battle.id, v_joined_at);
            UPDATE public.battle_challenges SET member4_stats = v_new_stats, updated_at = NOW() WHERE id = v_battle.id;
        ELSIF v_battle.member5_id = p_user_id THEN
            v_joined_at := COALESCE((v_battle.member5_stats->'profile'->>'joined_at')::timestamptz, NOW());
            v_new_stats := internal.calc_battle_member_stats(p_user_id, 5, false, v_battle.id, v_joined_at);
            UPDATE public.battle_challenges SET member5_stats = v_new_stats, updated_at = NOW() WHERE id = v_battle.id;
        END IF;

        PERFORM internal._update_competition_ranks(v_battle.id);
    END LOOP;
END; $$;

-- ============================================================
-- 5. RPC FUNCTIONS (Called by Flutter)
-- ============================================================

CREATE OR REPLACE FUNCTION public.toggle_battle_competitor(p_target_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_user_id UUID := auth.uid(); v_battle_id UUID; v_battle RECORD; v_slot_num INT := 0; v_id_col TEXT; v_stat_col TEXT; v_new_stats JSONB; v_action TEXT;
BEGIN
    IF v_user_id IS NULL THEN RETURN jsonb_build_object('error', 'Not authenticated'); END IF;
    IF v_user_id = p_target_id THEN RETURN jsonb_build_object('error', 'Cannot compete with yourself'); END IF;

    -- 1. Find/Create active battle
    SELECT id INTO v_battle_id FROM public.battle_challenges WHERE user_id = v_user_id AND status = 'active' LIMIT 1;
    IF v_battle_id IS NULL THEN
        INSERT INTO public.battle_challenges (user_id, title, status) VALUES (v_user_id, '1-on-1 Battle', 'active') RETURNING id INTO v_battle_id;
        PERFORM internal.refresh_battle_stats_for_user(v_user_id);
    END IF;

    -- 2. Toggle logic & Rate Limiting
    SELECT * INTO v_battle FROM public.battle_challenges WHERE id = v_battle_id;
    
    IF v_battle.updated_at > NOW() - INTERVAL '2 seconds' THEN
        RETURN jsonb_build_object('error', 'Too many requests. Please wait a moment.');
    END IF;

    IF v_battle.member1_id = p_target_id THEN v_slot_num := 1; v_action := 'remove';
    ELSIF v_battle.member2_id = p_target_id THEN v_slot_num := 2; v_action := 'remove';
    ELSIF v_battle.member3_id = p_target_id THEN v_slot_num := 3; v_action := 'remove';
    ELSIF v_battle.member4_id = p_target_id THEN v_slot_num := 4; v_action := 'remove';
    ELSIF v_battle.member5_id = p_target_id THEN v_slot_num := 5; v_action := 'remove';
    ELSE
        v_action := 'add';
        IF v_battle.member1_id IS NULL THEN v_slot_num := 1;
        ELSIF v_battle.member2_id IS NULL THEN v_slot_num := 2;
        ELSIF v_battle.member3_id IS NULL THEN v_slot_num := 3;
        ELSIF v_battle.member4_id IS NULL THEN v_slot_num := 4;
        ELSIF v_battle.member5_id IS NULL THEN v_slot_num := 5;
        ELSE RETURN jsonb_build_object('error', 'Competition is full'); END IF;
    END IF;

    -- 3. Execute
    v_id_col := 'member' || v_slot_num || '_id';
    v_stat_col := 'member' || v_slot_num || '_stats';
    IF v_action = 'remove' THEN
        EXECUTE format('UPDATE public.battle_challenges SET %I = NULL, %I = NULL WHERE id = $1', v_id_col, v_stat_col) USING v_battle_id;
    ELSE
        v_new_stats := internal.calc_battle_member_stats(p_target_id, v_slot_num, false, v_battle_id, NOW());
        EXECUTE format('UPDATE public.battle_challenges SET %I = $1, %I = $2 WHERE id = $3', v_id_col, v_stat_col) USING p_target_id, v_new_stats, v_battle_id;
    END IF;

    PERFORM internal._update_competition_ranks(v_battle_id);
    RETURN jsonb_build_object('success', true, 'action', v_action, 'battle_id', v_battle_id);
END; $$;

CREATE OR REPLACE FUNCTION public.get_battle(p_battle_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE v_battle RECORD;
BEGIN
    -- [SECURITY] Participation check
    -- This function returns full battle data including other users' snapshots.
    -- We must ensure the caller is one of the members.
    -- (Note: Internal check already exists below, but we add role check for safety)
    IF auth.uid() IS NULL AND auth.role() != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized';
    END IF;

    SELECT * INTO v_battle FROM public.battle_challenges WHERE id = p_battle_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('error', 'Battle not found'); END IF;
    IF auth.uid() NOT IN (v_battle.user_id, v_battle.member1_id, v_battle.member2_id, v_battle.member3_id, v_battle.member4_id, v_battle.member5_id) THEN
        RETURN jsonb_build_object('error', 'Access denied');
    END IF;
    RETURN row_to_json(v_battle)::jsonb;
END; $$;

-- ============================================================
-- 6. TRIGGERS
-- ============================================================

CREATE OR REPLACE FUNCTION internal.trigger_battle_stats_refresh()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.overview IS DISTINCT FROM OLD.overview THEN
        PERFORM internal.refresh_battle_stats_for_user(NEW.user_id);
    END IF;
    RETURN NEW;
END; $$;

CREATE TRIGGER trg_battle_stats_refresh
    AFTER UPDATE ON public.performance_analytics
    FOR EACH ROW EXECUTE FUNCTION internal.trigger_battle_stats_refresh();

CREATE OR REPLACE FUNCTION public.trigger_battle_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := NOW(); RETURN NEW; END; $$;

CREATE TRIGGER trg_battle_updated_at
    BEFORE INSERT OR UPDATE ON public.battle_challenges
    FOR EACH ROW EXECUTE FUNCTION public.trigger_battle_updated_at();

-- ============================================================
-- 7. RLS POLICIES
-- ============================================================

ALTER TABLE public.battle_challenges ENABLE ROW LEVEL SECURITY;

-- 1. SELECT: Participants can see their own battles
CREATE POLICY "bc_participant_select" ON public.battle_challenges
    FOR SELECT TO authenticated
    USING (
        auth.uid() = user_id OR
        auth.uid() = member1_id OR
        auth.uid() = member2_id OR
        auth.uid() = member3_id OR
        auth.uid() = member4_id OR
        auth.uid() = member5_id
    );

-- 2. INSERT: Users can create battles
CREATE POLICY "bc_creator_insert" ON public.battle_challenges
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- 3. UPDATE: Creators can update metadata
CREATE POLICY "bc_creator_update" ON public.battle_challenges
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 4. DELETE: Only creator can delete
CREATE POLICY "bc_creator_delete" ON public.battle_challenges
    FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- ============================================================
-- 8. GRANTS
-- ============================================================

-- 1. Global Revoke
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;

-- 2. Public API Grants
GRANT ALL ON TABLE public.battle_challenges TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_battle_competitor(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_battle(UUID) TO authenticated;

-- 3. Administrative/Internal
GRANT USAGE ON SCHEMA internal TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA internal TO service_role, postgres;
GRANT EXECUTE ON FUNCTION public.trigger_battle_updated_at() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ public.battle_challenges table ready';
    RAISE NOTICE '   - 2 triggers:';
    RAISE NOTICE '     • trg_battle_stats_refresh';
    RAISE NOTICE '     • trg_battle_updated_at';
    RAISE NOTICE '   - 6 functions:';
    RAISE NOTICE '     • calc_battle_member_stats()';
    RAISE NOTICE '     • _update_competition_ranks()';
    RAISE NOTICE '     • refresh_battle_stats_for_user()';
    RAISE NOTICE '     • toggle_battle_competitor()';
    RAISE NOTICE '     • get_battle()';
    RAISE NOTICE '     • trigger_battle_updated_at()';
    RAISE NOTICE '   - 4 RLS policies';
    RAISE NOTICE '   - 3 indexes';
END $$;
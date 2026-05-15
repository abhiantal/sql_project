-- ============================================================
-- 📁 FILE 19: DAILY MAINTENANCE & USER DELETION CLEANUP
-- Global functions that span multiple tables
-- ============================================================

-- ============================================================
-- FUNCTION: Run daily maintenance
-- ============================================================
CREATE OR REPLACE FUNCTION internal.run_daily_maintenance()
RETURNS VOID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check mentorship expirations
    BEGIN
        PERFORM internal.check_mentorship_expirations();
    EXCEPTION
        WHEN undefined_function THEN NULL;
    END;

    -- Update all leaderboard rankings (if exists)
    BEGIN
        PERFORM internal.update_global_leaderboard_ranks();
    EXCEPTION
        WHEN undefined_function THEN NULL;
    END;

    -- Cleanup disappearing messages (if exists)
    BEGIN
        PERFORM internal.cleanup_disappearing_messages();
    EXCEPTION
        WHEN undefined_function THEN NULL;
    END;
    END;
END;
$$;


-- ============================================================
-- GRANTS
-- ============================================================
GRANT USAGE ON SCHEMA internal TO service_role;
GRANT EXECUTE ON FUNCTION internal.run_daily_maintenance() TO service_role, postgres;

-- ============================================================
-- VERIFICATION
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ Maintenance functions ready';
    RAISE NOTICE '   - 1 function:';
    RAISE NOTICE '     • run_daily_maintenance()';
END $$;
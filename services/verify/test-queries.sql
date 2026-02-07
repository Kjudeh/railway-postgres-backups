-- ========================================
-- Custom Verification Queries
-- ========================================
-- Add your own verification queries here
-- These will be run against the restored database
-- to verify that your data is intact and queryable

-- Example: Verify critical tables exist
DO $$
BEGIN
    -- Add your table verification logic here
    -- Example:
    -- IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users') THEN
    --     RAISE EXCEPTION 'Critical table missing: users';
    -- END IF;
END $$;

-- Example: Verify row counts are reasonable
-- SELECT
--     tablename,
--     n_tup_ins - n_tup_del as row_count
-- FROM pg_stat_user_tables
-- WHERE schemaname = 'public'
--   AND (n_tup_ins - n_tup_del) = 0
--   AND tablename IN ('users', 'orders'); -- Critical tables that should have data

-- Example: Verify foreign key constraints
SELECT
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type
FROM information_schema.table_constraints tc
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public';

-- Example: Verify indexes exist
SELECT
    schemaname,
    tablename,
    indexname
FROM pg_indexes
WHERE schemaname = 'public';

-- If you reach here without errors, verification passed
SELECT 'Custom verification queries completed successfully' as status;

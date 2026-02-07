# Restore Guide

Complete guide for restoring PostgreSQL databases from backups.

## Table of Contents

- [Quick Restore](#quick-restore)
- [Restore Scenarios](#restore-scenarios)
- [Step-by-Step Restore](#step-by-step-restore)
- [Point-in-Time Considerations](#point-in-time-considerations)
- [Testing Restores](#testing-restores)
- [Troubleshooting Restores](#troubleshooting-restores)

## Quick Restore

### Prerequisites

- Access to S3 bucket with backups
- PostgreSQL client tools (`psql`, `pg_restore`)
- Target database server
- AWS CLI installed

### Quick Steps

```bash
# 1. Download latest backup
aws s3 cp s3://your-bucket/postgres-backups/backup_20240207_143022.sql.gz . \
  --endpoint-url https://s3.amazonaws.com

# 2. Decompress
gunzip backup_20240207_143022.sql.gz

# 3. Create target database
psql -h target-host -U postgres -c "CREATE DATABASE restored_db;"

# 4. Restore
psql -h target-host -U postgres -d restored_db -f backup_20240207_143022.sql

# 5. Verify
psql -h target-host -U postgres -d restored_db -c "SELECT COUNT(*) FROM your_table;"
```

## Restore Scenarios

### Scenario 1: Complete Database Loss

**Situation**: Production database is completely lost or corrupted

**Steps**:
1. Identify last known good backup
2. Create new database instance
3. Restore backup
4. Verify data integrity
5. Update application connection strings
6. Resume operations

**Estimated Time**: 30 minutes - 4 hours (depending on database size)

### Scenario 2: Accidental Data Deletion

**Situation**: Data was accidentally deleted, but database is otherwise healthy

**Steps**:
1. Identify backup before deletion occurred
2. Restore to temporary database
3. Export deleted data
4. Import data back to production
5. Verify data integrity

**Estimated Time**: 15 minutes - 2 hours

### Scenario 3: Migration to New Server

**Situation**: Moving database to new server or provider

**Steps**:
1. Download latest backup
2. Provision new database server
3. Restore backup to new server
4. Update application configuration
5. Test application connectivity
6. Switch over

**Estimated Time**: 1-6 hours

### Scenario 4: Rollback After Bad Migration

**Situation**: Database migration went wrong, need to rollback

**Steps**:
1. Identify backup before migration
2. Create new database instance (don't overwrite broken one yet)
3. Restore backup
4. Verify application works with restored database
5. Switch application to restored database
6. Clean up broken database

**Estimated Time**: 30 minutes - 2 hours

## Step-by-Step Restore

### Step 1: List Available Backups

```bash
# List all backups
aws s3 ls s3://your-bucket/postgres-backups/ \
  --endpoint-url https://your-s3-endpoint \
  --recursive

# Output:
# 2024-02-05 10:00:00  524288000 postgres-backups/backup_20240205_100000.sql.gz
# 2024-02-06 10:00:00  524288000 postgres-backups/backup_20240206_100000.sql.gz
# 2024-02-07 10:00:00  524288000 postgres-backups/backup_20240207_100000.sql.gz
```

### Step 2: Select Backup

Choose based on:
- **Latest backup**: Most recent data, but may include bad data
- **Specific time**: Before incident occurred
- **File size**: Unusually small files may be corrupted

### Step 3: Download Backup

```bash
# Download specific backup
aws s3 cp s3://your-bucket/postgres-backups/backup_20240207_100000.sql.gz ./restore/ \
  --endpoint-url https://your-s3-endpoint

# Verify download
ls -lh restore/
# Should show the .sql.gz file with correct size
```

### Step 4: Verify Backup Integrity

```bash
# Test gzip integrity
gunzip -t restore/backup_20240207_100000.sql.gz

# If successful, no output
# If corrupted, will show error
```

### Step 5: Decompress Backup

```bash
# Decompress
gunzip restore/backup_20240207_100000.sql.gz

# Result: restore/backup_20240207_100000.sql
```

### Step 6: Prepare Target Database

#### Option A: Create New Database

```bash
# Connect to PostgreSQL
psql -h target-host -U postgres

# Create database
CREATE DATABASE restored_db;

# Exit
\q
```

#### Option B: Clean Existing Database

```bash
# Connect to database
psql -h target-host -U postgres -d existing_db

# Drop all tables (careful!)
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;

# Exit
\q
```

### Step 7: Restore Backup

```bash
# Restore with progress indication
pv restore/backup_20240207_100000.sql | \
  psql -h target-host -U postgres -d restored_db

# Or without progress:
psql -h target-host -U postgres -d restored_db \
  -f restore/backup_20240207_100000.sql
```

**Expected Output**:
```
SET
SET
SET
SET
...
CREATE TABLE
CREATE TABLE
...
COPY 1234
COPY 5678
...
CREATE INDEX
CREATE INDEX
...
ALTER TABLE
```

**Common Messages** (usually safe to ignore):
- `ERROR: role "xyz" does not exist` (if using --no-owner)
- `ERROR: must be owner of extension` (if using --no-acl)

### Step 8: Verify Restoration

```bash
# Connect to restored database
psql -h target-host -U postgres -d restored_db

# Check tables exist
\dt

# Check row counts
SELECT schemaname, tablename, n_tup_ins - n_tup_del as row_count
FROM pg_stat_user_tables
WHERE schemaname = 'public';

# Check specific critical data
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM orders;

# Verify recent data (if applicable)
SELECT MAX(created_at) FROM orders;

# Exit
\q
```

### Step 9: Update Application

```bash
# Update DATABASE_URL environment variable
export DATABASE_URL="postgresql://user:pass@target-host:5432/restored_db"

# Or in Railway:
railway variables set DATABASE_URL="postgresql://user:pass@target-host:5432/restored_db"

# Restart application
railway up
```

### Step 10: Clean Up

```bash
# Remove local backup files
rm restore/backup_20240207_100000.sql
rm restore/backup_20240207_100000.sql.gz  # if not already deleted

# (Optional) Delete old broken database
psql -h old-host -U postgres -c "DROP DATABASE broken_db;"
```

## Point-in-Time Considerations

### What's Included in Backups

✅ **Included**:
- All table data at time of backup
- Table schemas
- Indexes
- Constraints
- Sequences
- Views
- Functions
- Triggers

❌ **Not Included**:
- Changes after backup was taken
- User roles/passwords (with --no-owner flag)
- Ownership information (with --no-owner flag)
- Permissions (with --no-acl flag)

### Determining Backup Time

```bash
# Extract timestamp from filename
# Format: backup_YYYYMMDD_HHMMSS.sql.gz
# Example: backup_20240207_143022.sql.gz
# = February 7, 2024 at 14:30:22 (2:30:22 PM)

# Or check S3 metadata
aws s3api head-object \
  --bucket your-bucket \
  --key postgres-backups/backup_20240207_143022.sql.gz \
  --endpoint-url https://your-s3-endpoint
```

### Data Loss Window

**Example**:
- Last backup: 14:00
- Incident occurred: 16:30
- **Data loss**: 2.5 hours (14:00 to 16:30)

**Mitigation**:
- More frequent backups
- Transaction logs (not included in this template)
- Read replicas with delayed replication

## Testing Restores

### Why Test?

- Verify backups are valid
- Practice restore procedures
- Measure restore time
- Identify issues before disaster

### Test Restore Procedure

```bash
# 1. Download random backup (not just latest)
RANDOM_BACKUP=$(aws s3 ls s3://your-bucket/postgres-backups/ \
  --endpoint-url https://your-s3-endpoint --recursive | \
  sort -R | head -n 1 | awk '{print $4}')

echo "Testing restore of: $RANDOM_BACKUP"

# 2. Download
aws s3 cp "s3://your-bucket/$RANDOM_BACKUP" ./test-restore/ \
  --endpoint-url https://your-s3-endpoint

# 3. Create test database
psql -h test-server -U postgres -c "DROP DATABASE IF EXISTS restore_test;"
psql -h test-server -U postgres -c "CREATE DATABASE restore_test;"

# 4. Restore
gunzip -c "test-restore/$(basename $RANDOM_BACKUP)" | \
  psql -h test-server -U postgres -d restore_test

# 5. Run verification queries
psql -h test-server -U postgres -d restore_test <<EOF
-- Count tables
SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema = 'public';

-- Check row counts
SELECT schemaname, tablename, n_tup_ins - n_tup_del as row_count
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY row_count DESC
LIMIT 10;

-- Verify indexes
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname = 'public';
EOF

# 6. Clean up
psql -h test-server -U postgres -c "DROP DATABASE restore_test;"
rm -rf test-restore/
```

### Automated Testing

The verify service automatically tests restores! See [Verify Service README](../services/verify/README.md).

## Restoring Specific Tables

### Export Single Table from Backup

```bash
# 1. Restore full backup to temporary database
gunzip -c backup_20240207_143022.sql.gz | \
  psql -h temp-server -U postgres -d temp_restore

# 2. Export specific table
pg_dump -h temp-server -U postgres -d temp_restore \
  -t users \
  --data-only \
  > users_data.sql

# 3. Import to production
psql -h prod-server -U postgres -d prod_db -f users_data.sql

# 4. Clean up
psql -h temp-server -U postgres -c "DROP DATABASE temp_restore;"
rm users_data.sql
```

### Restore Specific Tables Only

```bash
# Extract and restore only specific tables during initial restore
gunzip -c backup_20240207_143022.sql.gz | \
  psql -h target-server -U postgres -d target_db \
    --single-transaction \
    -v ON_ERROR_STOP=1 \
    2>&1 | grep -A 5 "CREATE TABLE users"
```

**Note**: This is complex. Easier to restore full database then export tables.

## Advanced Restore Techniques

### Parallel Restore (Faster for Large Databases)

If backup was created with `pg_dump --format=directory`:

```bash
# Restore with 4 parallel jobs
pg_restore -h target-host -U postgres -d target_db \
  --jobs=4 \
  backup_directory/
```

**Note**: This template uses SQL format, not directory format.

### Restore to Different PostgreSQL Version

**Supported**: ✅ Upgrading (e.g., PostgreSQL 12 → 16)
**Supported**: ⚠️ Downgrading (may have issues)

```bash
# Restore backup from PostgreSQL 14 to PostgreSQL 16
gunzip -c backup_from_pg14.sql.gz | \
  psql -h pg16-server -U postgres -d target_db
```

**Recommendations**:
- Test thoroughly
- Check PostgreSQL release notes for breaking changes
- Verify all extensions are compatible

### Restore to Different Server Architecture

Backups are portable across:
- ✅ Different operating systems (Linux → macOS → Windows)
- ✅ Different CPU architectures (x86 → ARM)
- ✅ Different PostgreSQL installations

### Restore with Modifications

```bash
# Restore and modify data during restore
gunzip -c backup_20240207_143022.sql.gz | \
  sed 's/old_value/new_value/g' | \
  psql -h target-host -U postgres -d target_db
```

**Use Cases**:
- Change schema names
- Modify constraint names
- Update specific values

**Warning**: Use with caution, test thoroughly!

## Troubleshooting Restores

See [Troubleshooting Guide](troubleshooting.md#restore-issues) for common restore issues.

### Quick Checklist

- [ ] Backup file downloaded successfully
- [ ] Backup file integrity verified (`gunzip -t`)
- [ ] Target database exists and is empty
- [ ] User has appropriate permissions
- [ ] PostgreSQL version compatible
- [ ] Sufficient disk space
- [ ] Network connectivity stable

### Common Issues

**Issue**: "must be owner of extension"
- **Cause**: Backup uses --no-acl flag
- **Solution**: Safe to ignore, or restore as superuser

**Issue**: "role does not exist"
- **Cause**: Backup uses --no-owner flag
- **Solution**: Safe to ignore, or create roles first

**Issue**: Restore is very slow
- **Cause**: Indexes being rebuilt
- **Solution**: Normal, wait for completion

**Issue**: "out of memory"
- **Cause**: Large transaction
- **Solution**: Increase database server memory or restore in smaller chunks

## Emergency Restore Contacts

In case of emergency:

1. **Check backups exist**:
   ```bash
   aws s3 ls s3://your-bucket/postgres-backups/ --recursive
   ```

2. **Check backup size** (compare to normal size):
   ```bash
   aws s3 ls s3://your-bucket/postgres-backups/ --recursive --human-readable
   ```

3. **Test restore to temporary database** (don't touch production yet)

4. **Document everything** for post-mortem

## Restore Best Practices

1. **Practice restores regularly** - Use verify service
2. **Document restore procedures** - Keep this guide updated
3. **Test in staging first** - Never restore directly to production without testing
4. **Time restores** - Know how long restores take
5. **Keep multiple backups** - Don't rely on just latest backup
6. **Verify after restore** - Always run verification queries
7. **Have rollback plan** - Keep old database until new one verified
8. **Monitor backup sizes** - Unusually small = potential problem
9. **Alert on restore failures** - Monitor verify service
10. **Document incidents** - Learn from each restore

## Restore Time Estimates

| Database Size | Download | Restore | Total  |
|--------------|----------|---------|--------|
| 100 MB       | 1 min    | 1 min   | 2 min  |
| 1 GB         | 2-5 min  | 5-10 min| 10-15 min |
| 10 GB        | 10-20 min| 20-40 min| 30-60 min |
| 100 GB       | 1-2 hrs  | 2-4 hrs | 3-6 hrs |

**Factors affecting restore time**:
- Network speed (download)
- Disk I/O speed (restore)
- Number of indexes (index rebuild)
- Number of constraints
- PostgreSQL configuration
- Server resources (CPU, RAM)

## Next Steps

After successful restore:
1. Review [Troubleshooting Guide](troubleshooting.md)
2. Check [Runbooks](runbooks.md) for operational procedures
3. Update team documentation
4. Schedule regular restore drills
5. Consider implementing point-in-time recovery

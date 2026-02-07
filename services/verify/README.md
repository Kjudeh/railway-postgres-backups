# PostgreSQL Restore Verification Service

Automated restore verification service that performs periodic "restore drills" to ensure backups are valid and restorable.

## Features

- Automated periodic restore testing
- Downloads backups from S3-compatible storage
- Restores to temporary databases (no impact on production)
- Runs verification queries to validate data integrity
- Automatic cleanup of temporary databases
- Configurable verification intervals
- Custom verification query support

## Why Restore Drills?

**Untested backups are worthless.** This service ensures your backups are actually restorable by:

1. Regularly downloading real backup files
2. Restoring them to temporary databases
3. Running verification queries
4. Reporting success/failure

This gives you confidence that when disaster strikes, your backups will work.

## Quick Start

### Local Development

1. Copy the example environment file:
```bash
cp .env.example .env
```

2. Edit `.env` with your configuration

3. (Optional) Customize `test-queries.sql` with your verification logic

4. Build and run with Docker:
```bash
docker build -t postgres-verify .
docker run --env-file .env postgres-verify
```

### Railway Deployment

1. Ensure you have the backup service running
2. Add this service from the template
3. Configure the required environment variables
4. Deploy

## Environment Variables

See `.env.example` for detailed documentation.

### Required
- `VERIFY_DATABASE_URL` - PostgreSQL connection string for restore target
  - **CRITICAL**: Must be different from production `DATABASE_URL`
  - Safety check prevents overwriting production database
  - Recommended: Use separate PostgreSQL instance for verification
- `S3_ENDPOINT` - S3-compatible storage endpoint
- `S3_BUCKET` - S3 bucket name
- `S3_ACCESS_KEY_ID` - S3 access key
- `S3_SECRET_ACCESS_KEY` - S3 secret key

### Optional
- `VERIFY_INTERVAL` - Verification frequency in seconds (default: 86400 = 24h)
- `S3_REGION` - AWS region (default: us-east-1)
- `BACKUP_PREFIX` - S3 key prefix (default: postgres-backups)
- `VERIFY_LATEST` - Verify latest backup (default: true)
- `VERIFY_BACKUP_FILE` - Specific backup to verify (optional)
- `VERIFY_SQL` - Custom SQL check to run during verification (optional)
  - Example: `SELECT COUNT(*) FROM users WHERE active = true`
  - Must succeed (return rows without error) for verification to pass
- `VERIFY_WEBHOOK_URL` - HTTP endpoint for status notifications (optional)
  - Receives JSON POST with status, message, backup file, and duration
  - Useful for integrating with monitoring/alerting systems
- `MIN_TABLE_COUNT` - Minimum number of tables expected (default: 0)
  - Verification fails if restored database has fewer tables
  - Use to detect incomplete or corrupted backups

## Custom Verification Queries

Edit `test-queries.sql` to add custom verification logic:

```sql
-- Verify critical tables exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users') THEN
        RAISE EXCEPTION 'Critical table missing: users';
    END IF;
END $$;

-- Verify row counts
SELECT COUNT(*) FROM users;
SELECT COUNT(*) FROM orders;
```

## How It Works

1. **Download**: Fetches the latest (or specified) backup from S3
2. **Restore**: Creates a temporary database and restores the backup
3. **Verify**: Runs built-in and custom verification queries
4. **Cleanup**: Drops the temporary database and removes local files
5. **Report**: Logs success/failure
6. **Sleep**: Waits for the next interval

## Monitoring

Monitor the following:
- Log output for verification success/failure
- Temporary database creation/cleanup
- Verification query results
- Time taken for each restore drill

## Troubleshooting

Common issues:

### "No backups found in S3"
- Ensure backup service is running and has created at least one backup
- Verify S3_BUCKET and BACKUP_PREFIX match the backup service configuration

### "Failed to download backup from S3"
- Check S3 credentials and permissions
- Verify S3_ENDPOINT is correct
- Ensure network connectivity to S3

### "Restore failed"
- Check PostgreSQL version compatibility
- Verify DATABASE_URL has permissions to create databases
- Review restore logs for specific SQL errors

### "Custom test queries failed"
- Review `test-queries.sql` for syntax errors
- Ensure queries are compatible with restored data

## Safety Features

### Production Database Protection

The service includes **critical safety checks** to prevent accidental damage to production:

1. **VERIFY_DATABASE_URL Required**: Must explicitly specify the restore target database
2. **Safety Validation**: Refuses to start if `VERIFY_DATABASE_URL` equals `DATABASE_URL`
3. **Warning on Same Host**: Warns if verify and production databases are on the same server
4. **Temporary Databases**: All restores use uniquely-named temporary databases
5. **Automatic Cleanup**: Temporary databases are always dropped after verification

**Example Safe Configuration**:
```bash
# Production database (used by backup service)
DATABASE_URL=postgresql://user:pass@prod.example.com:5432/production

# Separate verify database (different server recommended)
VERIFY_DATABASE_URL=postgresql://user:pass@verify.example.com:5432/postgres
```

**NEVER** set `VERIFY_DATABASE_URL` to your production database!

## Webhook Notifications

Enable webhook notifications to integrate with monitoring/alerting systems:

```bash
VERIFY_WEBHOOK_URL=https://your-webhook-endpoint.com/notify
```

**Webhook Payload**:
```json
{
  "status": "success|failure|error",
  "message": "Restore verification completed successfully",
  "backup_file": "backup_20240207_143022.sql.gz",
  "duration_seconds": 45,
  "timestamp": "2024-02-07T14:30:22Z",
  "service": "postgres-restore-verify",
  "host": "verify-db.example.com:5432"
}
```

**Status Values**:
- `success` - Verification completed successfully
- `failure` - Restore or verification checks failed
- `error` - System error (no backups, S3 failure, etc.)

**Use Cases**:
- Send alerts to Slack/Discord/PagerDuty
- Track verification metrics in monitoring system
- Trigger automated responses to failures
- Generate compliance reports

## Security

- Temporary databases are created with unique names and cleaned up automatically
- No credentials are logged
- Uses same security practices as backup service
- Safety checks prevent production database modification

## Performance Considerations

- Restore drills require CPU, memory, and disk I/O
- Adjust VERIFY_INTERVAL based on your backup size and server capacity
- Consider running verification on a separate database server
- Temporary databases can be large - ensure sufficient disk space

## Testing

See the `tests/` directory in the repository root for local testing.

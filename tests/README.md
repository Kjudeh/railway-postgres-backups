# Integration Tests

This directory contains integration tests for the PostgreSQL backup and restore verification services.

## Overview

The tests use Docker Compose to spin up a complete test environment:
- PostgreSQL database
- MinIO (S3-compatible storage)
- Backup service
- Restore verification service

## Prerequisites

- Docker and Docker Compose installed
- Bash shell (or Git Bash on Windows)

## Running Tests Locally

### Quick Start

```bash
cd tests
./run-tests.sh
```

The test script will:
1. Start PostgreSQL and MinIO containers
2. Seed test data
3. Run the backup service
4. Verify backup exists in MinIO
5. Run the restore verification service
6. Verify data integrity
7. Clean up all resources

### Manual Testing

Start all services:
```bash
docker-compose -f docker-compose.test.yml up
```

Access MinIO console:
- URL: http://localhost:9001
- Username: minioadmin
- Password: minioadmin123

Access PostgreSQL:
```bash
docker-compose -f docker-compose.test.yml exec postgres psql -U testuser -d testdb
```

Stop and clean up:
```bash
docker-compose -f docker-compose.test.yml down -v
```

## Test Scenarios

### Test 1: Backup Creation
- Seeds test data in PostgreSQL
- Runs backup service
- Verifies backup file is created in MinIO
- Checks backup logs for success

### Test 2: Backup Existence
- Lists files in MinIO bucket
- Verifies backup file exists with correct naming convention

### Test 3: Restore Verification
- Runs verify service
- Downloads latest backup
- Restores to temporary database
- Runs verification queries
- Checks logs for success

### Test 4: Data Integrity
- Queries restored database
- Verifies record counts match
- Validates schema integrity

### Test 5: Backup Retention (Manual)
- Requires time-based testing
- Verifies old backups are cleaned up
- See "Manual Retention Testing" below

## Manual Retention Testing

To test backup retention:

1. Start services:
```bash
docker-compose -f docker-compose.test.yml up -d
```

2. Wait for multiple backups to be created (set BACKUP_INTERVAL=60 for faster testing)

3. Check backups in MinIO:
```bash
docker-compose -f docker-compose.test.yml exec minio \
  mc ls myminio/test-backups/test-backups/
```

4. Manually create an "old" backup by modifying timestamps or wait for retention period

5. Verify old backups are deleted on next backup cycle

## Continuous Integration

The tests are also run in GitHub Actions CI. See `.github/workflows/test.yml`.

## Troubleshooting

### Services not starting
```bash
# Check service logs
docker-compose -f docker-compose.test.yml logs

# Check specific service
docker-compose -f docker-compose.test.yml logs postgres
docker-compose -f docker-compose.test.yml logs minio
docker-compose -f docker-compose.test.yml logs backup
```

### Backup not appearing in MinIO
```bash
# Check backup service logs
docker-compose -f docker-compose.test.yml logs backup

# Check MinIO bucket
docker-compose -f docker-compose.test.yml exec minio \
  mc ls myminio/test-backups/test-backups/
```

### Restore verification failing
```bash
# Check verify service logs
docker-compose -f docker-compose.test.yml logs verify

# Check if temporary databases are being created
docker-compose -f docker-compose.test.yml exec postgres \
  psql -U testuser -d postgres -c "\l"
```

### Port conflicts
If ports 5432, 9000, or 9001 are already in use, modify the ports in `docker-compose.test.yml`.

## Performance

Test execution time:
- Setup: ~10 seconds
- Backup cycle: ~60 seconds
- Verify cycle: ~120 seconds
- Total: ~3 minutes

## Customization

### Custom Test Data

Edit the seed data in `run-tests.sh`:
```sql
INSERT INTO test_table (name) VALUES
    ('Your custom data');
```

### Custom Verification Queries

Modify `../services/verify/test-queries.sql` to add custom verification logic.

### Test Configuration

Modify environment variables in `docker-compose.test.yml` to test different configurations:
- `BACKUP_INTERVAL` - Backup frequency
- `BACKUP_RETENTION_DAYS` - Retention policy
- `COMPRESSION_LEVEL` - Compression level
- `VERIFY_INTERVAL` - Verification frequency

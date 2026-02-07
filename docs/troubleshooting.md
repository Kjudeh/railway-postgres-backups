# Troubleshooting Guide

Common issues and solutions for the PostgreSQL backup and restore verification services.

## Table of Contents

- [Backup Service Issues](#backup-service-issues)
- [Verify Service Issues](#verify-service-issues)
- [S3 Connection Issues](#s3-connection-issues)
- [Database Connection Issues](#database-connection-issues)
- [Restore Issues](#restore-issues)
- [Performance Issues](#performance-issues)
- [Configuration Issues](#configuration-issues)

## Backup Service Issues

### Backup Service Won't Start

**Symptoms**:
- Container exits immediately
- "Required environment variable not set" error

**Diagnosis**:
```bash
# Check logs
railway logs

# Or with Docker:
docker logs <container-id>
```

**Solutions**:

1. **Missing environment variables**
   ```bash
   # Verify all required variables are set
   railway variables

   # Check for: DATABASE_URL, S3_ENDPOINT, S3_BUCKET,
   # S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY
   ```

2. **Invalid DATABASE_URL format**
   - ❌ Wrong: `postgres://user:pass@host/db`
   - ✅ Correct: `postgresql://user:pass@host:5432/db`

3. **Invalid S3_ENDPOINT format**
   - ❌ Wrong: `s3.amazonaws.com` (missing protocol)
   - ❌ Wrong: `https://s3.amazonaws.com/bucket` (includes bucket)
   - ✅ Correct: `https://s3.amazonaws.com`

### Backup Fails: "Cannot connect to database"

**Symptoms**:
```
ERROR: Cannot connect to database
pg_isready: no response from server
```

**Diagnosis**:
```bash
# Test database connectivity manually
psql "$DATABASE_URL" -c "SELECT version();"
```

**Solutions**:

1. **Database is down**
   - Check database service status in Railway
   - Verify database is running: `railway status`

2. **Wrong credentials**
   - Verify DATABASE_URL is correct
   - Test credentials manually
   - Check for special characters that need URL encoding

3. **Network issues**
   - Verify services are in same Railway project (for internal networking)
   - Check firewall rules if using external database
   - Verify SSL/TLS settings

4. **Database connection limit reached**
   ```bash
   # Check current connections
   psql "$DATABASE_URL" -c "SELECT count(*) FROM pg_stat_activity;"

   # Check max connections
   psql "$DATABASE_URL" -c "SHOW max_connections;"
   ```
   - Increase `max_connections` in PostgreSQL config
   - Close idle connections

### Backup Fails: "Cannot connect to S3"

**Symptoms**:
```
ERROR: S3 upload failed
fatal error: Unable to locate credentials
```

**Diagnosis**:
```bash
# Test S3 connectivity manually
aws s3 ls s3://${S3_BUCKET} --endpoint-url ${S3_ENDPOINT}
```

**Solutions**:

1. **Wrong credentials**
   - Verify S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY
   - Check for trailing spaces in variables
   - Verify credentials have not expired

2. **Wrong endpoint**
   - Verify S3_ENDPOINT matches your provider
   - Check [Configuration Guide](configuration.md#storage-provider-examples)

3. **Bucket doesn't exist**
   ```bash
   # Create bucket
   aws s3 mb s3://${S3_BUCKET} --endpoint-url ${S3_ENDPOINT}
   ```

4. **Insufficient permissions**
   - Verify IAM policy includes: `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:ListBucket`
   - Test permissions:
   ```bash
   # Test write
   echo "test" | aws s3 cp - s3://${S3_BUCKET}/test.txt --endpoint-url ${S3_ENDPOINT}

   # Test delete
   aws s3 rm s3://${S3_BUCKET}/test.txt --endpoint-url ${S3_ENDPOINT}
   ```

### Backup Succeeds but File is Empty or Very Small

**Symptoms**:
- Backup file is 0 bytes or unusually small
- Restore fails with "no data"

**Diagnosis**:
```bash
# Check backup file size
aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ --endpoint-url ${S3_ENDPOINT} --human-readable

# Download and inspect
aws s3 cp s3://${S3_BUCKET}/${BACKUP_PREFIX}/backup_latest.sql.gz ./test.gz --endpoint-url ${S3_ENDPOINT}
gunzip -t test.gz
gunzip test.gz
head test.sql
```

**Solutions**:

1. **pg_dump failed silently**
   - Check backup service logs for errors
   - Verify database user has read permissions on all tables
   ```bash
   # Grant read permissions
   psql "$DATABASE_URL" -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO backup_user;"
   ```

2. **Database is empty**
   - Verify tables exist:
   ```bash
   psql "$DATABASE_URL" -c "\dt"
   ```

3. **Compression issue**
   - Try COMPRESSION_LEVEL=1 to rule out compression problems
   - Check disk space during backup

### Backups Stop Working After Working Fine

**Symptoms**:
- Backups worked, then suddenly stopped
- "No space left on device" error

**Diagnosis**:
```bash
# Check disk usage
railway run df -h

# Check backup service logs
railway logs
```

**Solutions**:

1. **Disk space exhausted**
   - Temporary backups consume disk space
   - Increase Railway service disk size
   - Verify backup files are being cleaned up

2. **S3 bucket full or quota exceeded**
   - Check S3 storage usage
   - Increase quota or clean up old backups

3. **Database grew significantly**
   - Backup now takes longer than interval
   - Increase BACKUP_INTERVAL
   - Optimize database (VACUUM, ANALYZE)

4. **Credentials rotated**
   - Check if S3 or database credentials changed
   - Update environment variables

### Old Backups Not Being Deleted

**Symptoms**:
- S3 bucket keeps growing
- Backups older than BACKUP_RETENTION_DAYS still present

**Diagnosis**:
```bash
# List all backups with dates
aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ --endpoint-url ${S3_ENDPOINT} --recursive
```

**Solutions**:

1. **Date parsing issue**
   - Backup script uses `date` command which varies by system
   - Check backup service logs for deletion attempts
   - Manually delete old backups:
   ```bash
   # List old backups
   CUTOFF_DATE=$(date -d "30 days ago" +%Y%m%d)
   aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ --endpoint-url ${S3_ENDPOINT} --recursive | \
     awk -v cutoff=$CUTOFF_DATE '$1 < cutoff {print $4}'

   # Delete old backups (review list first!)
   aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ --endpoint-url ${S3_ENDPOINT} --recursive | \
     awk -v cutoff=$CUTOFF_DATE '$1 < cutoff {print $4}' | \
     xargs -I {} aws s3 rm s3://${S3_BUCKET}/{} --endpoint-url ${S3_ENDPOINT}
   ```

2. **Insufficient delete permissions**
   - Verify S3 credentials have `s3:DeleteObject` permission

3. **Wrong date format**
   - Verify backup filenames match format: `backup_YYYYMMDD_HHMMSS.sql.gz`

## Verify Service Issues

### Verify Service Won't Start

**Symptoms**:
- Container exits immediately
- Same as backup service startup issues

**Solutions**:
- See [Backup Service Won't Start](#backup-service-wont-start)
- Additionally verify BACKUP_PREFIX matches backup service

### Verify Fails: "No backups found in S3"

**Symptoms**:
```
ERROR: No backups found in S3
```

**Diagnosis**:
```bash
# Check if backups exist
aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ --endpoint-url ${S3_ENDPOINT} --recursive
```

**Solutions**:

1. **Backup service not running**
   - Check backup service status
   - Wait for first backup to complete

2. **BACKUP_PREFIX mismatch**
   - Verify BACKUP_PREFIX in verify service matches backup service
   - Check for typos or extra slashes

3. **Wrong S3 credentials or bucket**
   - Verify S3_BUCKET, S3_ENDPOINT match backup service
   - Test S3 access:
   ```bash
   aws s3 ls s3://${S3_BUCKET} --endpoint-url ${S3_ENDPOINT}
   ```

### Verify Fails: "Cannot create temporary database"

**Symptoms**:
```
ERROR: permission denied to create database
```

**Diagnosis**:
```bash
# Test database creation
psql "$DATABASE_URL" -c "CREATE DATABASE test_db_12345;"
psql "$DATABASE_URL" -c "DROP DATABASE test_db_12345;"
```

**Solutions**:

1. **Insufficient permissions**
   ```bash
   # Grant CREATEDB permission
   psql -U postgres -c "ALTER USER verify_user CREATEDB;"
   ```

2. **DATABASE_URL points to specific database**
   - ❌ Wrong: `postgresql://user:pass@host:5432/myapp`
   - ✅ Correct: `postgresql://user:pass@host:5432/postgres`
   - Verify service should connect to `postgres` database

3. **Connection limit reached**
   - Check and increase max_connections
   - Verify old verify_* databases were cleaned up

### Verify Fails: "Restore failed"

**Symptoms**:
```
ERROR: Restore failed
```

**Diagnosis**:
```bash
# Download backup and test restore manually
aws s3 cp s3://${S3_BUCKET}/${BACKUP_PREFIX}/backup_latest.sql.gz ./test.gz --endpoint-url ${S3_ENDPOINT}
gunzip test.gz
psql -U postgres -c "CREATE DATABASE manual_test;"
psql -U postgres -d manual_test -f test.sql 2>&1 | tee restore.log
```

**Solutions**:

1. **Corrupted backup**
   - Check backup file integrity: `gunzip -t backup.sql.gz`
   - Verify backup service logs show successful backup
   - Try previous backup

2. **PostgreSQL version mismatch**
   - Backup from newer version might not restore to older version
   - Upgrade target PostgreSQL version
   - Use compatible pg_dump version

3. **Missing extensions**
   ```bash
   # Install required extensions
   psql "$DATABASE_URL" -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
   ```

4. **Insufficient disk space**
   - Restored database needs space
   - Increase disk allocation

### Temporary Databases Not Cleaned Up

**Symptoms**:
- Multiple `verify_*` databases exist
- Disk space filling up

**Diagnosis**:
```bash
# List all databases on verify server
psql "$VERIFY_DATABASE_URL" -c "\l" | grep verify_
```

**Solutions**:

1. **Verify service crashed during restore**
   - Cleanup manually:
   ```bash
   psql "$VERIFY_DATABASE_URL" -c "SELECT 'DROP DATABASE ' || datname || ';' FROM pg_database WHERE datname LIKE 'verify_%';"
   # Review output, then execute DROP commands
   ```

2. **Add automated cleanup**
   - Run periodic cleanup job:
   ```bash
   # Drop all verify_ databases older than 1 hour
   psql "$DATABASE_URL" <<EOF
   SELECT pg_terminate_backend(pid)
   FROM pg_stat_activity
   WHERE datname LIKE 'verify_%';

   SELECT 'DROP DATABASE ' || datname || ';'
   FROM pg_database
   WHERE datname LIKE 'verify_%';
   EOF
   ```

## S3 Connection Issues

### "Connection timed out"

**Symptoms**:
```
ERROR: Connection timed out
Could not connect to the endpoint URL
```

**Solutions**:

1. **Network connectivity**
   - Test with curl: `curl -I ${S3_ENDPOINT}`
   - Check firewall rules
   - Verify Railway has internet access

2. **Wrong endpoint**
   - Verify endpoint format
   - Check provider documentation

3. **DNS issues**
   - Try using IP address instead of hostname (if applicable)
   - Check DNS resolution: `nslookup $(echo $S3_ENDPOINT | sed 's|https\?://||')`

### "Access Denied"

**Symptoms**:
```
ERROR: Access Denied
Status Code: 403
```

**Solutions**:

1. **Wrong credentials**
   - Double-check access key and secret key
   - Verify no extra spaces

2. **Bucket policy**
   - Check bucket permissions allow your access key
   - Verify bucket is not public with deny policies

3. **IAM policy**
   - Verify IAM user/role has required permissions
   - Required: `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`

4. **Bucket in different region**
   - Verify S3_REGION matches bucket region (AWS)
   - Some providers ignore region

### SSL/TLS Certificate Errors

**Symptoms**:
```
ERROR: SSL certificate problem
unable to verify certificate
```

**Solutions**:

1. **Self-signed certificate (MinIO)**
   - For development only, disable SSL verification:
   ```bash
   export AWS_CA_BUNDLE=""
   ```
   - Or use HTTP instead of HTTPS

2. **Expired certificate**
   - Contact storage provider
   - Update certificates

3. **Certificate verification issues**
   - Update CA certificates in container:
   ```dockerfile
   RUN apk add --no-cache ca-certificates && update-ca-certificates
   ```

## Database Connection Issues

### "Connection refused"

**Symptoms**:
```
psql: could not connect to server: Connection refused
```

**Solutions**:

1. **Database not running**
   - Check database service status
   - Start database service

2. **Wrong host/port**
   - Verify DATABASE_URL has correct host and port
   - Default PostgreSQL port: 5432

3. **Firewall blocking**
   - Check firewall rules
   - Use Railway internal networking

### "Password authentication failed"

**Symptoms**:
```
psql: FATAL: password authentication failed for user "xxx"
```

**Solutions**:

1. **Wrong credentials**
   - Verify username and password in DATABASE_URL
   - Check for special characters that need URL encoding:
     - `@` → `%40`
     - `:` → `%3A`
     - `/` → `%2F`

2. **User doesn't exist**
   ```bash
   # Create user
   psql -U postgres -c "CREATE USER backup_user WITH PASSWORD 'secure_password';"
   ```

3. **pg_hba.conf restrictions**
   - Check PostgreSQL pg_hba.conf allows connections
   - May need to allow specific IP or use md5/scram-sha-256 auth

### "Too many connections"

**Symptoms**:
```
FATAL: sorry, too many clients already
```

**Solutions**:

1. **Increase max_connections**
   ```bash
   # Check current limit
   psql "$DATABASE_URL" -c "SHOW max_connections;"

   # Increase (requires restart)
   # In Railway: adjust PostgreSQL configuration
   ```

2. **Close idle connections**
   ```bash
   # Kill idle connections
   psql "$DATABASE_URL" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND state_change < NOW() - INTERVAL '1 hour';"
   ```

3. **Use connection pooling**
   - Deploy PgBouncer
   - Reduce number of connections per service

## Restore Issues

### Restore is Very Slow

**Symptoms**:
- Restore takes hours for small database
- CPU at 100%

**Solutions**:

1. **Index rebuilding**
   - Normal for large databases
   - Wait for completion
   - Monitor progress:
   ```bash
   psql "$DATABASE_URL" -c "SELECT pid, state, query FROM pg_stat_activity WHERE query LIKE '%CREATE INDEX%';"
   ```

2. **Insufficient resources**
   - Increase database server CPU/RAM
   - Use faster disk (SSD)

3. **Slow network**
   - Download backup closer to database server
   - Use faster network connection

### Restore Fails with Errors

**Symptoms**:
```
ERROR: relation "xxx" already exists
ERROR: must be owner of extension
```

**Solutions**:

1. **Database not empty**
   - Use clean database
   - Or use `--clean --if-exists` flags in pg_dump (already included)

2. **"must be owner" errors**
   - Safe to ignore (caused by --no-owner flag)
   - Or restore as superuser

3. **"role does not exist" errors**
   - Safe to ignore (caused by --no-owner flag)
   - Or create roles first:
   ```bash
   psql "$DATABASE_URL" -c "CREATE ROLE missing_role;"
   ```

## Performance Issues

### Backups Taking Too Long

**Symptoms**:
- Backup takes longer than BACKUP_INTERVAL
- Backups overlapping

**Solutions**:

1. **Increase BACKUP_INTERVAL**
   - Set to 2× current backup duration minimum

2. **Reduce database size**
   ```bash
   # Vacuum and analyze
   psql "$DATABASE_URL" -c "VACUUM FULL ANALYZE;"
   ```

3. **Reduce compression level**
   - Set COMPRESSION_LEVEL=1 for faster backups
   - Trade-off: larger files

4. **Exclude large tables**
   - Modify backup.sh to exclude specific tables
   - Add: `--exclude-table=large_table`

### S3 Upload is Slow

**Symptoms**:
- Backup completes quickly
- Upload takes hours

**Solutions**:

1. **Slow network**
   - Use S3 endpoint closer to database
   - Upgrade network connection

2. **Large files**
   - Reduce COMPRESSION_LEVEL
   - Exclude unnecessary tables

3. **S3 throttling**
   - Check S3 provider limits
   - Contact provider to increase limits

### High Memory Usage

**Symptoms**:
- Container OOM (Out of Memory) killed
- Railway service crashes

**Solutions**:

1. **Increase memory allocation**
   - Increase Railway service memory limit

2. **Reduce COMPRESSION_LEVEL**
   - Lower compression uses less memory

3. **Stream processing**
   - Backup script already streams (pg_dump | gzip)
   - Check for memory leaks in logs

## Configuration Issues

### Can't Find Configuration File

**Symptoms**:
- Need to change environment variables
- Don't know where they're set

**Solutions**:

**Railway**:
```bash
# List all variables
railway variables

# Set variable
railway variables set VAR_NAME=value

# Delete variable
railway variables delete VAR_NAME
```

**Docker**:
- Check `.env` file
- Check `docker-compose.yml`
- Check `docker run` command arguments

### Configuration Changes Not Taking Effect

**Symptoms**:
- Changed environment variable
- Service still using old value

**Solutions**:

1. **Restart service**
   ```bash
   # Railway
   railway restart

   # Docker
   docker-compose restart backup
   ```

2. **Verify variable was set**
   ```bash
   # Railway
   railway variables

   # Docker
   docker-compose exec backup env | grep VAR_NAME
   ```

3. **Check for typos**
   - Variable names are case-sensitive
   - `DATABASE_URL` not `database_url`

## Getting More Help

If issues persist:

1. **Check logs**
   ```bash
   # Railway
   railway logs

   # Docker
   docker logs <container-id>
   docker-compose logs backup
   ```

2. **Enable verbose logging**
   - Add to backup.sh: `set -x` (enables bash debug mode)
   - Add to pg_dump: `--verbose`

3. **Test components individually**
   - Test database connection
   - Test S3 connection
   - Test backup creation
   - Test backup upload

4. **Review documentation**
   - [Configuration Guide](configuration.md)
   - [Architecture](architecture.md)
   - [Restore Guide](restore.md)

5. **Open an issue**
   - [GitHub Issues](https://github.com/yourusername/postgres-backup-railway/issues)
   - Include: logs, configuration (redact secrets!), error messages

6. **Search existing issues**
   - Someone may have had the same problem
   - [Search Issues](https://github.com/yourusername/postgres-backup-railway/issues)

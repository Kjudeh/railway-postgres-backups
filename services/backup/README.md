# PostgreSQL Backup Service - Internal Developer Notes

## Overview

Production-grade PostgreSQL backup service that dumps databases to S3-compatible storage with retry logic, encryption support, and webhook notifications.

## Architecture

```
entrypoint.sh (main runner)
    ├── Loads lib/logging.sh
    ├── Loads lib/config.sh
    ├── Loads lib/utils.sh
    └── Runs backup.sh in a loop

backup.sh (backup workflow)
    1. Check connectivity (DB + S3)
    2. pg_dump -> gzip
    3. [Optional] encrypt with openssl AES-256-CBC
    4. Upload to S3 with exponential backoff retry
    5. Cleanup local files
    6. Prune old backups (retention policy)
    7. [Optional] Send webhook notification
```

## Files

### Core Scripts
- `entrypoint.sh` - Main runner, handles scheduling and graceful shutdown
- `backup.sh` - Core backup logic (dump -> compress -> encrypt -> upload -> prune)
- `healthcheck.sh` - Health check for Docker/Railway monitoring

### Libraries
- `lib/logging.sh` - Structured logging with secret scrubbing
- `lib/config.sh` - Configuration loading and validation
- `lib/utils.sh` - Utility functions (retry, webhook, formatting, connectivity checks)

### Configuration
- `.env.example` - Example configuration with all variables documented
- `Dockerfile` - Container image definition

## Development

### Local Development

1. **Setup environment**:
   ```bash
   cd services/backup
   cp .env.example .env
   # Edit .env with your values
   ```

2. **Build image**:
   ```bash
   docker build -t postgres-backup:dev .
   ```

3. **Run one-time backup**:
   ```bash
   docker run --env-file .env postgres-backup:dev once
   ```

4. **Run continuous backup**:
   ```bash
   docker run --env-file .env postgres-backup:dev backup
   ```

5. **Run health check**:
   ```bash
   docker run --env-file .env postgres-backup:dev healthcheck
   ```

### Testing

**Test database connectivity**:
```bash
docker run --env-file .env postgres-backup:dev \
  bash -c 'source /app/lib/logging.sh && source /app/lib/utils.sh && source /app/lib/config.sh && load_config && check_db_connectivity'
```

**Test S3 connectivity**:
```bash
docker run --env-file .env postgres-backup:dev \
  bash -c 'source /app/lib/logging.sh && source /app/lib/utils.sh && source /app/lib/config.sh && load_config && check_s3_connectivity'
```

**Test backup encryption**:
```bash
# Enable encryption in .env:
# BACKUP_ENCRYPTION=true
# BACKUP_ENCRYPTION_KEY=test-key-32-characters-minimum

docker run --env-file .env postgres-backup:dev once
```

**Test webhook**:
```bash
# Set webhook URL in .env:
# WEBHOOK_URL=https://webhook.site/unique-id
# WEBHOOK_ON_SUCCESS=true

docker run --env-file .env postgres-backup:dev once
```

### Debugging

Enable debug logging:
```bash
# In .env or environment:
DEBUG=true

docker run --env-file .env postgres-backup:dev backup
```

View logs:
```bash
# Follow logs
docker logs -f <container-id>

# Search for errors
docker logs <container-id> | grep ERROR

# Search for specific backup
docker logs <container-id> | grep "backup_20240207"
```

## Configuration

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://user:pass@host:5432/db` |
| `S3_ENDPOINT` | S3 storage endpoint | `https://s3.amazonaws.com` |
| `S3_BUCKET` | S3 bucket name | `my-postgres-backups` |
| `S3_ACCESS_KEY_ID` | S3 access key | `AKIAIOSFODNN7EXAMPLE` |
| `S3_SECRET_ACCESS_KEY` | S3 secret key | `wJalrXUtnFEMI/K7MDENG...` |

**Or** use individual PG variables:
- `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_INTERVAL` | `3600` | Seconds between backups |
| `BACKUP_RETENTION_DAYS` | `7` | Days to keep backups |
| `COMPRESSION_LEVEL` | `6` | Gzip level (1-9) |
| `BACKUP_ENCRYPTION` | `false` | Enable encryption |
| `BACKUP_ENCRYPTION_KEY` | - | Encryption key (if enabled) |
| `WEBHOOK_URL` | - | Webhook notification URL |
| `RETRY_ATTEMPTS` | `3` | S3 upload retry attempts |
| `RETRY_DELAY` | `5` | Initial retry delay (seconds) |

See `.env.example` for complete list.

## How It Works

### Backup Workflow

1. **Connectivity Check**
   - Verify database is reachable (`pg_isready`)
   - Verify S3 bucket is accessible (`aws s3 ls`)

2. **Database Dump**
   ```bash
   pg_dump -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE \
     --no-owner --no-acl --clean --if-exists \
     | gzip -6 > /tmp/backup_20240207_143022.sql.gz
   ```

3. **Optional Encryption**
   ```bash
   openssl enc -aes-256-cbc -salt -pbkdf2 \
     -in backup.sql.gz \
     -out backup.sql.gz.enc \
     -pass "pass:$BACKUP_ENCRYPTION_KEY"
   ```

4. **Upload to S3**
   ```bash
   aws s3 cp backup.sql.gz "s3://bucket/prefix/backup_20240207_143022.sql.gz" \
     --endpoint-url $S3_ENDPOINT \
     --metadata "timestamp=2024-02-07T14:30:22Z,database=mydb,host=localhost"
   ```

5. **Retry Logic**
   - Attempt 1: Upload
   - If fail, wait 5s, retry
   - If fail, wait 10s, retry
   - If fail, wait 20s, retry
   - After 3 attempts, mark as failed

6. **Cleanup**
   ```bash
   rm -f /tmp/backup_20240207_143022.sql.gz*
   ```

7. **Retention Pruning**
   - List all backups in S3
   - Extract date from filename
   - Delete backups older than BACKUP_RETENTION_DAYS
   ```bash
   # Example: Delete backups older than 7 days
   for backup in $(aws s3 ls s3://bucket/prefix/); do
     if [[ date < cutoff_date ]]; then
       aws s3 rm "s3://bucket/prefix/$backup"
     fi
   done
   ```

### Logging

All logs follow the format:
```
YYYY-MM-DDTHH:MM:SSZ LEVEL message
```

Example:
```
2024-02-07T14:30:22Z INFO Starting backup: backup_20240207_143022.sql.gz
2024-02-07T14:30:24Z INFO Creating database dump...
2024-02-07T14:30:45Z INFO Dump completed in 21s, size: 524MB
2024-02-07T14:30:45Z INFO Uploading to S3...
2024-02-07T14:32:15Z INFO Upload completed in 90s
2024-02-07T14:32:15Z SUCCESS Backup completed successfully in 113s
```

**Secret Scrubbing**: Passwords, keys, and credentials are automatically scrubbed from logs.

### Error Handling

**Fatal Errors** (exit code 1):
- Missing required environment variables
- Invalid DATABASE_URL format
- Invalid configuration values

**Non-Fatal Errors** (logged, retry on next interval):
- Database connectivity failure
- S3 connectivity failure
- pg_dump failure
- S3 upload failure
- Encryption failure

**Warnings** (logged, continue):
- Retention pruning failure
- Webhook send failure

## Troubleshooting

### Backup Not Running

**Check container is running**:
```bash
docker ps | grep backup
railway logs --service backup
```

**Check logs for errors**:
```bash
docker logs <container-id>
```

**Common issues**:
- Missing environment variables (check .env)
- Invalid DATABASE_URL format
- Database not accessible
- S3 credentials invalid

### Backup Fails to Upload

**Test S3 connectivity**:
```bash
aws s3 ls s3://$S3_BUCKET --endpoint-url $S3_ENDPOINT
```

**Check**:
- S3 credentials are correct
- S3 bucket exists
- S3_ENDPOINT is correct
- Network connectivity to S3

### Backups Are Empty

**Check**:
- Database has data
- User has read permissions on all tables
- pg_dump completed successfully (check logs)

**Grant permissions**:
```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO backup_user;
```

### Old Backups Not Deleted

**Check**:
- BACKUP_RETENTION_DAYS is set
- S3 credentials have delete permission
- Backup filenames match format: `backup_YYYYMMDD_HHMMSS.sql.gz`

**Manual cleanup**:
```bash
# List all backups
aws s3 ls s3://$S3_BUCKET/$BACKUP_PREFIX/ --endpoint-url $S3_ENDPOINT --recursive

# Delete specific backup
aws s3 rm s3://$S3_BUCKET/$BACKUP_PREFIX/backup_20240101_000000.sql.gz \
  --endpoint-url $S3_ENDPOINT
```

### Encryption Not Working

**Check**:
- BACKUP_ENCRYPTION=true
- BACKUP_ENCRYPTION_KEY is set (32+ characters)
- Encrypted files have .enc extension
- openssl is installed in container

**Decrypt manually**:
```bash
openssl enc -aes-256-cbc -d -pbkdf2 \
  -in backup.sql.gz.enc \
  -out backup.sql.gz \
  -pass "pass:$BACKUP_ENCRYPTION_KEY"
```

## Performance

### Backup Duration

Typical duration for 1GB database:
- Dump: 1-2 minutes
- Compress: 30-60 seconds
- Encrypt: 10-20 seconds (if enabled)
- Upload: 1-3 minutes (depends on connection)
- **Total**: ~3-6 minutes

### Resource Usage

Typical resource usage:
- CPU: 10-30% during backup, <1% idle
- Memory: 64-256 MB
- Disk: 2× backup size (temporary storage)
- Network: 1-10 Mbps upload

### Optimization

**Faster backups**:
- Decrease COMPRESSION_LEVEL (1-3)
- Use faster network connection
- Use SSD storage
- Increase CPU allocation

**Smaller backups**:
- Increase COMPRESSION_LEVEL (8-9)
- Enable encryption (adds ~5% overhead)
- Exclude unnecessary tables:
  ```bash
  # Modify backup.sh to add:
  pg_dump --exclude-table=logs --exclude-table=temp_data ...
  ```

## Security

### Best Practices

1. **Credentials**
   - Never commit .env to git
   - Rotate S3 credentials every 90 days
   - Rotate database passwords every 90 days
   - Use Railway encrypted environment variables

2. **S3 Bucket**
   - Enable server-side encryption
   - Use bucket policies to restrict access
   - Enable versioning for backup protection
   - Disable public access

3. **Database**
   - Use SSL/TLS for connections
   - Use least privilege (SELECT only for backup user)
   - Strong passwords (20+ characters)

4. **Encryption**
   - Use strong encryption key (32+ characters, random)
   - Store encryption key securely (not in git)
   - Lost encryption key = lost backups

### Threat Model

**Mitigated**:
- ✅ Credentials in logs (auto-scrubbed)
- ✅ Credentials in code (environment variables only)
- ✅ Credentials in git (.gitignore)

**User Responsibility**:
- ⚠️ S3 bucket security (encryption, access control)
- ⚠️ Encryption key management
- ⚠️ Network security (SSL/TLS)

## Extending

### Adding Custom Backup Logic

Edit `backup.sh` to add custom logic:

```bash
# After backup completed, before cleanup
if [ "$CUSTOM_POST_BACKUP" = "true" ]; then
    # Your custom logic here
    log_info "Running custom post-backup logic..."
    /path/to/custom-script.sh "$backup_path"
fi
```

### Custom Verification

Add custom verification before upload:

```bash
# In perform_dump function, after dump completes
# Verify dump contains expected data
if ! gunzip -c "$output_file" | grep -q "CREATE TABLE users"; then
    log_error "Backup verification failed: missing users table"
    return 1
fi
```

### Multiple Databases

Deploy multiple instances with different DATABASE_URL and BACKUP_PREFIX:

```bash
# Instance 1
DATABASE_URL=postgresql://user:pass@host:5432/db1
BACKUP_PREFIX=db1/backups

# Instance 2
DATABASE_URL=postgresql://user:pass@host:5432/db2
BACKUP_PREFIX=db2/backups
```

## Changelog

### v1.0.0
- Initial implementation
- pg_dump -> gzip -> S3 workflow
- Retry with exponential backoff
- Optional encryption (AES-256-CBC)
- Webhook notifications
- Retention pruning
- Structured logging
- Secret scrubbing
- Health checks

## References

- [PostgreSQL pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html)
- [AWS CLI S3 commands](https://docs.aws.amazon.com/cli/latest/reference/s3/)
- [OpenSSL encryption](https://www.openssl.org/docs/man1.1.1/man1/enc.html)

---

**Maintainer**: Infrastructure Team
**Last Updated**: 2024-02-07
**Version**: 1.0.0

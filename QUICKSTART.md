# Quick Start Guide

Get up and running with PostgreSQL Backup & Restore Verification in 5 minutes.

## Prerequisites

- PostgreSQL database (Railway, AWS RDS, or self-hosted)
- S3-compatible storage (AWS S3, Backblaze B2, MinIO, etc.)
- Docker (for local testing)

## Option 1: Deploy to Railway (Recommended)

### Step 1: Deploy PostgreSQL
```bash
# If you don't have a PostgreSQL database yet
railway init
railway add postgres
```

### Step 2: Deploy Backup Service

1. Clone this repository:
```bash
git clone https://github.com/yourusername/postgres-backup-railway.git
cd postgres-backup-railway
```

2. Configure environment variables in Railway:
```bash
railway variables set DATABASE_URL="postgresql://user:pass@host:5432/db"
railway variables set S3_ENDPOINT="https://s3.amazonaws.com"
railway variables set S3_BUCKET="my-backups"
railway variables set S3_ACCESS_KEY_ID="your-key"
railway variables set S3_SECRET_ACCESS_KEY="your-secret"
```

3. Deploy:
```bash
railway up
```

### Step 3: Deploy Verify Service (Optional but Recommended)

```bash
# Same environment variables as backup service
railway up --service verify
```

### Step 4: Verify Everything Works

```bash
# Check logs
railway logs --service backup
railway logs --service verify

# You should see:
# - "Backup completed successfully"
# - "Restore verification completed successfully"
```

## Option 2: Docker Compose (Local Testing)

### Step 1: Configure Environment

```bash
cd services/backup
cp .env.example .env
# Edit .env with your values

cd ../verify
cp .env.example .env
# Edit .env with your values
```

### Step 2: Run Tests

```bash
cd tests
./run-tests.sh
```

This will:
- Start PostgreSQL and MinIO
- Run backup service
- Run verify service
- Validate everything works

## Option 3: Manual Docker

### Backup Service

```bash
cd services/backup

# Build
docker build -t postgres-backup .

# Run
docker run --env-file .env postgres-backup
```

### Verify Service

```bash
cd services/verify

# Build
docker build -t postgres-verify .

# Run
docker run --env-file .env postgres-verify
```

## Configuration

### Minimum Required Environment Variables

**Backup Service:**
```bash
DATABASE_URL=postgresql://user:pass@host:5432/db
S3_ENDPOINT=https://s3.amazonaws.com
S3_BUCKET=my-backups
S3_ACCESS_KEY_ID=your-key
S3_SECRET_ACCESS_KEY=your-secret
```

**Verify Service:**
```bash
DATABASE_URL=postgresql://user:pass@host:5432/postgres  # Note: connect to 'postgres' db
S3_ENDPOINT=https://s3.amazonaws.com
S3_BUCKET=my-backups
S3_ACCESS_KEY_ID=your-key
S3_SECRET_ACCESS_KEY=your-secret
```

### Common Optional Variables

```bash
# Backup every 6 hours instead of every hour
BACKUP_INTERVAL=21600

# Keep backups for 30 days instead of 7
BACKUP_RETENTION_DAYS=30

# Verify every 12 hours instead of every 24
VERIFY_INTERVAL=43200
```

See [Configuration Guide](docs/configuration.md) for all options.

## Verify It's Working

### Check Backups Exist

```bash
aws s3 ls s3://your-bucket/postgres-backups/ \
  --endpoint-url https://your-s3-endpoint \
  --recursive
```

You should see files like:
```
2024-02-07 10:00:00  524288000 postgres-backups/backup_20240207_100000.sql.gz
2024-02-07 11:00:00  524288000 postgres-backups/backup_20240207_110000.sql.gz
```

### Test Manual Restore

```bash
# Download latest backup
aws s3 cp s3://your-bucket/postgres-backups/backup_LATEST.sql.gz . \
  --endpoint-url https://your-s3-endpoint

# Test restore to temporary database
gunzip backup_LATEST.sql.gz
psql -h your-host -U postgres -c "CREATE DATABASE restore_test;"
psql -h your-host -U postgres -d restore_test -f backup_LATEST.sql

# Verify
psql -h your-host -U postgres -d restore_test -c "\dt"

# Cleanup
psql -h your-host -U postgres -c "DROP DATABASE restore_test;"
rm backup_LATEST.sql
```

## Common Issues

### "Cannot connect to database"
- Verify `DATABASE_URL` is correct
- Check database is running
- Verify network connectivity

### "Cannot connect to S3"
- Verify S3 credentials
- Check `S3_ENDPOINT` format (must include `https://`)
- Verify bucket exists

### "Permission denied"
- Backup service needs: `SELECT` on all tables
- Verify service needs: `CREATEDB` permission

See [Troubleshooting Guide](docs/troubleshooting.md) for more help.

## Next Steps

1. **Configure Alerts**: Set up monitoring for backup failures
2. **Test Restore**: Run a test restore drill (see [Restore Guide](docs/restore.md))
3. **Review Security**: Check [SECURITY.md](SECURITY.md)
4. **Read Documentation**:
   - [Architecture](docs/architecture.md)
   - [Configuration](docs/configuration.md)
   - [Troubleshooting](docs/troubleshooting.md)
   - [Runbooks](docs/runbooks.md)

## Support

- [Documentation](docs/)
- [GitHub Issues](https://github.com/yourusername/postgres-backup-railway/issues)
- [Discussions](https://github.com/yourusername/postgres-backup-railway/discussions)

## Important Reminders

**Untested backups are worthless!**
- Enable the verify service
- Run regular restore drills
- Monitor verification logs

**Security matters!**
- Never commit credentials
- Rotate credentials every 90 days
- Enable S3 encryption
- Use SSL/TLS for database connections

**Monitor your backups!**
- Check backup logs daily
- Verify backup sizes are reasonable
- Ensure old backups are being deleted
- Monitor S3 storage costs

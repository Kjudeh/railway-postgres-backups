# Configuration Guide

Complete configuration reference for the PostgreSQL Backup and Restore Drill system.

## Table of Contents

- [Overview](#overview)
- [Environment Variables](#environment-variables)
  - [Database Configuration](#database-configuration)
  - [S3 Storage Configuration](#s3-storage-configuration)
  - [Backup Service Configuration](#backup-service-configuration)
  - [Verify Service Configuration](#verify-service-configuration)
- [Configuration Examples](#configuration-examples)
- [S3 Provider Setup](#s3-provider-setup)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting Configuration](#troubleshooting-configuration)

## Overview

This system uses environment variables for all configuration. No configuration files are required. All services share a common configuration approach optimized for Railway deployment.

### Configuration Principles

1. **Environment Variables Only**: All configuration via environment variables
2. **Sensible Defaults**: Most variables have production-ready defaults
3. **Railway Native**: Optimized for Railway's environment variable system
4. **DATABASE_URL First**: Prefers Railway's native DATABASE_URL format
5. **No Secrets in Code**: All sensitive values via environment variables
6. **No Secrets in Logs**: Automatic credential scrubbing

## Environment Variables

### Database Configuration

#### Primary Method: DATABASE_URL (Recommended)

| Variable | Required | Default | Description | Example |
|----------|----------|---------|-------------|---------|
| `DATABASE_URL` | **Yes** (or use PG* vars) | - | PostgreSQL connection string in Railway format | `postgresql://user:pass@host:5432/db` |

**Format**: `postgresql://username:password@hostname:port/database`

**Railway**: Automatically provided when you add a PostgreSQL database to your project.

**Example**:
```bash
DATABASE_URL=postgresql://postgres:securepass123@prod-db.railway.internal:5432/myapp_production
```

#### Alternative Method: Individual PostgreSQL Variables

Use these if `DATABASE_URL` is not available:

| Variable | Required | Default | Description | Example |
|----------|----------|---------|-------------|---------|
| `PGHOST` | **Yes** (if no DATABASE_URL) | - | Database hostname or IP | `localhost`, `prod-db.railway.internal` |
| `PGPORT` | No | `5432` | Database port | `5432` |
| `PGUSER` | **Yes** (if no DATABASE_URL) | - | Database username | `postgres`, `backup_user` |
| `PGPASSWORD` | **Yes** (if no DATABASE_URL) | - | Database password | `securepassword123` |
| `PGDATABASE` | **Yes** (if no DATABASE_URL) | - | Database name | `myapp_production` |

**Example**:
```bash
PGHOST=prod-db.railway.internal
PGPORT=5432
PGUSER=postgres
PGPASSWORD=securepass123
PGDATABASE=myapp_production
```

**Note**: If both `DATABASE_URL` and `PG*` variables are provided, `DATABASE_URL` takes precedence.

### S3 Storage Configuration

Required for storing backups in S3-compatible storage.

| Variable | Required | Default | Description | Example |
|----------|----------|---------|-------------|---------|
| `S3_ENDPOINT` | **Yes** | - | S3-compatible storage endpoint (without bucket) | `https://s3.amazonaws.com` |
| `S3_BUCKET` | **Yes** | - | S3 bucket name for storing backups | `my-postgres-backups` |
| `S3_ACCESS_KEY_ID` | **Yes** | - | S3 access key ID | `AKIAIOSFODNN7EXAMPLE` |
| `S3_SECRET_ACCESS_KEY` | **Yes** | - | S3 secret access key | `wJalrXUtnFEMI/K7MDENG...` |
| `S3_REGION` | No | `us-east-1` | AWS region or region identifier | `us-east-1`, `us-west-002` |

**S3 Endpoint Examples**:
- AWS S3: `https://s3.amazonaws.com` or `https://s3.{region}.amazonaws.com`
- Backblaze B2: `https://s3.us-west-002.backblazeb2.com`
- DigitalOcean Spaces: `https://nyc3.digitaloceanspaces.com`
- Cloudflare R2: `https://{account-id}.r2.cloudflarestorage.com`
- Wasabi: `https://s3.wasabisys.com` or `https://s3.{region}.wasabisys.com`
- MinIO (local): `http://localhost:9000`

**Security Note**: Never commit S3 credentials to git. Use Railway's encrypted environment variables.

### Backup Service Configuration

Controls the automated backup service (`services/backup`).

#### Core Settings

| Variable | Required | Default | Description | Example |
|----------|----------|---------|-------------|---------|
| `BACKUP_INTERVAL` | No | `3600` | Seconds between backups (minimum: 60) | `21600` (6 hours) |
| `BACKUP_RETENTION_DAYS` | No | `7` | Days to keep backups (minimum: 1) | `30` |
| `BACKUP_PREFIX` | No | `postgres-backups` | S3 key prefix for organizing backups | `production/postgres/backups` |
| `COMPRESSION_LEVEL` | No | `6` | Gzip compression level (1-9) | `9` (maximum compression) |

**Backup Interval Examples**:
- `300` = 5 minutes (testing only)
- `3600` = 1 hour (default)
- `21600` = 6 hours
- `43200` = 12 hours
- `86400` = 24 hours

**Compression Level**:
- `1-3`: Faster backups, larger files
- `6`: Balanced (recommended)
- `7-9`: Slower backups, smaller files

#### Encryption Settings (Optional)

| Variable | Required | Default | Description | Example |
|----------|----------|---------|-------------|---------|
| `BACKUP_ENCRYPTION` | No | `false` | Enable AES-256-CBC encryption | `true` |
| `BACKUP_ENCRYPTION_KEY` | **Yes** (if encryption enabled) | - | Encryption key (32+ characters recommended) | `your-secure-encryption-key-min-32-chars` |

**Encryption Notes**:
- Uses AES-256-CBC with PBKDF2 key derivation
- Encrypted backups have `.enc` extension
- **Lost encryption key = lost backups** - store securely
- Consider using Railway secrets or external secrets manager

#### Webhook Notifications (Optional)

| Variable | Required | Default | Description | Example |
|----------|----------|---------|-------------|---------|
| `WEBHOOK_URL` | No | - | Webhook URL for notifications | `https://hooks.slack.com/services/...` |
| `WEBHOOK_ON_SUCCESS` | No | `false` | Send webhook on successful backups | `true` |
| `WEBHOOK_ON_FAILURE` | No | `true` | Send webhook on failed backups | `true` |

**Supported Webhook Types**:
- Slack incoming webhooks
- Discord webhooks
- Microsoft Teams webhooks
- Custom HTTP endpoints (accepts JSON POST)

**Webhook Payload Format**:
```json
{
  "status": "success",
  "message": "Backup completed successfully",
  "timestamp": "2024-02-07T14:30:22Z",
  "backup_file": "backup_20240207_143022.sql.gz",
  "backup_size": "524MB",
  "duration_seconds": 113
}
```

#### Retry Configuration

| Variable | Required | Default | Description | Example |
|----------|----------|---------|-------------|---------|
| `RETRY_ATTEMPTS` | No | `3` | Number of retry attempts for S3 upload | `5` |
| `RETRY_DELAY` | No | `5` | Initial retry delay in seconds (exponential backoff) | `10` |

**Exponential Backoff**:
- Attempt 1: Upload
- Fail → Wait `RETRY_DELAY` seconds (5s)
- Attempt 2: Upload
- Fail → Wait `RETRY_DELAY * 2` seconds (10s)
- Attempt 3: Upload
- Fail → Wait `RETRY_DELAY * 4` seconds (20s)
- After `RETRY_ATTEMPTS`, mark as failed

#### Debugging

| Variable | Required | Default | Description | Example |
|----------|----------|---------|-------------|---------|
| `DEBUG` | No | `false` | Enable debug logging | `true` |

**Debug Mode**:
- Shows detailed logs for all operations
- Includes database connection details (credentials scrubbed)
- Shows S3 upload progress
- Displays retry attempts
- Not recommended for production (verbose logs)

### Verify Service Configuration

Controls the restore drill/verification service (`services/verify` - to be implemented).

| Variable | Required | Default | Description | Example |
|----------|----------|---------|-------------|---------|
| `VERIFY_INTERVAL` | No | `86400` | Seconds between restore drills (minimum: 3600) | `86400` (24 hours) |
| `VERIFY_DATABASE_SUFFIX` | No | `_restore_drill` | Suffix for temporary restore databases | `_test_restore` |
| `VERIFY_RETENTION_HOURS` | No | `1` | Hours to keep temporary databases (cleanup) | `2` |
| `VERIFY_LATEST_N_BACKUPS` | No | `1` | Number of latest backups to verify | `3` |
| `VERIFY_WEBHOOK_URL` | No | - | Separate webhook for restore drill results | `https://...` |
| `VERIFY_ON_FAILURE_ONLY` | No | `true` | Only send webhook on verification failures | `false` |

**Note**: Verify service shares database and S3 configuration with backup service.

## Configuration Examples

### Example 1: Basic Development Setup

Simple configuration for local development with MinIO.

```bash
# Database
DATABASE_URL=postgresql://postgres:password@localhost:5432/testdb

# S3 Storage (MinIO)
S3_ENDPOINT=http://localhost:9000
S3_BUCKET=test-backups
S3_ACCESS_KEY_ID=minioadmin
S3_SECRET_ACCESS_KEY=minioadmin123
S3_REGION=us-east-1

# Backup Service
BACKUP_INTERVAL=300           # 5 minutes for testing
BACKUP_RETENTION_DAYS=1       # Keep only 1 day
COMPRESSION_LEVEL=6
DEBUG=true                    # Enable debug logging
```

### Example 2: Production AWS S3

Production configuration with AWS S3, encryption, and webhooks.

```bash
# Database (Railway provides this automatically)
DATABASE_URL=postgresql://produser:securepass@prod-db.railway.internal:5432/myapp_prod

# S3 Storage (AWS)
S3_ENDPOINT=https://s3.amazonaws.com
S3_BUCKET=mycompany-postgres-backups
S3_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
S3_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
S3_REGION=us-east-1

# Backup Service
BACKUP_INTERVAL=21600                    # 6 hours
BACKUP_RETENTION_DAYS=90                 # 90 days for compliance
BACKUP_PREFIX=production/postgres/backups
COMPRESSION_LEVEL=9                      # Maximum compression

# Encryption
BACKUP_ENCRYPTION=true
BACKUP_ENCRYPTION_KEY=super-secure-random-key-with-at-least-32-characters

# Webhooks (Slack)
WEBHOOK_URL=https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX
WEBHOOK_ON_SUCCESS=true
WEBHOOK_ON_FAILURE=true

# Retry
RETRY_ATTEMPTS=5
RETRY_DELAY=10
```

### Example 3: Backblaze B2

Using Backblaze B2 for cost-effective backup storage.

```bash
# Database
DATABASE_URL=postgresql://user:pass@db.railway.internal:5432/myapp

# S3 Storage (Backblaze B2)
S3_ENDPOINT=https://s3.us-west-002.backblazeb2.com
S3_BUCKET=myapp-postgres-backups
S3_ACCESS_KEY_ID=002abc123def456789000000f  # B2 keyID
S3_SECRET_ACCESS_KEY=K002abcDEF...          # B2 applicationKey
S3_REGION=us-west-002

# Backup Service
BACKUP_INTERVAL=43200        # 12 hours
BACKUP_RETENTION_DAYS=30
BACKUP_PREFIX=postgres-backups
COMPRESSION_LEVEL=7
```

### Example 4: Multi-Database Setup

Deploy multiple backup service instances with different configurations.

**Instance 1 (Production Database)**:
```bash
DATABASE_URL=postgresql://user:pass@prod-db.railway.internal:5432/production_db
S3_ENDPOINT=https://s3.amazonaws.com
S3_BUCKET=company-backups
S3_ACCESS_KEY_ID=AKIA...
S3_SECRET_ACCESS_KEY=...
BACKUP_PREFIX=production/db/backups
BACKUP_INTERVAL=21600        # 6 hours
BACKUP_RETENTION_DAYS=90
BACKUP_ENCRYPTION=true
BACKUP_ENCRYPTION_KEY=prod-key-32-chars-minimum
```

**Instance 2 (Staging Database)**:
```bash
DATABASE_URL=postgresql://user:pass@staging-db.railway.internal:5432/staging_db
S3_ENDPOINT=https://s3.amazonaws.com
S3_BUCKET=company-backups
S3_ACCESS_KEY_ID=AKIA...
S3_SECRET_ACCESS_KEY=...
BACKUP_PREFIX=staging/db/backups
BACKUP_INTERVAL=43200        # 12 hours
BACKUP_RETENTION_DAYS=14
BACKUP_ENCRYPTION=false
```

### Example 5: Cloudflare R2

Using Cloudflare R2 for zero-egress backup storage.

```bash
# Database
DATABASE_URL=postgresql://user:pass@db.railway.internal:5432/myapp

# S3 Storage (Cloudflare R2)
S3_ENDPOINT=https://abc123def456.r2.cloudflarestorage.com
S3_BUCKET=postgres-backups
S3_ACCESS_KEY_ID=your-r2-access-key-id
S3_SECRET_ACCESS_KEY=your-r2-secret-access-key
S3_REGION=auto  # R2 uses 'auto'

# Backup Service
BACKUP_INTERVAL=21600
BACKUP_RETENTION_DAYS=30
COMPRESSION_LEVEL=6
```

## S3 Provider Setup

### AWS S3

**1. Create S3 Bucket**:
```bash
aws s3 mb s3://my-postgres-backups --region us-east-1
```

**2. Create IAM User**:
- Navigate to IAM → Users → Add user
- Select "Programmatic access"
- Attach policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-postgres-backups",
        "arn:aws:s3:::my-postgres-backups/*"
      ]
    }
  ]
}
```

**3. Enable Server-Side Encryption** (Recommended):
- Navigate to bucket → Properties → Default encryption
- Choose "AES-256" or "AWS-KMS"

**4. Configure**:
```bash
S3_ENDPOINT=https://s3.amazonaws.com
S3_BUCKET=my-postgres-backups
S3_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
S3_SECRET_ACCESS_KEY=wJalr...
S3_REGION=us-east-1
```

### Backblaze B2

**1. Create Bucket**:
- Log in to Backblaze B2
- Buckets → Create a Bucket
- Set to "Private"

**2. Create Application Key**:
- App Keys → Add a New Application Key
- Select your bucket
- Grant permissions: `listBuckets`, `listFiles`, `readFiles`, `writeFiles`, `deleteFiles`
- Save keyID and applicationKey

**3. Configure**:
```bash
S3_ENDPOINT=https://s3.us-west-002.backblazeb2.com  # Check your bucket's region
S3_BUCKET=my-postgres-backups
S3_ACCESS_KEY_ID=002abc123def456789000000f  # keyID
S3_SECRET_ACCESS_KEY=K002abcDEF...          # applicationKey
S3_REGION=us-west-002
```

**Note**: Use S3-compatible API endpoint, not native B2 API.

### DigitalOcean Spaces

**1. Create Space**:
- Navigate to Spaces → Create Space
- Choose region
- Enable CDN (optional)

**2. Create API Key**:
- API → Spaces access keys → Generate New Key
- Save key and secret

**3. Configure**:
```bash
S3_ENDPOINT=https://nyc3.digitaloceanspaces.com  # Use your region
S3_BUCKET=my-postgres-backups
S3_ACCESS_KEY_ID=DO00ABCD...
S3_SECRET_ACCESS_KEY=secret...
S3_REGION=nyc3
```

### Cloudflare R2

**1. Create Bucket**:
- R2 → Create bucket
- Enter bucket name

**2. Create API Token**:
- R2 → Manage R2 API Tokens → Create API token
- Permissions: Object Read & Write
- Save Access Key ID and Secret Access Key

**3. Get Account ID**:
- Find your account ID in R2 dashboard URL or settings

**4. Configure**:
```bash
S3_ENDPOINT=https://abc123def456.r2.cloudflarestorage.com  # Account ID in URL
S3_BUCKET=postgres-backups
S3_ACCESS_KEY_ID=your-key-id
S3_SECRET_ACCESS_KEY=your-secret
S3_REGION=auto
```

### MinIO (Self-Hosted / Local Development)

**1. Install MinIO**:
```bash
# Docker
docker run -p 9000:9000 -p 9001:9001 \
  -e "MINIO_ROOT_USER=minioadmin" \
  -e "MINIO_ROOT_PASSWORD=minioadmin123" \
  minio/minio server /data --console-address ":9001"
```

**2. Create Bucket**:
- Open http://localhost:9001
- Login with minioadmin/minioadmin123
- Buckets → Create Bucket → `test-backups`

**3. Configure**:
```bash
S3_ENDPOINT=http://localhost:9000
S3_BUCKET=test-backups
S3_ACCESS_KEY_ID=minioadmin
S3_SECRET_ACCESS_KEY=minioadmin123
S3_REGION=us-east-1
```

## Security Best Practices

### 1. Credential Management

**DO**:
- Use Railway's encrypted environment variables
- Rotate credentials every 90 days
- Use separate credentials for each environment
- Store encryption keys securely (separate from backups)
- Use secrets management systems (AWS Secrets Manager, HashiCorp Vault)

**DON'T**:
- Commit `.env` files to git
- Share credentials via email or Slack
- Use the same credentials across environments
- Store credentials in code or config files
- Use weak or default passwords

### 2. S3 Bucket Security

**Required**:
- Enable server-side encryption
- Disable public access
- Use bucket policies to restrict access
- Enable versioning (backup protection)
- Enable access logging

**Example Bucket Policy** (AWS S3):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::my-backups",
        "arn:aws:s3:::my-backups/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

### 3. Database Security

**Connection Security**:
- Use SSL/TLS for database connections
- Add `?sslmode=require` to DATABASE_URL if supported
- Restrict database access by IP when possible
- Use strong passwords (20+ characters)

**Backup User Permissions**:
- Create dedicated backup user with minimal permissions
- Grant only SELECT on required tables:

```sql
-- Create backup user
CREATE USER backup_user WITH PASSWORD 'secure-password-20-chars';

-- Grant read-only access
GRANT CONNECT ON DATABASE myapp_production TO backup_user;
GRANT USAGE ON SCHEMA public TO backup_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO backup_user;

-- For future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO backup_user;
```

### 4. Encryption

**Backup Encryption**:
- Use strong encryption keys (32+ characters, random)
- Store encryption key separately from backups
- Document encryption key storage location
- Test decryption regularly
- **Remember**: Lost key = lost backups

**Generate Secure Keys**:
```bash
# Linux/macOS
openssl rand -base64 32

# Or use password generator with 32+ characters
# Store in Railway environment variables or secrets manager
```

### 5. Network Security

**HTTPS Only**:
- Always use HTTPS for S3 endpoints
- Verify SSL/TLS certificates
- Consider using VPN or private networking for database access

**Railway Internal Networking**:
- Use Railway's internal networking for database connections
- Database URLs like `postgres://prod-db.railway.internal:5432/db` stay within Railway's private network

## Troubleshooting Configuration

### Issue: "DATABASE_URL not set"

**Cause**: Missing database configuration

**Fix**:
```bash
# Option 1: Use DATABASE_URL
DATABASE_URL=postgresql://user:pass@host:5432/db

# Option 2: Use PG* variables
PGHOST=localhost
PGUSER=postgres
PGPASSWORD=password
PGDATABASE=mydb
```

### Issue: "Invalid DATABASE_URL format"

**Cause**: Malformed connection string

**Fix**: Ensure format is `postgresql://username:password@hostname:port/database`

**Valid Examples**:
```
postgresql://postgres:pass@localhost:5432/mydb
postgresql://user:p@ssw0rd@db.railway.internal:5432/production
postgres://user:pass@host:5432/db  # 'postgres://' also works
```

**Invalid Examples**:
```
postgresql://localhost:5432/mydb  # Missing username and password
postgresql://user@localhost/mydb   # Missing password and port
```

### Issue: "S3 connectivity check failed"

**Causes**:
1. Invalid S3 credentials
2. Wrong S3 endpoint
3. Bucket doesn't exist
4. Network connectivity issues

**Diagnosis**:
```bash
# Test with AWS CLI
aws s3 ls s3://your-bucket \
  --endpoint-url https://your-endpoint \
  --region your-region

# Check environment variables
echo $S3_ENDPOINT
echo $S3_BUCKET
echo $S3_ACCESS_KEY_ID
# Don't echo secret!
```

**Fix**:
- Verify S3_ENDPOINT is correct for your provider
- Ensure bucket exists
- Check credentials have correct permissions
- Verify S3_REGION matches bucket region

### Issue: "Database connectivity check failed"

**Causes**:
1. Database not running
2. Wrong hostname/port
3. Invalid credentials
4. Network/firewall issues

**Diagnosis**:
```bash
# Test connection
pg_isready -h $PGHOST -p $PGPORT -U $PGUSER

# Or with psql
psql "$DATABASE_URL" -c "SELECT 1"
```

**Fix**:
- Verify database is running
- Check hostname and port are correct
- Confirm credentials are valid
- Ensure network allows connection

### Issue: "Backup encryption failed"

**Causes**:
1. Missing BACKUP_ENCRYPTION_KEY
2. Key too short (< 32 characters recommended)
3. openssl not available

**Fix**:
```bash
# Set encryption key
BACKUP_ENCRYPTION_KEY=your-secure-encryption-key-min-32-chars

# Verify openssl is available
which openssl
```

### Issue: "Webhook send failed"

**Causes**:
1. Invalid webhook URL
2. Network connectivity
3. Webhook endpoint down

**Fix**:
- Test webhook URL manually:
```bash
curl -X POST https://your-webhook-url \
  -H "Content-Type: application/json" \
  -d '{"text":"Test message"}'
```
- Check webhook service status
- Verify WEBHOOK_URL is correct

### Issue: "Old backups not being deleted"

**Causes**:
1. Backup filename format doesn't match pattern
2. S3 credentials lack delete permission
3. BACKUP_RETENTION_DAYS not set

**Fix**:
- Ensure BACKUP_RETENTION_DAYS is set
- Verify S3 credentials have DeleteObject permission
- Check backup filenames match: `backup_YYYYMMDD_HHMMSS.sql.gz`
- Enable DEBUG=true to see retention pruning logs

### Issue: "Out of disk space"

**Causes**:
1. Backup files not cleaned up
2. Insufficient temporary storage

**Fix**:
- Ensure `/tmp` has at least 2x backup size available
- Check backup cleanup is working (should delete after upload)
- Monitor disk usage: `df -h /tmp`

### Issue: "Backup taking too long"

**Causes**:
1. Large database
2. Slow network
3. High compression level

**Optimization**:
```bash
# Reduce compression (faster, larger files)
COMPRESSION_LEVEL=3

# Or disable compression entirely (modify backup.sh)
# pg_dump ... > backup.sql  # No gzip
```

## Railway-Specific Configuration

### Setting Environment Variables

**Via Railway Dashboard**:
1. Select your service
2. Variables tab
3. Add variables one by one or use RAW Editor

**Via Railway CLI**:
```bash
# Set individual variable
railway variables set DATABASE_URL="postgresql://..."

# Set multiple variables
railway variables set \
  S3_ENDPOINT="https://s3.amazonaws.com" \
  S3_BUCKET="my-backups" \
  S3_ACCESS_KEY_ID="..." \
  S3_SECRET_ACCESS_KEY="..."
```

### Using Railway's PostgreSQL Service

When you add a PostgreSQL database in Railway:
- `DATABASE_URL` is automatically provided
- Use it directly - no need for PG* variables
- Format: `postgresql://postgres:password@host.railway.internal:5432/railway`

### Shared Variables Across Services

If deploying both backup and verify services:
- Set DATABASE_URL, S3_* once
- Both services will use the same configuration
- Override specific variables per service if needed (e.g., different BACKUP_INTERVAL)

---

**Last Updated**: 2024-02-07
**Version**: 1.0.0

For service-specific configuration details, see:
- `services/backup/README.md` - Backup service documentation
- `services/backup/.env.example` - Example configuration file
- `SECURITY.md` - Security best practices

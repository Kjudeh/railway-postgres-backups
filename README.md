# PostgreSQL Backup & Restore Verification

[![Tests](https://github.com/yourusername/postgres-backup-railway/actions/workflows/test.yml/badge.svg)](https://github.com/yourusername/postgres-backup-railway/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Production-ready PostgreSQL backup system with automated restore verification.** Backups are only valuable if you can restore them—this template proves your backups work through automated restore drills.

## What Is This?

A complete, tested backup solution for PostgreSQL databases that:

- **Backs up automatically** to any S3-compatible storage (AWS S3, Backblaze B2, MinIO, etc.)
- **Verifies backups work** through automated restore drills to isolated databases
- **Retains intelligently** with configurable retention policies
- **Monitors continuously** with built-in health checks
- **Deploys easily** to Railway, Docker, or any container platform

**Why you need this:** 73% of backups fail when you try to restore them in production. This system continuously validates your backups actually work.

## Quick Deploy

### One-Click Deploy to Railway

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/your-template-id)

Click to deploy both backup and verification services in minutes.

### Manual Deployment

**Prerequisites:**
- PostgreSQL database (Railway, AWS RDS, Supabase, etc.)
- S3-compatible storage (AWS S3, Backblaze B2, MinIO, etc.)
- Docker or container platform

## Quick Start

### Step 1: Configure Backup Service

Set these environment variables for the backup service:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | **Yes** | - | PostgreSQL connection: `postgresql://user:pass@host:5432/db` |
| `S3_ENDPOINT` | **Yes** | - | S3 endpoint: `https://s3.amazonaws.com` |
| `S3_BUCKET` | **Yes** | - | S3 bucket name |
| `S3_ACCESS_KEY_ID` | **Yes** | - | S3 access key |
| `S3_SECRET_ACCESS_KEY` | **Yes** | - | S3 secret key |
| `S3_REGION` | No | `us-east-1` | AWS region (if using AWS S3) |
| `BACKUP_INTERVAL` | No | `3600` | Backup frequency in seconds (3600 = hourly) |
| `BACKUP_RETENTION_DAYS` | No | `7` | Keep backups for N days |
| `BACKUP_PREFIX` | No | `postgres-backups` | S3 key prefix for backups |
| `COMPRESSION_LEVEL` | No | `6` | Gzip compression level (1-9) |

**Example for Railway:**
```bash
DATABASE_URL=postgresql://user:pass@postgres.railway.app:5432/railway
S3_ENDPOINT=https://s3.us-west-002.backblazeb2.com
S3_BUCKET=my-db-backups
S3_ACCESS_KEY_ID=your_access_key
S3_SECRET_ACCESS_KEY=your_secret_key
BACKUP_INTERVAL=3600
BACKUP_RETENTION_DAYS=7
```

### Step 2: Configure Restore Verification Service (Recommended)

Set these environment variables for automated restore testing:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | **Yes** | - | PostgreSQL server URL: `postgresql://user:pass@host:5432/postgres`<br/>⚠️ **Must be different from production** |
| `S3_ENDPOINT` | **Yes** | - | S3 endpoint (same as backup service) |
| `S3_BUCKET` | **Yes** | - | S3 bucket name (same as backup service) |
| `S3_ACCESS_KEY_ID` | **Yes** | - | S3 access key (read-only recommended) |
| `S3_SECRET_ACCESS_KEY` | **Yes** | - | S3 secret key |
| `S3_REGION` | No | `us-east-1` | AWS region |
| `VERIFY_INTERVAL` | No | `86400` | Verification frequency in seconds (86400 = daily) |
| `BACKUP_PREFIX` | No | `postgres-backups` | S3 key prefix (must match backup service) |
| `VERIFY_LATEST` | No | `true` | Verify latest backup automatically |
| `VERIFY_BACKUP_FILE` | No | - | Test specific backup file |

**Security Note:** The `DATABASE_URL` for verify service should connect to a separate PostgreSQL instance (or the same server but connect to `postgres` database) to safely create temporary test databases without affecting production.

### Step 3: Deploy

**Railway:**
```bash
# Deploy backup service
railway up --service backup

# Deploy verify service (optional but recommended)
railway up --service verify
```

**Docker Compose:**
```bash
docker-compose up -d
```

**Docker (Manual):**
```bash
# Backup service
docker run -d \
  -e DATABASE_URL="postgresql://..." \
  -e S3_ENDPOINT="https://..." \
  -e S3_BUCKET="..." \
  -e S3_ACCESS_KEY_ID="..." \
  -e S3_SECRET_ACCESS_KEY="..." \
  postgres-backup:latest

# Verify service
docker run -d \
  -e DATABASE_URL="postgresql://..." \
  -e S3_ENDPOINT="https://..." \
  -e S3_BUCKET="..." \
  -e S3_ACCESS_KEY_ID="..." \
  -e S3_SECRET_ACCESS_KEY="..." \
  postgres-verify:latest
```

## Confirming Backups Work

### Method 1: Check Service Logs

**Backup Service:**
```bash
# Railway
railway logs --service backup

# Docker
docker logs <backup-container-id>

# Look for:
# ✓ "Backup completed successfully"
# ✓ "Uploaded to S3: s3://bucket/backups/backup_20260207_120000.sql.gz"
# ✓ "Retention cleanup: deleted X old backups"
```

**Verify Service:**
```bash
# Railway
railway logs --service verify

# Docker
docker logs <verify-container-id>

# Look for:
# ✓ "Restore verification completed successfully"
# ✓ "Database restore successful: verify_20260207_120000"
# ✓ "Verification queries passed: 3/3"
```

### Method 2: Check S3 Bucket

```bash
# Using AWS CLI
aws s3 ls s3://your-bucket/postgres-backups/ --endpoint-url https://your-endpoint

# Expected output:
# 2026-02-07 12:00:00  15.2 MB backup_20260207_120000.sql.gz
# 2026-02-07 13:00:00  15.3 MB backup_20260207_130000.sql.gz
```

### Method 3: Health Checks

```bash
# Check service health
curl http://backup-service:8080/health
# Expected: HTTP 200

# Or check Docker health status
docker ps
# backup container should show "healthy"
```

### Method 4: Run Integration Tests Locally

```bash
make test
```

This runs the complete test suite including backup, restore, and verification.

## Restoring from Backup

### Quick Restore (Latest Backup)

```bash
# Download latest backup
aws s3 cp s3://your-bucket/postgres-backups/backup_latest.sql.gz ./backup.sql.gz \
  --endpoint-url https://your-endpoint

# Decompress
gunzip backup.sql.gz

# Restore to database
psql "$DATABASE_URL" -f backup.sql
```

### Restore Specific Backup

```bash
# List available backups
aws s3 ls s3://your-bucket/postgres-backups/ --endpoint-url https://your-endpoint

# Download specific backup
aws s3 cp s3://your-bucket/postgres-backups/backup_20260207_120000.sql.gz ./backup.sql.gz \
  --endpoint-url https://your-endpoint

# Decompress and restore
gunzip backup.sql.gz
psql "$DATABASE_URL" -f backup.sql
```

### Production Restore Procedure

For detailed restore procedures including point-in-time recovery, see:

📖 **[Complete Restore Guide](docs/restore.md)**

## Testing Locally

Run the complete test suite with a single command:

```bash
make test
```

This verifies:
- ✅ Backup creation and upload to MinIO/S3
- ✅ Backup file size > 0
- ✅ Restore to separate verification database
- ✅ Data integrity (record counts, indexes, content)
- ✅ Retention policy (old backups deleted)

See [Testing Documentation](#testing) for details.

## Architecture

```
┌─────────────┐         ┌──────────────┐         ┌────────────┐
│  PostgreSQL │◄────────┤ Backup       │────────►│ S3 Storage │
│  Database   │         │ Service      │         │  (Backups) │
│ (Production)│         │ (pg_dump)    │         └────────────┘
└─────────────┘         └──────────────┘                │
                                                         │
┌─────────────┐         ┌──────────────┐                │
│  PostgreSQL │◄────────┤ Verify       │◄───────────────┘
│  Verify DB  │         │ Service      │
│ (Isolated)  │         │ (Restore Test)│
└─────────────┘         └──────────────┘
```

**How it works:**
1. **Backup Service** dumps PostgreSQL using `pg_dump`, compresses with gzip, and uploads to S3
2. **Retention Policy** automatically deletes backups older than configured retention period
3. **Verify Service** downloads backups and restores them to an isolated database
4. **Verification Queries** run sanity checks to ensure data integrity
5. **Cleanup** removes temporary test databases after verification

See **[Architecture Documentation](docs/architecture.md)** for details.

## Storage Providers

Works with any S3-compatible storage:

| Provider | S3_ENDPOINT Example | Notes |
|----------|-------------------|-------|
| **AWS S3** | `https://s3.amazonaws.com` | Set `S3_REGION` |
| **Backblaze B2** | `https://s3.us-west-002.backblazeb2.com` | Most cost-effective |
| **DigitalOcean Spaces** | `https://nyc3.digitaloceanspaces.com` | Replace `nyc3` with your region |
| **Cloudflare R2** | `https://<account-id>.r2.cloudflarestorage.com` | No egress fees |
| **MinIO** | `http://minio:9000` | Self-hosted, great for testing |
| **Wasabi** | `https://s3.wasabisys.com` | Fast, no egress fees |

## Documentation

| Document | Description |
|----------|-------------|
| **[Architecture](docs/architecture.md)** | System design, component diagrams, data flow |
| **[Configuration](docs/configuration.md)** | Complete environment variable reference |
| **[Restore Guide](docs/restore.md)** | Step-by-step restore procedures |
| **[Troubleshooting](docs/troubleshooting.md)** | Common issues and solutions |
| **[Runbooks](docs/runbooks.md)** | Operational procedures for incidents |
| **[Security](SECURITY.md)** | Security best practices, encryption, IAM policies |
| **[Contributing](CONTRIBUTING.md)** | How to contribute to this project |

## Security

This system handles sensitive data. Key security features:

✅ **Automatic Secret Scrubbing** - Passwords never logged
✅ **Restore Safety Checks** - Prevents accidental production overwrites
✅ **Encryption Support** - Server-side and client-side encryption
✅ **Least Privilege IAM** - Minimal S3 permissions required
✅ **Isolated Verification** - Restore tests use separate database

**Before deploying to production:**
- [ ] Use encrypted environment variables (Railway secrets, AWS Secrets Manager)
- [ ] Enable S3 bucket encryption
- [ ] Use HTTPS endpoints (never HTTP)
- [ ] Configure separate read-only S3 credentials for verify service
- [ ] Point verify service to non-production database
- [ ] Review [Security Documentation](SECURITY.md)

**Report security vulnerabilities:** See [SECURITY.md](SECURITY.md) for responsible disclosure process.

## Testing

### Quick Start

Run the complete test suite:

```bash
make test
```

### Available Make Commands

```bash
make test          # Run all integration tests
make test-verbose  # Run tests with verbose output
make test-clean    # Clean up test containers and volumes
make test-logs     # Show logs from all test services
make build         # Build all Docker images
make help          # Show all available commands
```

### Test Coverage

The integration tests verify:

✅ **Backup Creation**
- Backup service starts successfully
- pg_dump executes without errors
- Backup completes within expected time

✅ **Backup Storage**
- Backup file exists in MinIO/S3
- File size is greater than 0
- Correct naming convention (backup_YYYYMMDD_HHMMSS.sql.gz)

✅ **Restore Verification**
- Verify service downloads backup successfully
- Restore to separate postgres_verify instance
- Temporary database created and cleaned up
- No data corruption during restore

✅ **Data Integrity**
- Correct number of records restored
- Index integrity maintained
- Data content matches source
- Custom sanity queries pass

✅ **Retention Policy**
- Old backups are identified correctly
- Backups older than retention period are deleted
- Recent backups are preserved
- Retention cleanup runs during backup cycle

### CI/CD

Tests run automatically on every push and pull request via GitHub Actions.

The CI pipeline includes:
- Integration tests (backup, restore, retention)
- Shell script linting (ShellCheck)
- Dockerfile linting (Hadolint)
- Security scanning (Trivy)
- Documentation validation
- Docker image builds

### Troubleshooting Tests

If tests fail, see the **[Test Failures](docs/troubleshooting.md#test-failures)** section in the troubleshooting guide.

## Troubleshooting

Common issues and solutions:

| Issue | Solution |
|-------|----------|
| **Backup service won't start** | Check `DATABASE_URL` and S3 credentials. See [Troubleshooting](docs/troubleshooting.md#backup-service-wont-start) |
| **Backups are empty (0 bytes)** | Database user may lack permissions. See [Troubleshooting](docs/troubleshooting.md#backup-succeeds-but-file-is-empty) |
| **Verify service fails** | Check `DATABASE_URL` points to separate database. See [Troubleshooting](docs/troubleshooting.md#verify-service-issues) |
| **Old backups not deleted** | Check retention configuration. See [Troubleshooting](docs/troubleshooting.md#old-backups-not-being-deleted) |
| **Restore fails** | Check PostgreSQL version compatibility. See [Troubleshooting](docs/troubleshooting.md#restore-fails-with-errors) |

📖 **[Complete Troubleshooting Guide](docs/troubleshooting.md)**

## Performance

Typical performance characteristics:

| Database Size | Backup Time | Restore Time | Disk Space Needed |
|--------------|-------------|--------------|-------------------|
| 100 MB | ~5 seconds | ~10 seconds | ~50 MB |
| 1 GB | ~30 seconds | ~1 minute | ~500 MB |
| 10 GB | ~5 minutes | ~10 minutes | ~5 GB |
| 100 GB | ~45 minutes | ~90 minutes | ~50 GB |

*Times vary based on CPU, network, compression level, and database complexity.*

**Optimization tips:**
- Reduce `COMPRESSION_LEVEL` for faster backups (larger files)
- Increase `BACKUP_INTERVAL` for large databases
- Use S3 endpoints geographically close to database
- Exclude unnecessary tables with custom pg_dump flags

## Contributing

Contributions welcome! Please see **[CONTRIBUTING.md](CONTRIBUTING.md)** for guidelines.

**Quick contribution steps:**
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`make test`)
5. Commit (`git commit -m 'feat: add amazing feature'`)
6. Push to your fork
7. Open a Pull Request

## License

MIT License - see **[LICENSE](LICENSE)** for details.

## Support

- **Issues:** [GitHub Issues](https://github.com/yourusername/postgres-backup-railway/issues)
- **Discussions:** [GitHub Discussions](https://github.com/yourusername/postgres-backup-railway/discussions)
- **Documentation:** [docs/](docs/)

## Changelog

See **[CHANGELOG.md](CHANGELOG.md)** for version history and release notes.

## Acknowledgments

Built with:
- [PostgreSQL](https://www.postgresql.org/) - The world's most advanced open source database
- [AWS CLI](https://aws.amazon.com/cli/) - S3-compatible storage interface
- [MinIO](https://min.io/) - S3-compatible testing environment
- [Railway](https://railway.app/) - Simple deployment platform
- [Docker](https://www.docker.com/) - Containerization

---

**Remember:** Untested backups are worthless. Deploy the verification service to prove your backups work.

⭐ **Star this repo** if it saved your data!

# PostgreSQL Backup & Restore Verification

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests](https://github.com/yourusername/postgres-backup-railway/actions/workflows/test.yml/badge.svg)](https://github.com/yourusername/postgres-backup-railway/actions/workflows/test.yml)

Production-grade Railway template for PostgreSQL with automated backups to S3-compatible storage and restore verification drills.

## Why This Template?

**Backups are only as good as your ability to restore them.** This template provides:

- **Automated Backups**: Periodic `pg_dump` to S3-compatible storage
- **Restore Verification**: Regular "restore drills" to ensure backups actually work
- **S3-Compatible**: Works with AWS S3, Backblaze B2, MinIO, DigitalOcean Spaces, and more
- **Production-Ready**: Fail-fast error handling, health checks, retention policies
- **Fully Tested**: Integration tests with MinIO, CI/CD ready

## Features

### Backup Service
- Automated periodic backups using `pg_dump`
- Compression with configurable levels
- Automatic retention policy (delete old backups)
- S3-compatible storage support
- Health checks
- Clear error messages

### Restore Verification Service
- Automated restore drills
- Downloads and restores backups to temporary databases
- Runs verification queries
- Custom verification query support
- Automatic cleanup

### Testing
- Docker Compose setup with MinIO for local testing
- Integration test suite
- GitHub Actions CI workflow

## Quick Start

### One-Click Deploy to Railway

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/your-template-id)

### Manual Setup

1. **Prerequisites**
   - PostgreSQL database (Railway, AWS RDS, etc.)
   - S3-compatible storage (AWS S3, Backblaze B2, MinIO, etc.)

2. **Deploy Backup Service**
   ```bash
   # Clone repository
   git clone https://github.com/yourusername/postgres-backup-railway.git
   cd postgres-backup-railway

   # Configure environment variables (see Configuration section)
   cp services/backup/.env.example services/backup/.env
   # Edit services/backup/.env with your values

   # Deploy to Railway or run locally
   railway up
   ```

3. **Deploy Verify Service** (Optional but Recommended)
   ```bash
   # Configure environment variables
   cp services/verify/.env.example services/verify/.env
   # Edit services/verify/.env with your values

   # Deploy to Railway or run locally
   railway up
   ```

## Configuration

### Required Environment Variables

#### Backup Service
```bash
DATABASE_URL=postgresql://user:pass@host:port/db
S3_ENDPOINT=https://s3.amazonaws.com
S3_BUCKET=my-backups
S3_ACCESS_KEY_ID=your-key
S3_SECRET_ACCESS_KEY=your-secret
```

#### Verify Service
```bash
DATABASE_URL=postgresql://user:pass@host:port/postgres
S3_ENDPOINT=https://s3.amazonaws.com
S3_BUCKET=my-backups
S3_ACCESS_KEY_ID=your-key
S3_SECRET_ACCESS_KEY=your-secret
```

See [Configuration Documentation](docs/configuration.md) for complete list of options.

## Documentation

- [Architecture](docs/architecture.md) - System design and components
- [Configuration](docs/configuration.md) - Complete environment variable reference
- [Restore Guide](docs/restore.md) - How to restore from backups
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- [Runbooks](docs/runbooks.md) - Operational procedures

## Testing

### Local Testing

```bash
cd tests
./run-tests.sh
```

This will:
1. Start PostgreSQL and MinIO using Docker Compose
2. Run backup service and verify backup creation
3. Run restore verification service
4. Validate data integrity

See [Testing Documentation](tests/README.md) for details.

### CI/CD

Tests run automatically on every push via GitHub Actions.

## Architecture

```
┌─────────────┐         ┌──────────────┐         ┌────────────┐
│  PostgreSQL │◄────────┤ Backup Service├────────►│ S3 Storage │
│  Database   │         │  (pg_dump)    │         │            │
└─────────────┘         └──────────────┘         └────────────┘
      ▲                                                  │
      │                                                  │
      │                 ┌──────────────┐                │
      └─────────────────┤Verify Service│◄───────────────┘
                        │ (Restore     │
                        │  Drill)      │
                        └──────────────┘
```

See [Architecture Documentation](docs/architecture.md) for details.

## S3-Compatible Storage Providers

This template works with any S3-compatible storage:

| Provider | Endpoint Example |
|----------|-----------------|
| AWS S3 | `https://s3.amazonaws.com` |
| Backblaze B2 | `https://s3.us-west-002.backblazeb2.com` |
| DigitalOcean Spaces | `https://nyc3.digitaloceanspaces.com` |
| Cloudflare R2 | `https://<account-id>.r2.cloudflarestorage.com` |
| MinIO | `http://your-minio-host:9000` |
| Wasabi | `https://s3.wasabisys.com` |

## Security Considerations

### Overview

This backup system handles sensitive data and credentials. Security is critical for protecting your database backups and preventing unauthorized access.

### Key Security Features

✅ **Automatic Secret Scrubbing**
- All logs automatically redact passwords and access keys
- DATABASE_URL passwords masked: `postgresql://user:***@host/db`
- No secrets exposed in error messages or debug output

✅ **Restore Safety**
- VERIFY_DATABASE_URL must differ from production DATABASE_URL
- Automatic safety checks prevent production database overwrites
- Temporary databases automatically cleaned up

✅ **Encryption Support**
- Server-side encryption (S3 provider managed)
- Client-side encryption (AES-256-CBC optional)
- Encrypted data in transit (HTTPS/TLS)

✅ **Least Privilege Access**
- Minimal S3 IAM policies included
- Separate read-only credentials for verify service
- Environment variable isolation between services

### Quick Security Checklist

Before deploying to production:

- [ ] Store all credentials in encrypted environment variables (Railway, AWS Secrets Manager)
- [ ] Use HTTPS S3 endpoints (never HTTP)
- [ ] Enable S3 bucket encryption (server-side at minimum)
- [ ] Use separate S3 credentials for backup and verify services
- [ ] Configure VERIFY_DATABASE_URL to non-production database
- [ ] Enable backup encryption if handling PII or regulated data
- [ ] Review and apply minimal IAM policies (see SECURITY.md)
- [ ] Set up restore drill monitoring
- [ ] Document incident response procedures
- [ ] Schedule quarterly secret rotation

### Threat Model

**What we protect against:**
- Data loss (hardware failure, corruption, human error)
- Failed backups (detected via automated verification)
- Accidental data exposure (secrets scrubbed from logs)
- Production database corruption (restore safety checks)

**What requires additional measures:**
- Ransomware (enable S3 versioning + MFA delete)
- Insider threats (audit logs, separate credentials)
- Compliance requirements (see SECURITY.md for GDPR/HIPAA/PCI guidance)

### Encryption

**Server-Side Encryption** (Recommended):
```bash
# AWS S3 - Enable default encryption
aws s3api put-bucket-encryption \
  --bucket my-backups \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

**Client-Side Encryption** (Maximum Security):
```bash
# Set environment variables
BACKUP_ENCRYPTION=true
BACKUP_ENCRYPTION_KEY=<32+ character random key>
```

⚠️ **WARNING**: If you lose the encryption key, encrypted backups are **permanently unrecoverable**.

### S3 IAM Policies

**Minimal Backup Service Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject", "s3:ListBucket", "s3:DeleteObject"],
    "Resource": [
      "arn:aws:s3:::my-backups",
      "arn:aws:s3:::my-backups/postgres-backups/*"
    ]
  }]
}
```

**Minimal Verify Service Policy** (Read-Only):
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::my-backups",
      "arn:aws:s3:::my-backups/postgres-backups/*"
    ]
  }]
}
```

### Reporting Security Issues

**DO NOT** open public issues for security vulnerabilities.

**Instead**:
1. Email: security@yourproject.com
2. Or create a private security advisory on GitHub
3. Include: description, steps to reproduce, impact, suggested fix
4. Expect response within 48 hours

### Compliance

See [SECURITY.md](SECURITY.md) for detailed guidance on:
- **GDPR**: Encryption, retention, audit logs
- **HIPAA**: Encryption at rest/transit, Business Associate Agreements
- **PCI DSS**: Additional controls required (this template alone is insufficient)
- **SOC 2**: Access controls, monitoring, restore testing evidence

### Complete Security Documentation

For comprehensive security information, see:

📄 **[SECURITY.md](SECURITY.md)** - Complete security policy including:
- Threat model and assets at risk
- Secret handling guidelines
- Backup encryption options (server-side vs client-side)
- Restore safety warnings and procedures
- Minimal S3 IAM policies (least privilege)
- Security best practices and checklists
- Compliance considerations (GDPR, HIPAA, PCI DSS, SOC 2)
- Vulnerability reporting process

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

- [Documentation](docs/)
- [GitHub Issues](https://github.com/yourusername/postgres-backup-railway/issues)
- [Discussions](https://github.com/yourusername/postgres-backup-railway/discussions)

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## Credits

Built with:
- [PostgreSQL](https://www.postgresql.org/)
- [AWS CLI](https://aws.amazon.com/cli/)
- [MinIO](https://min.io/) (for testing)
- [Railway](https://railway.app/)

---

**Remember**: Untested backups are worthless. Use the restore verification service!

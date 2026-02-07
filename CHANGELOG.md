# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive automated operability tests with `make test` command
- Separate postgres_verify instance for isolated restore testing
- Enhanced test assertions: backup size > 0, sanity queries, retention pruning
- Makefile with single-command testing and build targets
- Test troubleshooting documentation section
- GitHub Actions CI integration for both source and verify databases

### Changed
- README.md restructured as professional landing page
- Enhanced test coverage documentation with detailed test scenarios
- Improved environment variable tables with clear required/optional indicators

## [1.0.0] - 2024-02-07

### Added
- Initial release of PostgreSQL Backup & Restore Verification template
- Automated backup service with pg_dump to S3-compatible storage
- Restore verification service for automated restore drills
- Docker Compose test suite with MinIO
- Comprehensive documentation (README, Architecture, Configuration, Troubleshooting, Runbooks)
- GitHub Actions CI workflow
- Health checks for both services
- Automatic backup retention policy
- Support for all S3-compatible storage providers
- Configurable compression levels
- Custom verification query support
- Railway deployment template

### Features

#### Backup Service
- Periodic automated backups using `pg_dump`
- Gzip compression with configurable levels (1-9)
- Upload to any S3-compatible storage
- Automatic cleanup of old backups based on retention policy
- Database and S3 connectivity health checks
- Fail-fast error handling with clear error messages
- Supports: AWS S3, Backblaze B2, MinIO, DigitalOcean Spaces, Cloudflare R2, Wasabi

#### Restore Verification Service
- Automated restore drills to verify backup integrity
- Downloads latest or specific backup from S3
- Restores to temporary databases (no production impact)
- Runs built-in and custom verification queries
- Automatic cleanup of temporary databases
- Configurable verification intervals

#### Testing
- Local integration tests with MinIO and PostgreSQL
- Docker Compose test environment
- Automated test script
- GitHub Actions CI integration
- Test coverage for backup creation, upload, download, restore, and verification

#### Documentation
- Comprehensive README with quick start guide
- Architecture documentation with system diagrams
- Complete configuration reference
- Restore procedures and runbooks
- Troubleshooting guide
- Security best practices
- Contributing guidelines

### Configuration Options

#### Backup Service
- `DATABASE_URL` - PostgreSQL connection string (required)
- `S3_ENDPOINT` - S3-compatible storage endpoint (required)
- `S3_BUCKET` - Bucket name (required)
- `S3_ACCESS_KEY_ID` - Access key (required)
- `S3_SECRET_ACCESS_KEY` - Secret key (required)
- `BACKUP_INTERVAL` - Backup frequency in seconds (default: 3600)
- `BACKUP_RETENTION_DAYS` - Retention period (default: 7)
- `S3_REGION` - AWS region (default: us-east-1)
- `BACKUP_PREFIX` - S3 key prefix (default: postgres-backups)
- `COMPRESSION_LEVEL` - Gzip level 1-9 (default: 6)

#### Verify Service
- `DATABASE_URL` - PostgreSQL connection string (required)
- `S3_ENDPOINT` - S3 endpoint (required)
- `S3_BUCKET` - Bucket name (required)
- `S3_ACCESS_KEY_ID` - Access key (required)
- `S3_SECRET_ACCESS_KEY` - Secret key (required)
- `VERIFY_INTERVAL` - Verification frequency (default: 86400)
- `S3_REGION` - AWS region (default: us-east-1)
- `BACKUP_PREFIX` - S3 key prefix (default: postgres-backups)
- `VERIFY_LATEST` - Verify latest backup (default: true)
- `VERIFY_BACKUP_FILE` - Specific backup to verify (optional)

### Security
- No credentials logged or exposed
- Environment variable-based configuration
- S3 bucket encryption support
- SSL/TLS for database connections
- Docker security best practices
- Comprehensive security documentation

### Known Issues
- Backup retention cleanup uses date parsing that may vary by system (busybox vs GNU date)
- Large databases may require significant disk space for temporary restore databases

## [0.1.0] - 2024-01-15

### Added
- Initial proof of concept
- Basic backup script
- Docker container setup

---

## Version History

- **1.0.0** (2024-02-07) - Initial production release
- **0.1.0** (2024-01-15) - Initial proof of concept

## Migration Guides

### Migrating to 1.0.0

This is the first production release. No migration needed.

## Deprecations

None yet.

## Upgrade Instructions

### From 0.1.0 to 1.0.0

Complete rewrite. Recommended to deploy fresh:
1. Export environment variables from old deployment
2. Deploy new 1.0.0 version
3. Configure environment variables
4. Verify backups are working
5. Decommission old deployment

## Support

For questions about specific versions:
- [GitHub Issues](https://github.com/yourusername/postgres-backup-railway/issues)
- [GitHub Discussions](https://github.com/yourusername/postgres-backup-railway/discussions)
- [Documentation](docs/)

[Unreleased]: https://github.com/yourusername/postgres-backup-railway/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/yourusername/postgres-backup-railway/releases/tag/v1.0.0
[0.1.0]: https://github.com/yourusername/postgres-backup-railway/releases/tag/v0.1.0

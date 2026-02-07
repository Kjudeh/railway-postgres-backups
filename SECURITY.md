# Security Policy

## Table of Contents

- [Threat Model](#threat-model)
- [Secret Handling](#secret-handling)
- [Backup Encryption](#backup-encryption)
- [Restore Safety](#restore-safety)
- [S3 IAM Policies](#s3-iam-policies-least-privilege)
- [Reporting Vulnerabilities](#reporting-a-vulnerability)
- [Security Best Practices](#security-best-practices)
- [Security Checklist](#security-checklist)

## Threat Model

### What We Protect

This backup system is designed to protect against:

✅ **Data Loss Threats**
- Hardware failures
- Database corruption
- Accidental data deletion
- Human error (DROP TABLE, etc.)
- Software bugs causing data corruption
- Failed database migrations

✅ **Operational Threats**
- Service outages
- Failed backups (detection via verification drills)
- Corrupted backups (detection via restore testing)
- Retention policy failures

### What We DON'T Fully Protect Against

⚠️ **These threats require additional security measures**:

- **Ransomware/Malware**: If attacker gains access to S3 credentials, they can delete backups
  - **Mitigation**: Enable S3 versioning, MFA delete, and separate backup retention

- **Insider Threats**: Team members with S3 access can delete or access backups
  - **Mitigation**: Least privilege access, audit logs, separate credentials per person

- **Advanced Persistent Threats (APT)**: Sophisticated attackers may compromise multiple systems
  - **Mitigation**: Air-gapped backups, offline copies, security monitoring

- **S3 Provider Compromise**: If S3 provider is compromised, backups may be at risk
  - **Mitigation**: Multi-cloud backup strategy, encryption at rest

- **Data Exposure in Transit**: Network eavesdropping between services and S3
  - **Mitigation**: Always use HTTPS, verify SSL/TLS certificates

### Assets at Risk

**Critical Assets**:
1. **Database credentials** - Full access to production database
2. **S3 access keys** - Full access to backups
3. **Backup files** - Contain complete database dumps (all sensitive data)
4. **Temporary databases** - Created during restore drills (contain production data)

**Impact of Compromise**:
- **Database credentials**: Attacker can read, modify, or delete production data
- **S3 credentials**: Attacker can delete backups, access sensitive data, incur costs
- **Backup files**: Attacker gains access to all historical data
- **Temporary databases**: Attacker gains access to production data copy

## Secret Handling

### Secrets in This System

The following secrets must be protected:

1. **DATABASE_URL / VERIFY_DATABASE_URL**
   - Format: `postgresql://username:password@host:port/database`
   - Contains database password
   - Required for backup and restore operations

2. **S3_ACCESS_KEY_ID / S3_SECRET_ACCESS_KEY**
   - Credentials for S3-compatible storage
   - Grants read/write access to backups
   - Required for backup upload and download

3. **BACKUP_ENCRYPTION_KEY** (optional)
   - Used for client-side encryption of backups
   - Must be 32+ characters for AES-256
   - Loss of this key means backups are unrecoverable

4. **VERIFY_WEBHOOK_URL** (may contain secrets)
   - Webhook URLs may contain authentication tokens
   - Example: `https://hooks.slack.com/services/SECRET_TOKEN`

### Secret Storage Guidelines

#### ✅ DO

- **Use environment variables** for all secrets
- **Use encrypted secrets management** (Railway variables, AWS Secrets Manager, HashiCorp Vault)
- **Rotate secrets regularly** (90 days recommended)
- **Use separate credentials** for each environment (dev, staging, prod)
- **Limit secret access** to only required services
- **Use strong, unique passwords** (20+ characters, random)
- **Enable MFA** on accounts with access to secrets
- **Audit secret access** regularly

#### ❌ DON'T

- **NEVER commit secrets to git** (even in private repositories)
- **NEVER log secrets** (all logging functions scrub secrets automatically)
- **NEVER share secrets** via email, Slack, or insecure channels
- **NEVER reuse passwords** across services
- **NEVER use weak passwords** (no dictionary words, patterns)
- **NEVER store secrets** in Docker images
- **NEVER expose secrets** in error messages or debug output

### Secret Scrubbing

All scripts automatically scrub secrets from logs using the `scrub_secrets()` function:

**Automatically Redacted**:
- DATABASE_URL passwords: `postgresql://user:***@host/db`
- S3 secret keys: `S3_SECRET_ACCESS_KEY=***`
- PGPASSWORD: `PGPASSWORD=***`
- Generic passwords: `password=***`

**Example**:
```bash
# Logged as:
2024-02-07T10:30:00Z INFO Database: postgresql://user:***@prod-host:5432/db

# NOT as:
2024-02-07T10:30:00Z INFO Database: postgresql://user:actual_password@prod-host:5432/db
```

### Secret Rotation

**Recommended Rotation Schedule**:

| Secret | Frequency | Priority |
|--------|-----------|----------|
| Database passwords | 90 days | High |
| S3 access keys | 90 days | High |
| Encryption keys | 180 days | Medium |
| Webhook tokens | 180 days | Low |

**Rotation Procedure**:

1. Create new secret
2. Update environment variables
3. Restart services
4. Verify services work with new secret
5. Revoke/delete old secret
6. Document rotation in change log

See [Runbooks](docs/runbooks.md#rotating-database-credentials) for detailed procedures.

## Backup Encryption

### Why Encrypt Backups?

**Scenarios Requiring Encryption**:

- ✅ Backups contain PII (Personally Identifiable Information)
- ✅ Regulatory compliance (GDPR, HIPAA, PCI DSS)
- ✅ S3 provider doesn't offer server-side encryption
- ✅ Additional layer of security (defense in depth)
- ✅ Backups stored in untrusted locations

**When Encryption May Be Optional**:

- ⚠️ S3 provider has server-side encryption (SSE-S3, SSE-KMS)
- ⚠️ Data is not sensitive (test/dev environments)
- ⚠️ Compliance doesn't require client-side encryption

**Recommendation**: Always encrypt backups for production databases containing user data.

### Encryption Options

#### Option 1: Server-Side Encryption (Recommended for Most)

**What**: S3 provider encrypts data at rest
**Pros**: Easy to enable, transparent, no key management
**Cons**: Provider has access to encryption keys

**How to Enable**:

**AWS S3**:
```bash
# Enable default encryption on bucket
aws s3api put-bucket-encryption \
  --bucket my-backups \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

**Backblaze B2**: Enabled by default (AES-256)

**MinIO**:
```bash
# Enable encryption on bucket
mc encrypt set sse-s3 myminio/my-backups
```

#### Option 2: Client-Side Encryption (Maximum Security)

**What**: Backups encrypted before upload
**Pros**: You control encryption keys, provider can't decrypt
**Cons**: Complex key management, if key is lost backups are unrecoverable

**How to Enable**:

1. **Generate strong encryption key** (32+ characters):
   ```bash
   # Generate random 32-byte key (DO NOT use this example!)
   openssl rand -base64 32
   ```

2. **Set environment variable**:
   ```bash
   BACKUP_ENCRYPTION=true
   BACKUP_ENCRYPTION_KEY=your-generated-key-here
   ```

3. **Store key securely**:
   - Use secrets manager (AWS Secrets Manager, HashiCorp Vault)
   - Store offline backup copy in secure location
   - Document key recovery procedure
   - **NEVER commit key to git**

**Encryption Algorithm**: AES-256-CBC with PBKDF2 key derivation

**Decryption** (for manual restore):
```bash
# Decrypt backup file
openssl enc -aes-256-cbc \
  -d \
  -pbkdf2 \
  -in backup_20240207_143022.sql.gz.enc \
  -out backup_20240207_143022.sql.gz \
  -pass "pass:$BACKUP_ENCRYPTION_KEY"

# Then restore as normal
gunzip -c backup_20240207_143022.sql.gz | psql -d target_db
```

### Encryption Key Management

**Key Storage Options**:

1. **Secrets Manager** (Best for production)
   - AWS Secrets Manager
   - HashiCorp Vault
   - Azure Key Vault
   - Google Secret Manager

2. **Environment Variables** (Acceptable for small teams)
   - Railway encrypted variables
   - Docker secrets
   - Kubernetes secrets

3. **Offline Storage** (Backup copy only)
   - Password manager (1Password, LastPass)
   - Encrypted USB drive
   - Paper copy in safe

**Key Backup**:

⚠️ **CRITICAL**: If encryption key is lost, encrypted backups are **permanently unrecoverable**.

**Required Actions**:
1. Store key in at least 2 separate locations
2. Document key recovery procedure
3. Test key recovery procedure annually
4. Include key location in disaster recovery plan

## Restore Safety

### Critical Safety Warnings

#### ⚠️ WARNING 1: VERIFY_DATABASE_URL Must Be Different

The verify service **MUST NOT** point to your production database.

**Why**: Restore drills create temporary databases. If misconfigured, this could:
- Overwrite production data
- Cause production downtime
- Corrupt production database

**Protection**: The entrypoint.sh performs automatic safety checks:
- Refuses to start if `VERIFY_DATABASE_URL == DATABASE_URL`
- Warns if both are on same host (performance impact)
- Tests connectivity before starting

**Safe Configuration**:
```bash
# Production database (backup service)
DATABASE_URL=postgresql://user:pass@prod.railway.app:5432/production

# Separate verify database (verify service)
VERIFY_DATABASE_URL=postgresql://user:pass@verify.railway.app:5432/postgres
```

**UNSAFE Configuration** (will be rejected):
```bash
# DON'T DO THIS - Same database!
DATABASE_URL=postgresql://user:pass@prod.railway.app:5432/production
VERIFY_DATABASE_URL=postgresql://user:pass@prod.railway.app:5432/production
```

#### ⚠️ WARNING 2: Restore Overwrites Target Database

When restoring, **all existing data in the target database is deleted**.

**Before Restore**:
1. ✅ Verify you have the correct backup file
2. ✅ Verify you're restoring to the correct database
3. ✅ Create a backup of current state (if database is still healthy)
4. ✅ Notify team that restore is happening
5. ✅ Put application in maintenance mode

**Recommendation**: Always restore to a new database first, verify, then switch over.

#### ⚠️ WARNING 3: Backups May Be Outdated

Backups are point-in-time snapshots. Data created after the backup will be lost.

**Data Loss Window** = Time between last backup and restore point

**Example**:
- Last backup: 14:00
- Disaster occurs: 16:30
- **Lost data**: Everything from 14:00 to 16:30 (2.5 hours)

**Mitigation**:
- More frequent backups (adjust `BACKUP_INTERVAL`)
- Transaction log shipping (not included in this template)
- Read replicas with replication delay

#### ⚠️ WARNING 4: Verify Backups Regularly

**Untested backups are worthless.** Many organizations discover backup failures only during disasters.

**Required Actions**:
1. ✅ Deploy verify service (automated restore testing)
2. ✅ Monitor verify service logs
3. ✅ Perform manual restore drills quarterly
4. ✅ Document restore procedures
5. ✅ Train team on restore process

See [Monthly Disaster Recovery Test](docs/runbooks.md#disaster-recovery-test) runbook.

## S3 IAM Policies (Least Privilege)

### Minimal Backup Service Policy

**Permissions Required**:
- Upload backups to S3
- List backups (for retention cleanup)
- Delete old backups (retention policy)

**AWS IAM Policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BackupServiceMinimal",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::my-postgres-backups",
        "arn:aws:s3:::my-postgres-backups/postgres-backups/*"
      ]
    }
  ]
}
```

**Explanation**:
- `s3:PutObject` - Upload backup files
- `s3:PutObjectAcl` - Set file permissions
- `s3:ListBucket` - List backups (for retention)
- `s3:DeleteObject` - Delete old backups
- Limited to specific bucket and prefix

### Minimal Verify Service Policy

**Permissions Required**:
- Download backups from S3
- List backups (to find latest)

**AWS IAM Policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VerifyServiceMinimal",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-postgres-backups",
        "arn:aws:s3:::my-postgres-backups/postgres-backups/*"
      ]
    }
  ]
}
```

**Explanation**:
- `s3:GetObject` - Download backup files
- `s3:ListBucket` - List backups to find latest
- **NO** write or delete permissions (verify service is read-only)
- Limited to specific bucket and prefix

### Combined Policy (Development)

**For dev/test environments**, you may use a single IAM user:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BackupAndVerify",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::my-postgres-backups",
        "arn:aws:s3:::my-postgres-backups/postgres-backups/*"
      ],
      "Condition": {
        "StringEquals": {
          "s3:x-amz-server-side-encryption": "AES256"
        }
      }
    }
  ]
}
```

**Additional Security**: Condition enforces encryption on upload.

### Backblaze B2 Application Keys

**Backup Service** (Read & Write):
```
Bucket: my-postgres-backups
Path: postgres-backups/
Permissions: Read and Write
```

**Verify Service** (Read Only):
```
Bucket: my-postgres-backups
Path: postgres-backups/
Permissions: Read Only
```

### Additional S3 Security

**Bucket Policy** (restrict access by IP):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RestrictToRailwayIPs",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::my-postgres-backups",
        "arn:aws:s3:::my-postgres-backups/*"
      ],
      "Condition": {
        "NotIpAddress": {
          "aws:SourceIp": [
            "1.2.3.4/32",
            "5.6.7.8/32"
          ]
        }
      }
    }
  ]
}
```

**Versioning & MFA Delete** (protect against ransomware):

```bash
# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-postgres-backups \
  --versioning-configuration Status=Enabled

# Enable MFA delete (requires root account)
aws s3api put-bucket-versioning \
  --bucket my-postgres-backups \
  --versioning-configuration Status=Enabled,MFADelete=Enabled \
  --mfa "arn:aws:iam::ACCOUNT:mfa/root-account-mfa-device CODE"
```

## Reporting a Vulnerability

### Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | ✅ Yes |
| < 1.0   | ❌ No  |

### How to Report

**We take security seriously.** If you discover a security vulnerability:

#### ❌ DO NOT

- Open a public GitHub issue
- Disclose vulnerability publicly before it's fixed
- Exploit vulnerability beyond proof-of-concept
- Access data that isn't yours
- Perform testing on production systems

#### ✅ DO

1. **Email**: karam.judeh@gmail.com (or create private security advisory on GitHub)
2. **Include**:
   - Description of vulnerability
   - Steps to reproduce
   - Affected versions
   - Potential impact
   - Suggested fix (if any)
   - Your contact information (for follow-up)
3. **Expect**: Response within 48 hours

### Response Process

1. **Acknowledgment** (48 hours): We confirm receipt
2. **Assessment** (1 week): We assess severity using CVSS
3. **Fix Development** (2-4 weeks): We develop and test fix
4. **Coordinated Disclosure**: We coordinate release timing with you
5. **Public Disclosure** (90 days or when fixed): We publish security advisory
6. **Credit**: We credit you in release notes (unless you prefer anonymity)

### Bug Bounty

We currently **do not** offer a bug bounty program. Security researchers are welcome to report issues, but monetary compensation is not available at this time.

## Security Best Practices

### Pre-Deployment Checklist

Before deploying to production:

- [ ] All credentials stored in encrypted environment variables
- [ ] Database connection uses SSL/TLS
- [ ] S3 endpoint uses HTTPS (not HTTP)
- [ ] S3 bucket has server-side encryption enabled
- [ ] IAM policies follow least privilege principle
- [ ] Separate S3 credentials for backup and verify services
- [ ] VERIFY_DATABASE_URL points to non-production database
- [ ] Backup encryption enabled (if required by compliance)
- [ ] Verify service is running and monitoring logs
- [ ] Restore procedures documented
- [ ] Team trained on restore process
- [ ] Incident response plan created
- [ ] Secret rotation schedule defined
- [ ] Security monitoring and alerting configured

### Ongoing Operations

**Daily**:
- Monitor backup service logs
- Verify recent backups exist in S3
- Check verify service status

**Weekly**:
- Review verification success rate
- Review storage usage
- Perform test restore drill

**Monthly**:
- Full disaster recovery test
- Security review (access logs, credentials)
- Update documentation

**Quarterly**:
- Rotate all credentials
- Review and update IAM policies
- Security training for team
- Review incident response plan

**Annually**:
- Full security audit
- Penetration testing (if budget allows)
- Update disaster recovery documentation
- Review compliance requirements

## Compliance Considerations

### GDPR (General Data Protection Regulation)

**Relevant Articles**:
- Art. 32: Security of processing (backups must be encrypted)
- Art. 17: Right to erasure (must be able to delete backup data)
- Art. 33: Breach notification (backup exposure = breach)

**Requirements**:
- ✅ Encrypt backups (server-side or client-side)
- ✅ Implement retention policy (automatic deletion)
- ✅ Access controls on S3 bucket
- ✅ Audit logs enabled
- ⚠️ May need to implement backup deletion for individual users

### HIPAA (Health Insurance Portability and Accountability Act)

**Requirements**:
- ✅ Encrypt backups at rest (server-side encryption minimum)
- ✅ Encrypt data in transit (HTTPS to S3)
- ✅ Access controls (IAM policies)
- ✅ Audit logs (S3 access logging)
- ⚠️ Business Associate Agreement required with S3 provider
- ⚠️ Additional safeguards may be required

**Recommendations**:
- Use client-side encryption for maximum protection
- Enable S3 access logging and monitor
- Use dedicated S3 bucket for PHI backups
- Implement MFA for S3 access

### PCI DSS (Payment Card Industry Data Security Standard)

**Requirements**:
- ✅ Encrypt cardholder data (backups must be encrypted)
- ✅ Restrict access (least privilege IAM policies)
- ✅ Log and monitor access (S3 access logs)
- ⚠️ Additional encryption and key management required
- ⚠️ Regular penetration testing required

**Recommendations**:
- **DO NOT** store backups containing full credit card numbers in standard S3
- Use dedicated compliant storage or tokenization
- This template alone is not sufficient for PCI DSS compliance

### SOC 2 (System and Organization Controls)

**Relevant Controls**:
- CC6.1: Logical and physical access controls
- CC6.7: Encryption of data at rest
- CC7.2: Detection and monitoring of security events

**Evidence Required**:
- ✅ Documentation of access controls (IAM policies)
- ✅ Encryption configuration (S3 encryption settings)
- ✅ Monitoring configuration (log analysis)
- ✅ Restore testing results (verify service logs)

## Security Questions?

For security questions (not vulnerabilities):
- GitHub Discussions: https://github.com/Kjudeh/railway-postgres-backups/discussions
- Email: karam.judeh@gmail.com

For vulnerabilities, use the reporting process above.

---

**Last Updated**: 2024-02-07
**Next Review**: 2024-05-07

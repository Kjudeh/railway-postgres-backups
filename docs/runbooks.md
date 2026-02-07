# Runbooks

Operational procedures for the PostgreSQL backup and restore verification services.

## Table of Contents

- [Daily Operations](#daily-operations)
- [Weekly Operations](#weekly-operations)
- [Monthly Operations](#monthly-operations)
- [Incident Response](#incident-response)
- [Maintenance Procedures](#maintenance-procedures)
- [Emergency Procedures](#emergency-procedures)

## Daily Operations

### Morning Health Check

**Frequency**: Every business day
**Duration**: 5 minutes
**Responsibility**: On-call engineer

**Procedure**:

1. **Check backup service status**
   ```bash
   railway status
   # Or: docker ps | grep backup
   ```
   - ✅ Service is running
   - ❌ Service is stopped → Investigate logs, restart if needed

2. **Verify recent backups exist**
   ```bash
   aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ \
     --endpoint-url ${S3_ENDPOINT} \
     --recursive | tail -5
   ```
   - ✅ Backups from last 24 hours exist
   - ❌ No recent backups → Check backup service logs

3. **Check verify service status**
   ```bash
   railway logs --service verify | tail -50
   ```
   - ✅ Recent verification passed
   - ❌ Verification failed → Review logs, may indicate backup corruption

4. **Check disk space**
   ```bash
   railway run df -h
   ```
   - ✅ > 20% free space
   - ⚠️ 10-20% free → Plan cleanup
   - ❌ < 10% free → Immediate action required

5. **Review alerts**
   - Check monitoring dashboard
   - Review any alert notifications
   - Acknowledge and assign if needed

**Expected Results**:
- All services running
- Recent backups exist
- Recent verification passed
- Sufficient disk space

**Escalation**:
- If any checks fail, follow [Incident Response](#incident-response)

### Check Backup Logs

**Frequency**: Daily
**Duration**: 2 minutes

**Procedure**:

```bash
# View last 100 lines of backup service logs
railway logs --service backup | tail -100

# Look for:
# - "Backup completed successfully"
# - No ERROR messages
# - Reasonable backup file sizes
```

**Red flags**:
- ❌ "ERROR" messages
- ❌ Backup file is 0 bytes
- ❌ "Connection refused"
- ❌ "Access Denied"

**Action**:
- If red flags found, investigate using [Troubleshooting Guide](troubleshooting.md)

### Monitor Backup File Sizes

**Frequency**: Daily
**Duration**: 2 minutes

**Procedure**:

```bash
# Get backup sizes for last 7 days
aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ \
  --endpoint-url ${S3_ENDPOINT} \
  --recursive \
  --human-readable | tail -20
```

**Analysis**:
- Compare sizes to baseline
- ✅ Sizes similar to previous backups (±20%)
- ⚠️ Size increased 20-50% → Check for data growth
- ❌ Size decreased >50% or is 0 → Investigate backup failure
- ❌ Size increased >100% → Check for unexpected data growth

**Action**:
- Document baseline size weekly
- Alert if size deviates significantly

## Weekly Operations

### Backup Verification Report

**Frequency**: Weekly (Monday)
**Duration**: 10 minutes
**Responsibility**: Team lead

**Procedure**:

1. **Review verification success rate**
   ```bash
   # Count successful verifications in last 7 days
   railway logs --service verify --since 7d | \
     grep -c "Restore verification completed successfully"

   # Count failed verifications
   railway logs --service verify --since 7d | \
     grep -c "Restore verification failed"
   ```

2. **Calculate success rate**
   ```
   Success Rate = Successful / (Successful + Failed) × 100%
   ```

3. **Review verification duration trends**
   ```bash
   # Extract verification durations from logs
   railway logs --service verify --since 7d | \
     grep "Verification finished"
   ```

4. **Document findings**
   - Success rate (target: >95%)
   - Average verification time
   - Any issues or trends

**Expected Results**:
- Success rate: >95%
- Verification time: Stable or decreasing

**Escalation**:
- Success rate <95% → Investigate failures
- Verification time increasing → Check database growth

### Storage Usage Review

**Frequency**: Weekly (Friday)
**Duration**: 5 minutes

**Procedure**:

1. **Check S3 bucket size**
   ```bash
   # Get total bucket size
   aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ \
     --endpoint-url ${S3_ENDPOINT} \
     --recursive \
     --summarize \
     --human-readable
   ```

2. **Count backup files**
   ```bash
   aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ \
     --endpoint-url ${S3_ENDPOINT} \
     --recursive | wc -l
   ```

3. **Calculate storage cost**
   ```
   Monthly Cost = Total Size (GB) × Price per GB
   ```

4. **Verify retention policy**
   ```bash
   # Check oldest backup
   aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ \
     --endpoint-url ${S3_ENDPOINT} \
     --recursive | head -5

   # Should be approximately BACKUP_RETENTION_DAYS old
   ```

**Expected Results**:
- Storage growth is predictable
- Oldest backup matches retention policy
- Cost is within budget

**Action**:
- Adjust BACKUP_RETENTION_DAYS if cost is too high
- Increase storage if nearing quota

### Test Restore Drill

**Frequency**: Weekly (Wednesday)
**Duration**: 30-60 minutes
**Responsibility**: Engineering team (rotation)

**Procedure**:

1. **Select random backup** (not latest)
   ```bash
   RANDOM_BACKUP=$(aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ \
     --endpoint-url ${S3_ENDPOINT} --recursive | \
     sort -R | head -n 1 | awk '{print $4}')

   echo "Testing: $RANDOM_BACKUP"
   ```

2. **Download backup**
   ```bash
   aws s3 cp "s3://${S3_BUCKET}/${RANDOM_BACKUP}" \
     ./weekly-test/ \
     --endpoint-url ${S3_ENDPOINT}
   ```

3. **Create test database**
   ```bash
   psql -h test-server -U postgres -c "DROP DATABASE IF EXISTS weekly_restore_test;"
   psql -h test-server -U postgres -c "CREATE DATABASE weekly_restore_test;"
   ```

4. **Restore**
   ```bash
   time gunzip -c "./weekly-test/$(basename $RANDOM_BACKUP)" | \
     psql -h test-server -U postgres -d weekly_restore_test
   ```

5. **Run verification queries**
   ```bash
   psql -h test-server -U postgres -d weekly_restore_test -f verification-queries.sql
   ```

6. **Document results**
   - Backup date
   - Backup size
   - Restore duration
   - Any errors or warnings
   - Pass/Fail

7. **Cleanup**
   ```bash
   psql -h test-server -U postgres -c "DROP DATABASE weekly_restore_test;"
   rm -rf weekly-test/
   ```

**Expected Results**:
- Restore completes without errors
- Verification queries pass
- Restore time within acceptable range

**Escalation**:
- If restore fails, follow [Emergency Restore Failure](#emergency-restore-failure)

## Monthly Operations

### Security Review

**Frequency**: Monthly (First Monday)
**Duration**: 30 minutes
**Responsibility**: Security lead

**Procedure**:

1. **Review access logs**
   ```bash
   # S3 access logs (if enabled)
   aws s3 ls s3://${LOGS_BUCKET}/s3-access-logs/ \
     --endpoint-url ${S3_ENDPOINT} \
     --recursive
   ```

2. **Verify credentials rotation schedule**
   - Database passwords: Last rotated?
   - S3 access keys: Last rotated?
   - Action if >90 days: Schedule rotation

3. **Review IAM permissions**
   - Are permissions still following least privilege?
   - Any unused permissions?
   - Any overly broad permissions?

4. **Check for exposed secrets**
   ```bash
   # Search git history for potential secrets
   git log --all --full-history --source --pickaxe-regex -S "password|secret|key" -- .
   ```

5. **Review encryption**
   - S3 bucket encryption enabled?
   - Database SSL/TLS enabled?
   - In-transit encryption verified?

6. **Update security documentation**
   - Document any changes
   - Update [SECURITY.md](../SECURITY.md) if needed

**Action Items**:
- Schedule credential rotation if needed
- Fix any security issues found
- Document security posture

### Performance Review

**Frequency**: Monthly (Second Monday)
**Duration**: 45 minutes
**Responsibility**: Engineering lead

**Procedure**:

1. **Analyze backup duration trends**
   ```bash
   # Extract backup durations from logs for last 30 days
   railway logs --service backup --since 30d | \
     grep "Backup completed successfully"
   ```

2. **Analyze database growth**
   ```bash
   # Get database size
   psql "$DATABASE_URL" -c "SELECT pg_size_pretty(pg_database_size(current_database()));"

   # Compare to last month
   ```

3. **Review backup intervals**
   - Is current interval still appropriate?
   - Should it be increased/decreased?

4. **Analyze storage costs**
   ```
   Current Month Cost = S3 Size × Price
   Trend = (Current - Last Month) / Last Month × 100%
   ```

5. **Review resource utilization**
   ```bash
   # Check Railway service metrics
   railway metrics --service backup
   railway metrics --service verify
   ```

6. **Optimize if needed**
   - Adjust BACKUP_INTERVAL
   - Adjust COMPRESSION_LEVEL
   - Adjust BACKUP_RETENTION_DAYS
   - Increase service resources

**Document**:
- Current performance metrics
- Trends
- Any optimization actions taken
- Projected costs for next month

### Disaster Recovery Test

**Frequency**: Monthly (Third Wednesday)
**Duration**: 2-4 hours
**Responsibility**: Full engineering team

**Procedure**:

1. **Schedule maintenance window**
   - Notify stakeholders
   - 2-4 hour window
   - Off-peak hours

2. **Scenario: Complete database loss**
   - Document current database state
   - Backup current state (in addition to automated backups)

3. **Simulate disaster** (in staging environment)
   - Deploy separate test environment
   - Download latest backup
   - Restore from backup
   - Verify application functionality

4. **Measure**
   - Detection time (how quickly was issue identified?)
   - Response time (how quickly did team respond?)
   - Recovery time (how long until service restored?)
   - Data loss (how much data lost?)

5. **Document**
   - What worked well
   - What didn't work well
   - Lessons learned
   - Action items for improvement

6. **Update runbooks**
   - Update based on lessons learned
   - Clarify ambiguous steps
   - Add missing procedures

**Success Criteria**:
- Restore completed successfully
- Application functional after restore
- RTO (Recovery Time Objective) met
- RPO (Recovery Point Objective) met

**Follow-up**:
- Team retrospective
- Update documentation
- Implement improvements

## Incident Response

### Backup Service Down

**Severity**: High
**Response Time**: 15 minutes

**Immediate Actions**:

1. **Check service status**
   ```bash
   railway status
   ```

2. **Check logs**
   ```bash
   railway logs --service backup | tail -100
   ```

3. **Attempt restart**
   ```bash
   railway restart --service backup
   ```

4. **Verify restart**
   ```bash
   railway logs --service backup --follow
   # Wait for "Backup service started"
   ```

5. **If restart fails**
   - Review logs for errors
   - Check [Troubleshooting Guide](troubleshooting.md)
   - Fix configuration issues
   - Redeploy if needed

**Communication**:
- Alert team in incident channel
- Update status page (if applicable)
- Document incident timeline

**Follow-up**:
- Post-incident review within 48 hours
- Update runbooks based on findings

### Verification Failing

**Severity**: Medium
**Response Time**: 1 hour

**Immediate Actions**:

1. **Check last successful verification**
   ```bash
   railway logs --service verify | \
     grep "Restore verification completed successfully" | tail -1
   ```

2. **Review failure logs**
   ```bash
   railway logs --service verify | grep -A 10 "ERROR"
   ```

3. **Test backup manually**
   - Download latest backup
   - Attempt manual restore
   - If restore succeeds, issue is with verify service
   - If restore fails, issue is with backup

4. **If backup is corrupt**
   - Follow [Emergency Backup Corruption](#emergency-backup-corruption)

5. **If verify service issue**
   - Check database permissions
   - Check disk space
   - Restart verify service
   - Review configuration

**Communication**:
- Alert team
- Document issue

**Follow-up**:
- Determine root cause
- Implement preventive measures

### S3 Storage Outage

**Severity**: High
**Response Time**: Immediate

**Immediate Actions**:

1. **Verify S3 is down**
   ```bash
   curl -I ${S3_ENDPOINT}
   # Or check provider status page
   ```

2. **Check S3 provider status**
   - AWS: https://status.aws.amazon.com/
   - Backblaze: https://status.backblaze.com/
   - Check specific provider

3. **If provider outage**
   - Wait for provider to resolve
   - Monitor status page
   - Backups will resume automatically when S3 is available

4. **If not provider outage**
   - Check credentials
   - Check network connectivity
   - Check firewall rules
   - Follow [Troubleshooting Guide](troubleshooting.md#s3-connection-issues)

5. **Temporary mitigation** (if S3 down for extended period)
   - Consider switching to alternative S3 provider
   - Or temporarily disable backup service (not recommended)

**Communication**:
- Alert team
- Notify stakeholders if downtime expected
- Update status page

**Follow-up**:
- Consider multi-region S3 replication
- Implement backup to secondary storage

### Database Connection Lost

**Severity**: Critical
**Response Time**: Immediate

**Immediate Actions**:

1. **Verify database status**
   ```bash
   psql "$DATABASE_URL" -c "SELECT version();"
   ```

2. **If database is down**
   - Check database service status
   - Restart database if needed
   - Follow database runbooks

3. **If database is up but backup can't connect**
   - Check network connectivity
   - Check credentials
   - Check firewall rules
   - Review DATABASE_URL configuration

4. **If database is up**
   - Backup service will continue attempting
   - Fix connection issue
   - Backups will resume automatically

**Communication**:
- Alert database team
- Coordinate response

**Follow-up**:
- Review database monitoring
- Implement better health checks

## Maintenance Procedures

### Rotating Database Credentials

**Frequency**: Every 90 days or as needed
**Duration**: 30 minutes
**Downtime**: None (if done correctly)

**Procedure**:

1. **Create new credentials**
   ```bash
   # Create new database user
   psql -U postgres -c "CREATE USER backup_user_new WITH PASSWORD 'new_secure_password';"

   # Grant permissions
   psql -U postgres -d your_db -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO backup_user_new;"
   psql -U postgres -c "ALTER USER backup_user_new CREATEDB;"  # For verify service
   ```

2. **Update environment variables**
   ```bash
   # Update DATABASE_URL with new credentials
   NEW_DATABASE_URL="postgresql://backup_user_new:new_secure_password@host:5432/db"

   railway variables set DATABASE_URL="$NEW_DATABASE_URL" --service backup
   railway variables set VERIFY_DATABASE_URL="$NEW_VERIFY_DATABASE_URL" --service verify
   ```

3. **Restart services**
   ```bash
   railway restart --service backup
   railway restart --service verify
   ```

4. **Verify services work**
   ```bash
   railway logs --service backup --follow
   # Wait for successful backup

   railway logs --service verify --follow
   # Wait for successful verification
   ```

5. **Remove old credentials**
   ```bash
   # Only after verifying new credentials work!
   psql -U postgres -c "DROP USER backup_user_old;"
   ```

6. **Document**
   - Date of rotation
   - Old username (not password!)
   - New username (not password!)

### Rotating S3 Credentials

**Frequency**: Every 90 days or as needed
**Duration**: 30 minutes
**Downtime**: None (if done correctly)

**Procedure**:

1. **Create new S3 access key**
   - AWS: IAM Console → Users → Security Credentials → Create Access Key
   - Other providers: Follow provider documentation

2. **Update environment variables**
   ```bash
   railway variables set S3_ACCESS_KEY_ID="new_key_id" --service backup
   railway variables set S3_SECRET_ACCESS_KEY="new_secret_key" --service backup

   railway variables set S3_ACCESS_KEY_ID="new_key_id" --service verify
   railway variables set S3_SECRET_ACCESS_KEY="new_secret_key" --service verify
   ```

3. **Restart services**
   ```bash
   railway restart --service backup
   railway restart --service verify
   ```

4. **Verify services work**
   ```bash
   railway logs --service backup --follow
   railway logs --service verify --follow
   ```

5. **Deactivate old credentials**
   - AWS: IAM Console → Users → Security Credentials → Make Inactive
   - Wait 24 hours to ensure no issues
   - Then delete old access key

6. **Document**
   - Date of rotation
   - Old access key ID
   - New access key ID

### Upgrading PostgreSQL Version

**Frequency**: As needed
**Duration**: 2-4 hours
**Downtime**: Yes (for database)

**Procedure**:

1. **Backup current state**
   ```bash
   # Force immediate backup
   railway run --service backup /app/backup.sh
   ```

2. **Download recent backup**
   ```bash
   aws s3 cp s3://${S3_BUCKET}/${BACKUP_PREFIX}/backup_latest.sql.gz ./upgrade-backup/ \
     --endpoint-url ${S3_ENDPOINT}
   ```

3. **Provision new PostgreSQL version**
   - Deploy new PostgreSQL service (new version)
   - Configure networking
   - Create databases

4. **Restore backup to new version**
   ```bash
   gunzip -c upgrade-backup/backup_latest.sql.gz | \
     psql -h new-postgres-host -U postgres -d new_db
   ```

5. **Test application with new database**
   - Update DATABASE_URL to point to new database
   - Run application tests
   - Verify functionality

6. **Update backup services**
   ```bash
   # Update DATABASE_URL for both services
   railway variables set DATABASE_URL="postgresql://user:pass@new-postgres-host:5432/new_db" \
     --service backup
   railway variables set DATABASE_URL="postgresql://user:pass@new-postgres-host:5432/postgres" \
     --service verify

   railway restart --service backup
   railway restart --service verify
   ```

7. **Verify backups work**
   ```bash
   railway logs --service backup --follow
   railway logs --service verify --follow
   ```

8. **Decommission old database**
   - Wait 7 days
   - Verify everything working
   - Delete old PostgreSQL service

9. **Document upgrade**
   - Old version
   - New version
   - Date
   - Any issues encountered

### Adjusting Backup Frequency

**Frequency**: As needed
**Duration**: 5 minutes
**Downtime**: None

**Procedure**:

1. **Determine new interval**
   - Consider database size
   - Consider change frequency
   - Consider RTO/RPO requirements
   - Examples: 3600 (1h), 21600 (6h), 86400 (24h)

2. **Calculate storage impact**
   ```
   Daily Backups = 86400 / NEW_INTERVAL
   Storage Required = Database Size × Compression Ratio × Daily Backups × Retention Days
   ```

3. **Update configuration**
   ```bash
   railway variables set BACKUP_INTERVAL="21600" --service backup
   ```

4. **Restart backup service**
   ```bash
   railway restart --service backup
   ```

5. **Verify new interval**
   ```bash
   railway logs --service backup --follow
   # Check for "Next backup in XXXXs"
   ```

6. **Document change**
   - Old interval
   - New interval
   - Reason for change
   - Date

## Emergency Procedures

### Emergency Restore Failure

**Severity**: Critical
**Situation**: Need to restore database but restore is failing

**Immediate Actions**:

1. **Don't panic**
   - Assess situation calmly
   - Multiple backups exist

2. **Try previous backup**
   ```bash
   # List backups
   aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ \
     --endpoint-url ${S3_ENDPOINT} --recursive | tail -10

   # Try second-most-recent backup
   aws s3 cp s3://${S3_BUCKET}/${BACKUP_PREFIX}/backup_SECOND_LATEST.sql.gz ./emergency/ \
     --endpoint-url ${S3_ENDPOINT}
   ```

3. **Verify backup integrity**
   ```bash
   gunzip -t emergency/backup_SECOND_LATEST.sql.gz
   ```

4. **Attempt restore**
   ```bash
   gunzip -c emergency/backup_SECOND_LATEST.sql.gz | \
     psql -h target-host -U postgres -d target_db 2>&1 | tee restore.log
   ```

5. **If still failing**
   - Try third-most-recent backup
   - Review error messages in restore.log
   - Contact PostgreSQL expert
   - Check [Troubleshooting Guide](troubleshooting.md#restore-issues)

6. **Last resort**
   - Restore to older PostgreSQL version
   - Restore partial tables
   - Contact storage provider for backup recovery

**Communication**:
- Alert entire team
- Notify stakeholders
- Set up war room
- Provide hourly updates

**Follow-up**:
- Full post-mortem
- Update disaster recovery plan
- Implement additional safeguards

### Emergency Backup Corruption

**Severity**: Critical
**Situation**: All recent backups are corrupted

**Immediate Actions**:

1. **Verify corruption**
   ```bash
   # Test last 5 backups
   for backup in $(aws s3 ls s3://${S3_BUCKET}/${BACKUP_PREFIX}/ --endpoint-url ${S3_ENDPOINT} --recursive | tail -5 | awk '{print $4}'); do
     echo "Testing: $backup"
     aws s3 cp "s3://${S3_BUCKET}/${backup}" ./test.gz --endpoint-url ${S3_ENDPOINT}
     gunzip -t test.gz && echo "OK" || echo "CORRUPTED"
     rm test.gz
   done
   ```

2. **Find last good backup**
   - Test progressively older backups
   - Document which backups are good

3. **Immediate mitigation**
   - Stop backup service (to prevent more corrupted backups)
   ```bash
   railway stop --service backup
   ```

4. **Investigate root cause**
   - Check disk space on backup service
   - Check database health
   - Review backup service logs
   - Check S3 storage health

5. **Fix root cause**
   - Increase disk space
   - Fix database issues
   - Fix configuration
   - Repair storage

6. **Test backup**
   ```bash
   # Run manual backup
   railway run --service backup /app/backup.sh

   # Verify it's not corrupted
   aws s3 cp s3://${S3_BUCKET}/${BACKUP_PREFIX}/backup_latest.sql.gz ./test.gz \
     --endpoint-url ${S3_ENDPOINT}
   gunzip -t test.gz
   ```

7. **Resume backup service**
   ```bash
   railway start --service backup
   ```

8. **Verify backups resuming correctly**
   ```bash
   railway logs --service backup --follow
   ```

**Communication**:
- Alert entire team immediately
- Notify management
- Document timeline

**Follow-up**:
- Full root cause analysis
- Implement backup integrity monitoring
- Consider backup redundancy (multiple S3 buckets)

### Emergency: Out of Disk Space

**Severity**: High
**Situation**: Backup service failing due to no disk space

**Immediate Actions**:

1. **Verify disk usage**
   ```bash
   railway run --service backup df -h
   ```

2. **Identify large files**
   ```bash
   railway run --service backup du -h /tmp | sort -rh | head -10
   ```

3. **Clean up temporary files**
   ```bash
   railway run --service backup "rm -f /tmp/backup_*.sql /tmp/backup_*.sql.gz"
   ```

4. **Check if old backups stuck in temp**
   ```bash
   railway run --service backup "ls -lah /tmp/"
   ```

5. **Increase disk space**
   - Railway: Increase service disk allocation
   - Docker: Increase volume size

6. **Restart backup service**
   ```bash
   railway restart --service backup
   ```

7. **Verify backups resuming**
   ```bash
   railway logs --service backup --follow
   ```

**Prevention**:
- Monitor disk usage daily
- Set up alerts for disk usage >80%
- Ensure backup cleanup is working
- Review BACKUP_INTERVAL vs database size

**Follow-up**:
- Implement disk usage monitoring
- Add automated cleanup
- Document disk space requirements

## Contacts

### Escalation Path

1. **On-call Engineer** - First responder
2. **Engineering Lead** - Escalation for complex issues
3. **CTO/VP Engineering** - Critical incidents
4. **External Support** - Provider support (Railway, S3 provider, PostgreSQL consultants)

### External Contacts

- **Railway Support**: https://railway.app/help
- **AWS Support**: (if using AWS)
- **Backblaze Support**: https://www.backblaze.com/company/contact (if using B2)
- **PostgreSQL Mailing List**: pgsql-general@postgresql.org

## Documentation

Keep these runbooks updated:
- Review quarterly
- Update after each incident
- Incorporate lessons learned
- Keep procedures current with actual practice

**Last Updated**: 2024-02-07
**Next Review**: 2024-05-07

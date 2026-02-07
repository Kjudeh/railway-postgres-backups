#!/bin/bash
set -euo pipefail

# ========================================
# PostgreSQL Restore Verification Entrypoint
# ========================================
# Safety validation before running verification service
# Ensures VERIFY_DATABASE_URL is set and different from DATABASE_URL

echo "=========================================="
echo "PostgreSQL Restore Verification Service"
echo "=========================================="

# Required environment variables for verification
required_vars=(
    "VERIFY_DATABASE_URL"
    "S3_ENDPOINT"
    "S3_BUCKET"
    "S3_ACCESS_KEY_ID"
    "S3_SECRET_ACCESS_KEY"
)

# Check all required variables are set
echo "Checking required environment variables..."
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Required environment variable $var is not set" >&2
        echo "Please configure $var before running the verify service" >&2
        exit 1
    fi
    echo "  ✓ $var is set"
done

# CRITICAL SAFETY CHECK: Ensure VERIFY_DATABASE_URL is different from DATABASE_URL
echo ""
echo "Running safety validation..."

# If DATABASE_URL is set, verify it's different from VERIFY_DATABASE_URL
if [ -n "${DATABASE_URL:-}" ]; then
    # Extract database names from URLs for comparison
    verify_db=$(echo "$VERIFY_DATABASE_URL" | sed -n 's#.*://[^/]*/\([^?]*\).*#\1#p')
    primary_db=$(echo "$DATABASE_URL" | sed -n 's#.*://[^/]*/\([^?]*\).*#\1#p')

    # Extract host:port for comparison
    verify_host=$(echo "$VERIFY_DATABASE_URL" | sed -n 's#.*://[^@]*@\([^/]*\)/.*#\1#p')
    primary_host=$(echo "$DATABASE_URL" | sed -n 's#.*://[^@]*@\([^/]*\)/.*#\1#p')

    if [ "$VERIFY_DATABASE_URL" = "$DATABASE_URL" ]; then
        echo "=========================================="
        echo "CRITICAL SAFETY CHECK FAILED"
        echo "=========================================="
        echo "ERROR: VERIFY_DATABASE_URL equals DATABASE_URL" >&2
        echo "" >&2
        echo "This is extremely dangerous! The verify service would:" >&2
        echo "  - Create temporary databases on your PRIMARY server" >&2
        echo "  - Potentially overwrite production data" >&2
        echo "  - Cause production downtime" >&2
        echo "" >&2
        echo "SOLUTION: Set VERIFY_DATABASE_URL to a DIFFERENT database:" >&2
        echo "  - Use a separate PostgreSQL instance, OR" >&2
        echo "  - Use a different database on the same server" >&2
        echo "" >&2
        echo "Example:" >&2
        echo "  DATABASE_URL=postgresql://user:pass@prod-host:5432/production" >&2
        echo "  VERIFY_DATABASE_URL=postgresql://user:pass@test-host:5432/postgres" >&2
        echo "" >&2
        echo "Refusing to start. This is a safety feature." >&2
        echo "=========================================="
        exit 1
    fi

    # Warn if on same host but different database
    if [ "$verify_host" = "$primary_host" ] && [ "$verify_db" != "$primary_db" ]; then
        echo "WARNING: VERIFY_DATABASE_URL and DATABASE_URL are on the same host"
        echo "  Primary: $primary_host/$primary_db"
        echo "  Verify:  $verify_host/$verify_db"
        echo ""
        echo "This is allowed but not recommended because:"
        echo "  - Restore drills will consume resources on your primary database server"
        echo "  - May impact production performance"
        echo ""
        echo "RECOMMENDATION: Use a separate PostgreSQL instance for verification"
        echo ""
        echo "Continuing in 5 seconds... (Ctrl+C to cancel)"
        sleep 5
    fi

    echo "  ✓ VERIFY_DATABASE_URL is different from DATABASE_URL"
    echo "    Primary: $primary_host/$primary_db"
    echo "    Verify:  $verify_host/$verify_db"
else
    echo "  ⚠ DATABASE_URL not set (safety check skipped)"
    echo "    Ensure VERIFY_DATABASE_URL points to a non-production database"
fi

# Validate VERIFY_DATABASE_URL format
if [[ ! "$VERIFY_DATABASE_URL" =~ ^postgresql:// ]]; then
    echo "ERROR: VERIFY_DATABASE_URL must start with 'postgresql://'" >&2
    # Redact password before displaying
    echo "Got: $(echo "$VERIFY_DATABASE_URL" | sed 's/:\/\/[^:]*:[^@]*@/:\/\/***:***@/')" >&2
    exit 1
fi
echo "  ✓ VERIFY_DATABASE_URL format is valid"

# Test database connectivity
echo ""
echo "Testing database connectivity..."
if PGPASSWORD=$(echo "$VERIFY_DATABASE_URL" | sed -n 's#.*://[^:]*:\([^@]*\)@.*#\1#p') \
   psql "$VERIFY_DATABASE_URL" -c "SELECT version();" > /dev/null 2>&1; then
    echo "  ✓ Successfully connected to verify database"
else
    echo "ERROR: Cannot connect to VERIFY_DATABASE_URL" >&2
    echo "Please check:" >&2
    echo "  - Database is running" >&2
    echo "  - Credentials are correct" >&2
    echo "  - Network connectivity" >&2
    echo "  - Firewall rules" >&2
    exit 1
fi

# Test S3 connectivity
echo ""
echo "Testing S3 connectivity..."
export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="${S3_REGION:-us-east-1}"

if aws s3 ls "s3://${S3_BUCKET}/" --endpoint-url "$S3_ENDPOINT" > /dev/null 2>&1; then
    echo "  ✓ Successfully connected to S3"
else
    echo "ERROR: Cannot connect to S3" >&2
    echo "Please check:" >&2
    echo "  - S3_ENDPOINT is correct" >&2
    echo "  - S3_BUCKET exists" >&2
    echo "  - S3 credentials are valid" >&2
    echo "  - Network connectivity" >&2
    exit 1
fi

# Verify backups exist
echo ""
echo "Checking for backups..."
backup_count=$(aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX:-postgres-backups}/" \
    --endpoint-url "$S3_ENDPOINT" \
    --recursive 2>/dev/null | grep -c '\.sql\.gz$' || echo "0")

if [ "$backup_count" -gt 0 ]; then
    echo "  ✓ Found $backup_count backup(s) in S3"
else
    echo "WARNING: No backups found in S3" >&2
    echo "  The verify service will wait for backups to become available" >&2
    echo "  Ensure the backup service is running and creating backups" >&2
fi

# Validate webhook URL if set
if [ -n "${VERIFY_WEBHOOK_URL:-}" ]; then
    echo ""
    echo "Webhook notification enabled"
    echo "  Webhook URL: ${VERIFY_WEBHOOK_URL}"
    if [[ ! "$VERIFY_WEBHOOK_URL" =~ ^https?:// ]]; then
        echo "WARNING: VERIFY_WEBHOOK_URL should start with http:// or https://" >&2
    fi
fi

# Display configuration
echo ""
echo "=========================================="
echo "Configuration Summary"
echo "=========================================="
echo "Verify Database: $(echo "$VERIFY_DATABASE_URL" | sed 's/:\/\/[^:]*:[^@]*@/:\/\/***:***@/')"
echo "S3 Endpoint:     ${S3_ENDPOINT}"
echo "S3 Bucket:       ${S3_BUCKET}"
echo "Backup Prefix:   ${BACKUP_PREFIX:-postgres-backups}"
echo "Verify Interval: ${VERIFY_INTERVAL:-86400}s ($(( ${VERIFY_INTERVAL:-86400} / 3600 ))h)"
echo "Verify Latest:   ${VERIFY_LATEST:-true}"
if [ -n "${VERIFY_BACKUP_FILE:-}" ]; then
    echo "Specific Backup: ${VERIFY_BACKUP_FILE}"
fi
if [ -n "${VERIFY_SQL:-}" ]; then
    echo "Custom SQL:      Enabled"
fi
if [ -n "${VERIFY_WEBHOOK_URL:-}" ]; then
    echo "Webhook:         Enabled"
fi
echo "=========================================="

echo ""
echo "All safety checks passed! Starting verification service..."
echo ""

# Execute the verification script
exec /app/verify.sh

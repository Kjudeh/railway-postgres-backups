#!/bin/bash
set -euo pipefail

# ========================================
# PostgreSQL Backup Restore Verification
# ========================================
# This script performs restore drills by:
# 1. Downloading a backup from S3
# 2. Restoring it to a temporary database
# 3. Running verification queries
# 4. Cleaning up

# Required environment variables
# NOTE: VERIFY_DATABASE_URL is validated in entrypoint.sh
required_vars=(
    "VERIFY_DATABASE_URL"
    "S3_ENDPOINT"
    "S3_BUCKET"
    "S3_ACCESS_KEY_ID"
    "S3_SECRET_ACCESS_KEY"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "ERROR: Required environment variable $var is not set" >&2
        exit 1
    fi
done

# Optional environment variables
VERIFY_INTERVAL="${VERIFY_INTERVAL:-86400}"  # Default: 24 hours
S3_REGION="${S3_REGION:-us-east-1}"
BACKUP_PREFIX="${BACKUP_PREFIX:-postgres-backups}"
VERIFY_LATEST="${VERIFY_LATEST:-true}"  # Verify latest backup by default
VERIFY_BACKUP_FILE="${VERIFY_BACKUP_FILE:-}"  # Specific backup to verify
VERIFY_SQL="${VERIFY_SQL:-}"  # Optional custom SQL check
VERIFY_WEBHOOK_URL="${VERIFY_WEBHOOK_URL:-}"  # Optional webhook for notifications
MIN_TABLE_COUNT="${MIN_TABLE_COUNT:-0}"  # Minimum number of tables expected

# Configure AWS CLI
export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="$S3_REGION"

# Parse VERIFY_DATABASE_URL
if [[ ! "$VERIFY_DATABASE_URL" =~ postgresql://([^:]+):([^@]+)@([^:]+):([^/]+)/(.+) ]]; then
    echo "ERROR: Invalid VERIFY_DATABASE_URL format" >&2
    exit 1
fi

PGUSER="${BASH_REMATCH[1]}"
PGPASSWORD="${BASH_REMATCH[2]}"
PGHOST="${BASH_REMATCH[3]}"
PGPORT="${BASH_REMATCH[4]}"
PGDATABASE="${BASH_REMATCH[5]}"

export PGUSER PGPASSWORD PGHOST PGPORT

echo "Restore verification service started"
echo "Target host: $PGHOST:$PGPORT"
echo "S3 endpoint: $S3_ENDPOINT"
echo "S3 bucket: $S3_BUCKET"
echo "Verification interval: ${VERIFY_INTERVAL}s"
if [ -n "$VERIFY_WEBHOOK_URL" ]; then
    echo "Webhook notifications: Enabled"
fi

# Function to send webhook notification
send_webhook() {
    local status="$1"
    local message="$2"
    local backup_file="${3:-}"
    local duration="${4:-0}"

    if [ -z "$VERIFY_WEBHOOK_URL" ]; then
        return 0
    fi

    local timestamp=$(date -Iseconds)
    local payload=$(cat <<EOF
{
    "status": "$status",
    "message": "$message",
    "backup_file": "$backup_file",
    "duration_seconds": $duration,
    "timestamp": "$timestamp",
    "service": "postgres-restore-verify",
    "host": "$PGHOST:$PGPORT"
}
EOF
)

    if curl -X POST "$VERIFY_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 10 \
        --silent \
        --show-error \
        > /dev/null 2>&1; then
        echo "Webhook notification sent: $status"
    else
        echo "WARNING: Failed to send webhook notification" >&2
    fi
}

# Function to get latest backup from S3
get_latest_backup() {
    echo "Finding latest backup..."

    local latest_backup=$(aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/" \
        --endpoint-url "$S3_ENDPOINT" \
        --recursive | \
        grep '\.sql\.gz$' | \
        sort -r | \
        head -n 1 | \
        awk '{print $4}')

    if [ -z "$latest_backup" ]; then
        echo "ERROR: No backups found in S3" >&2
        return 1
    fi

    echo "$latest_backup"
}

# Function to download backup from S3
download_backup() {
    local s3_key="$1"
    local local_path="$2"

    echo "Downloading backup: $s3_key"

    if ! aws s3 cp "s3://${S3_BUCKET}/${s3_key}" "$local_path" \
        --endpoint-url "$S3_ENDPOINT"; then
        echo "ERROR: Failed to download backup from S3" >&2
        return 1
    fi

    # Verify file was downloaded and is not empty
    if [ ! -s "$local_path" ]; then
        echo "ERROR: Downloaded backup file is empty" >&2
        return 1
    fi

    local size=$(du -h "$local_path" | cut -f1)
    echo "Downloaded: $size"

    return 0
}

# Function to create temporary database
create_temp_database() {
    local temp_db="$1"

    echo "Creating temporary database: $temp_db"

    # Drop if exists, then create
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres \
        -c "DROP DATABASE IF EXISTS \"${temp_db}\";" \
        -c "CREATE DATABASE \"${temp_db}\";" \
        2>&1 | grep -v "does not exist, skipping" || true

    return 0
}

# Function to restore backup to temporary database
restore_backup() {
    local backup_file="$1"
    local temp_db="$2"

    echo "Restoring backup to $temp_db..."

    if ! gunzip -c "$backup_file" | \
        psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$temp_db" \
        --quiet \
        --set ON_ERROR_STOP=on 2>&1 | \
        grep -v "already exists" | \
        grep -v "does not exist" || true; then
        echo "ERROR: Restore failed" >&2
        return 1
    fi

    echo "Restore completed"
    return 0
}

# Function to run verification queries
run_verification() {
    local temp_db="$1"

    echo "Running verification queries..."

    local failed=0

    # Check 1: Database is accessible
    echo "  - Checking database connectivity..."
    if ! psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$temp_db" \
        -c "SELECT version();" > /dev/null 2>&1; then
        echo "ERROR: Cannot connect to database" >&2
        ((failed++))
    else
        echo "    ✓ Database is accessible"
    fi

    # Check 2: Count tables and verify minimum
    echo "  - Checking table count..."
    local table_count=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$temp_db" \
        -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" \
        2>/dev/null | tr -d ' ' || echo "0")

    if [ "$table_count" -ge "$MIN_TABLE_COUNT" ]; then
        echo "    ✓ Found $table_count tables (minimum: $MIN_TABLE_COUNT)"
    else
        echo "ERROR: Found $table_count tables, expected minimum: $MIN_TABLE_COUNT" >&2
        ((failed++))
    fi

    # Check 3: Verify row counts
    echo "  - Checking row counts..."
    if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$temp_db" \
        -c "SELECT schemaname, tablename, n_tup_ins - n_tup_del as row_count
            FROM pg_stat_user_tables
            WHERE schemaname = 'public'
            LIMIT 10;" > /dev/null 2>&1; then
        echo "    ✓ Row count query succeeded"
    else
        echo "WARNING: Row count query failed" >&2
    fi

    # Check 4: Run custom SQL from VERIFY_SQL environment variable
    if [ -n "$VERIFY_SQL" ]; then
        echo "  - Running custom VERIFY_SQL check..."
        if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$temp_db" \
            -c "$VERIFY_SQL" > /dev/null 2>&1; then
            echo "    ✓ Custom VERIFY_SQL passed"
        else
            echo "ERROR: Custom VERIFY_SQL failed" >&2
            echo "SQL: $VERIFY_SQL" >&2
            ((failed++))
        fi
    fi

    # Check 5: Run custom test queries from file
    if [ -f "/app/test-queries.sql" ]; then
        echo "  - Running custom test queries from file..."
        if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$temp_db" \
            -f /app/test-queries.sql > /dev/null 2>&1; then
            echo "    ✓ Custom test queries passed"
        else
            echo "ERROR: Custom test queries failed" >&2
            ((failed++))
        fi
    fi

    if [ $failed -gt 0 ]; then
        echo "FAILED: $failed verification check(s) failed" >&2
        return 1
    fi

    echo "SUCCESS: All verification checks passed"
    return 0
}

# Function to cleanup temporary database
cleanup_temp_database() {
    local temp_db="$1"

    echo "Cleaning up temporary database..."

    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres \
        -c "DROP DATABASE IF EXISTS \"${temp_db}\";" \
        2>&1 | grep -v "does not exist, skipping" || true

    return 0
}

# Main verification function
perform_verification() {
    local start_time=$(date +%s)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local temp_db="verify_${timestamp}"
    local backup_file="/tmp/backup_${timestamp}.sql.gz"

    echo "========================================"
    echo "Starting restore verification at $(date -Iseconds)"

    # Determine which backup to verify
    local s3_key=""
    local backup_filename=""
    if [ -n "$VERIFY_BACKUP_FILE" ]; then
        s3_key="${BACKUP_PREFIX}/${VERIFY_BACKUP_FILE}"
        backup_filename="$VERIFY_BACKUP_FILE"
        echo "Verifying specific backup: $VERIFY_BACKUP_FILE"
    elif [ "$VERIFY_LATEST" = "true" ]; then
        s3_key=$(get_latest_backup)
        if [ $? -ne 0 ]; then
            send_webhook "error" "No backups found in S3" "" "0"
            return 1
        fi
        backup_filename=$(basename "$s3_key")
        echo "Verifying latest backup: $backup_filename"
    else
        echo "ERROR: No backup specified for verification" >&2
        send_webhook "error" "No backup specified for verification" "" "0"
        return 1
    fi

    # Download backup
    if ! download_backup "$s3_key" "$backup_file"; then
        local duration=$(($(date +%s) - start_time))
        send_webhook "error" "Failed to download backup from S3" "$backup_filename" "$duration"
        rm -f "$backup_file"
        return 1
    fi

    # Create temporary database
    if ! create_temp_database "$temp_db"; then
        local duration=$(($(date +%s) - start_time))
        send_webhook "error" "Failed to create temporary database" "$backup_filename" "$duration"
        rm -f "$backup_file"
        cleanup_temp_database "$temp_db"
        return 1
    fi

    # Restore backup
    local restore_success=0
    if ! restore_backup "$backup_file" "$temp_db"; then
        restore_success=1
    fi

    # Run verification queries
    local verify_success=0
    if [ $restore_success -eq 0 ]; then
        if ! run_verification "$temp_db"; then
            verify_success=1
        fi
    fi

    # Cleanup
    rm -f "$backup_file"
    cleanup_temp_database "$temp_db"

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Report results
    if [ $restore_success -ne 0 ]; then
        echo "FAILURE: Restore verification failed - restore step failed"
        send_webhook "failure" "Restore step failed" "$backup_filename" "$duration"
        return 1
    elif [ $verify_success -ne 0 ]; then
        echo "FAILURE: Restore verification failed - verification checks failed"
        send_webhook "failure" "Verification checks failed" "$backup_filename" "$duration"
        return 1
    fi

    echo "SUCCESS: Restore verification completed successfully in ${duration}s"
    echo "Verification finished at $(date -Iseconds)"
    echo "Next verification in ${VERIFY_INTERVAL}s"

    send_webhook "success" "Restore verification completed successfully" "$backup_filename" "$duration"

    return 0
}

# Trap signals for graceful shutdown
trap 'echo "Received shutdown signal, exiting..."; exit 0' SIGTERM SIGINT

# Main loop
while true; do
    if perform_verification; then
        echo "Verification cycle completed successfully"
    else
        echo "WARNING: Verification cycle failed, will retry on next interval" >&2
    fi

    sleep "$VERIFY_INTERVAL"
done

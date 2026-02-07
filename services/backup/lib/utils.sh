#!/bin/bash
# ========================================
# Utility Functions
# ========================================

source /app/lib/logging.sh

# Retry a command with exponential backoff
# Usage: retry_with_backoff <max_attempts> <base_delay> <command> [args...]
retry_with_backoff() {
    local max_attempts="$1"
    local base_delay="$2"
    shift 2
    local command=("$@")

    local attempt=1
    local delay="$base_delay"

    while [ $attempt -le "$max_attempts" ]; do
        log_debug "Attempt $attempt/$max_attempts: ${command[*]}"

        if "${command[@]}"; then
            log_debug "Command succeeded on attempt $attempt"
            return 0
        fi

        if [ $attempt -lt "$max_attempts" ]; then
            log_warn "Attempt $attempt failed, retrying in ${delay}s..."
            sleep "$delay"

            # Exponential backoff: double the delay
            delay=$((delay * 2))
            attempt=$((attempt + 1))
        else
            log_error "Command failed after $max_attempts attempts"
            return 1
        fi
    done
}

# Send webhook notification
# Usage: send_webhook <status> <message> [extra_data]
send_webhook() {
    local status="$1"
    local message="$2"
    local extra_data="${3:-{}}"

    # Check if webhook is configured
    if [ -z "${WEBHOOK_URL:-}" ]; then
        log_debug "Webhook not configured, skipping notification"
        return 0
    fi

    # Check if we should send this notification
    if [ "$status" = "success" ] && [ "${WEBHOOK_ON_SUCCESS:-false}" != "true" ]; then
        log_debug "Webhook on success disabled, skipping"
        return 0
    fi

    if [ "$status" = "failure" ] && [ "${WEBHOOK_ON_FAILURE:-true}" != "true" ]; then
        log_debug "Webhook on failure disabled, skipping"
        return 0
    fi

    log_info "Sending webhook notification: $status"

    # Scrub secrets from message
    message=$(scrub_secrets "$message")

    # Build JSON payload
    local payload
    payload=$(jq -n \
        --arg timestamp "$(get_timestamp)" \
        --arg status "$status" \
        --arg message "$message" \
        --arg service "postgres-backup" \
        --arg host "${PGHOST:-unknown}" \
        --arg database "${PGDATABASE:-unknown}" \
        --argjson extra "$extra_data" \
        '{
            timestamp: $timestamp,
            status: $status,
            message: $message,
            service: $service,
            database: {host: $host, name: $database},
            extra: $extra
        }')

    # Send webhook with retry
    if retry_with_backoff 3 2 curl -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --max-time 10 \
        --silent \
        --show-error \
        "$WEBHOOK_URL"; then
        log_debug "Webhook sent successfully"
        return 0
    else
        log_warn "Failed to send webhook after retries"
        return 1
    fi
}

# Format bytes to human-readable size
format_bytes() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    local size="$bytes"

    while [ "$size" -gt 1024 ] && [ "$unit" -lt 4 ]; do
        size=$((size / 1024))
        unit=$((unit + 1))
    done

    echo "${size}${units[$unit]}"
}

# Get file size in bytes
get_file_size() {
    local file="$1"
    if [ -f "$file" ]; then
        stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate S3 connectivity
check_s3_connectivity() {
    log_debug "Checking S3 connectivity..."

    if aws s3 ls "s3://${S3_BUCKET}" --endpoint-url "$S3_ENDPOINT" >/dev/null 2>&1; then
        log_debug "S3 connectivity OK"
        return 0
    else
        log_error "Cannot connect to S3 bucket: s3://${S3_BUCKET}"
        return 1
    fi
}

# Validate database connectivity
check_db_connectivity() {
    log_debug "Checking database connectivity..."

    if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t 10 >/dev/null 2>&1; then
        log_debug "Database connectivity OK"
        return 0
    else
        log_error "Cannot connect to database: $PGHOST:$PGPORT/$PGDATABASE"
        return 1
    fi
}

# Export functions
export -f retry_with_backoff
export -f send_webhook
export -f format_bytes
export -f get_file_size
export -f command_exists
export -f check_s3_connectivity
export -f check_db_connectivity

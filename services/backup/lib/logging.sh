#!/bin/bash
# ========================================
# Structured Logging Library
# ========================================
# Provides consistent, structured logging with no secret exposure

# ANSI color codes (disabled in non-TTY)
if [ -t 1 ]; then
    COLOR_RED='\033[0;31m'
    COLOR_YELLOW='\033[1;33m'
    COLOR_GREEN='\033[0;32m'
    COLOR_BLUE='\033[0;34m'
    COLOR_RESET='\033[0m'
else
    COLOR_RED=''
    COLOR_YELLOW=''
    COLOR_GREEN=''
    COLOR_BLUE=''
    COLOR_RESET=''
fi

# Get ISO 8601 timestamp
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Scrub secrets from log messages
scrub_secrets() {
    local message="$1"

    # Scrub DATABASE_URL password
    message=$(echo "$message" | sed -E 's|postgresql://([^:]+):([^@]+)@|postgresql://\1:***@|g')

    # Scrub S3 credentials (basic patterns)
    message=$(echo "$message" | sed -E 's/AWS_SECRET_ACCESS_KEY=[^ ]*/AWS_SECRET_ACCESS_KEY=***/g')
    message=$(echo "$message" | sed -E 's/S3_SECRET_ACCESS_KEY=[^ ]*/S3_SECRET_ACCESS_KEY=***/g')

    # Scrub password patterns
    message=$(echo "$message" | sed -E 's/password=[^ ]*/password=***/gi')
    message=$(echo "$message" | sed -E 's/passwd=[^ ]*/passwd=***/gi')
    message=$(echo "$message" | sed -E 's/PGPASSWORD=[^ ]*/PGPASSWORD=***/g')

    echo "$message"
}

# Log with structured format: TIMESTAMP LEVEL MESSAGE
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(get_timestamp)

    # Scrub secrets
    message=$(scrub_secrets "$message")

    # Format: ISO8601 LEVEL message
    echo "${timestamp} ${level} ${message}"
}

# Convenience functions
log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARNING" "$@" >&2
}

log_error() {
    log "ERROR" "$@" >&2
}

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        log "DEBUG" "$@"
    fi
}

# Log with colored output (for terminal)
log_success() {
    local timestamp=$(get_timestamp)
    local message=$(scrub_secrets "$*")
    echo -e "${timestamp} ${COLOR_GREEN}SUCCESS${COLOR_RESET} ${message}"
}

log_failure() {
    local timestamp=$(get_timestamp)
    local message=$(scrub_secrets "$*")
    echo -e "${timestamp} ${COLOR_RED}FAILURE${COLOR_RESET} ${message}" >&2
}

# JSON structured log (optional, for machine parsing)
log_json() {
    local level="$1"
    local message="$2"
    local extra="${3:-{}}"

    message=$(scrub_secrets "$message")

    jq -n \
        --arg timestamp "$(get_timestamp)" \
        --arg level "$level" \
        --arg message "$message" \
        --argjson extra "$extra" \
        '{timestamp: $timestamp, level: $level, message: $message, extra: $extra}'
}

# Export functions
export -f get_timestamp
export -f scrub_secrets
export -f log
export -f log_info
export -f log_warn
export -f log_error
export -f log_debug
export -f log_success
export -f log_failure
export -f log_json

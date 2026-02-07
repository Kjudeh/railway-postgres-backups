#!/bin/bash
# ========================================
# Configuration Loading and Validation
# ========================================

source /app/lib/logging.sh

# Parse DATABASE_URL into PG* variables
parse_database_url() {
    local url="$1"

    # Format: postgresql://user:password@host:port/dbname
    # Also support postgres:// prefix
    if [[ "$url" =~ ^(postgresql|postgres)://([^:]+):([^@]+)@([^:]+):([^/]+)/(.+)$ ]]; then
        export PGUSER="${BASH_REMATCH[2]}"
        export PGPASSWORD="${BASH_REMATCH[3]}"
        export PGHOST="${BASH_REMATCH[4]}"
        export PGPORT="${BASH_REMATCH[5]}"
        export PGDATABASE="${BASH_REMATCH[6]}"
        return 0
    else
        log_error "Invalid DATABASE_URL format. Expected: postgresql://user:password@host:port/database"
        return 1
    fi
}

# Load and validate configuration
load_config() {
    log_info "Loading configuration..."

    # Option 1: DATABASE_URL (preferred)
    if [ -n "${DATABASE_URL:-}" ]; then
        log_debug "Using DATABASE_URL"
        if ! parse_database_url "$DATABASE_URL"; then
            return 1
        fi
    # Option 2: Individual PG* variables
    elif [ -n "${PGHOST:-}" ]; then
        log_debug "Using individual PG* variables"

        # Validate required PG variables
        local required_pg_vars=("PGHOST" "PGUSER" "PGDATABASE")
        for var in "${required_pg_vars[@]}"; do
            if [ -z "${!var:-}" ]; then
                log_error "Required variable $var is not set (when not using DATABASE_URL)"
                return 1
            fi
        done

        # Set defaults
        export PGPORT="${PGPORT:-5432}"
        export PGPASSWORD="${PGPASSWORD:-}"
    else
        log_error "Either DATABASE_URL or PGHOST must be set"
        return 1
    fi

    # Validate S3 configuration
    local required_s3_vars=("S3_ENDPOINT" "S3_BUCKET" "S3_ACCESS_KEY_ID" "S3_SECRET_ACCESS_KEY")
    for var in "${required_s3_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required variable $var is not set"
            return 1
        fi
    done

    # Set optional variables with defaults
    export BACKUP_INTERVAL="${BACKUP_INTERVAL:-3600}"
    export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
    export S3_REGION="${S3_REGION:-us-east-1}"
    export BACKUP_PREFIX="${BACKUP_PREFIX:-postgres-backups}"
    export COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"
    export BACKUP_ENCRYPTION="${BACKUP_ENCRYPTION:-false}"
    export BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY:-}"
    export WEBHOOK_URL="${WEBHOOK_URL:-}"
    export WEBHOOK_ON_SUCCESS="${WEBHOOK_ON_SUCCESS:-false}"
    export WEBHOOK_ON_FAILURE="${WEBHOOK_ON_FAILURE:-true}"
    export RETRY_ATTEMPTS="${RETRY_ATTEMPTS:-3}"
    export RETRY_DELAY="${RETRY_DELAY:-5}"

    # Configure AWS CLI
    export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY"
    export AWS_DEFAULT_REGION="$S3_REGION"

    # Validate configuration values
    if ! [[ "$BACKUP_INTERVAL" =~ ^[0-9]+$ ]] || [ "$BACKUP_INTERVAL" -lt 60 ]; then
        log_error "BACKUP_INTERVAL must be a number >= 60 seconds"
        return 1
    fi

    if ! [[ "$BACKUP_RETENTION_DAYS" =~ ^[0-9]+$ ]] || [ "$BACKUP_RETENTION_DAYS" -lt 1 ]; then
        log_error "BACKUP_RETENTION_DAYS must be a number >= 1"
        return 1
    fi

    if ! [[ "$COMPRESSION_LEVEL" =~ ^[1-9]$ ]]; then
        log_error "COMPRESSION_LEVEL must be between 1 and 9"
        return 1
    fi

    if [ "$BACKUP_ENCRYPTION" = "true" ] && [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
        log_error "BACKUP_ENCRYPTION_KEY must be set when BACKUP_ENCRYPTION=true"
        return 1
    fi

    log_info "Configuration loaded successfully"
    log_debug "Database: $PGHOST:$PGPORT/$PGDATABASE"
    log_debug "S3 Endpoint: $S3_ENDPOINT"
    log_debug "S3 Bucket: $S3_BUCKET"
    log_debug "Backup Interval: ${BACKUP_INTERVAL}s"
    log_debug "Retention: $BACKUP_RETENTION_DAYS days"
    log_debug "Compression Level: $COMPRESSION_LEVEL"
    log_debug "Encryption: $BACKUP_ENCRYPTION"

    return 0
}

# Export functions
export -f parse_database_url
export -f load_config

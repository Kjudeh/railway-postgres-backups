#!/bin/bash
# ========================================
# Health Check for Backup Service
# ========================================
# Verifies database and S3 connectivity

set -euo pipefail

# Load libraries
source /app/lib/logging.sh 2>/dev/null || {
    echo "ERROR: Cannot load logging library"
    exit 1
}

source /app/lib/config.sh 2>/dev/null || {
    log_error "Cannot load config library"
    exit 1
}

source /app/lib/utils.sh 2>/dev/null || {
    log_error "Cannot load utils library"
    exit 1
}

# Main health check
main() {
    local errors=0

    # Load configuration (without strict validation)
    if [ -n "${DATABASE_URL:-}" ]; then
        parse_database_url "$DATABASE_URL" || errors=$((errors + 1))
    elif [ -n "${PGHOST:-}" ]; then
        export PGHOST PGUSER PGDATABASE
        export PGPORT="${PGPORT:-5432}"
        export PGPASSWORD="${PGPASSWORD:-}"
    else
        log_error "DATABASE_URL or PGHOST not set"
        exit 1
    fi

    # Check S3 variables
    if [ -z "${S3_ENDPOINT:-}" ] || [ -z "${S3_BUCKET:-}" ]; then
        log_error "S3_ENDPOINT or S3_BUCKET not set"
        exit 1
    fi

    # Configure AWS CLI
    export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID:-}"
    export AWS_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY:-}"
    export AWS_DEFAULT_REGION="${S3_REGION:-us-east-1}"

    # Check database connectivity
    if ! check_db_connectivity; then
        log_error "Database health check failed"
        errors=$((errors + 1))
    fi

    # Check S3 connectivity
    if ! check_s3_connectivity; then
        log_error "S3 health check failed"
        errors=$((errors + 1))
    fi

    if [ $errors -gt 0 ]; then
        log_error "Health check failed: $errors error(s)"
        exit 1
    fi

    log_info "Health check passed"
    exit 0
}

main "$@"

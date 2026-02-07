#!/bin/bash
# ========================================
# PostgreSQL Backup Service - Entrypoint
# ========================================
# Main runner that coordinates the backup service

set -euo pipefail

# Load libraries
source /app/lib/logging.sh
source /app/lib/config.sh
source /app/lib/utils.sh

# Trap signals for graceful shutdown
SHUTDOWN=false

handle_signal() {
    log_info "Received shutdown signal (SIGTERM/SIGINT)"
    SHUTDOWN=true
}

trap handle_signal SIGTERM SIGINT

# Main entrypoint
main() {
    local mode="${1:-backup}"

    log_info "========================================  "
    log_info "PostgreSQL Backup Service Starting"
    log_info "========================================"

    # Load and validate configuration
    if ! load_config; then
        log_error "Configuration validation failed"
        exit 1
    fi

    # Check connectivity
    log_info "Performing initial connectivity checks..."

    if ! check_db_connectivity; then
        log_warn "Database connectivity check failed (will retry during backup)"
    fi

    if ! check_s3_connectivity; then
        log_warn "S3 connectivity check failed (will retry during backup)"
    fi

    # Run based on mode
    case "$mode" in
        backup)
            run_backup_loop
            ;;
        once)
            run_backup_once
            ;;
        healthcheck)
            run_healthcheck
            ;;
        *)
            log_error "Unknown mode: $mode"
            log_error "Usage: $0 [backup|once|healthcheck]"
            exit 1
            ;;
    esac
}

# Run continuous backup loop
run_backup_loop() {
    log_info "Starting continuous backup mode"
    log_info "Backup interval: ${BACKUP_INTERVAL}s"
    log_info "Next backup will run immediately"

    local iteration=1

    while [ "$SHUTDOWN" = "false" ]; do
        log_info "========================================"
        log_info "Backup Iteration #$iteration"
        log_info "========================================"

        # Run backup script
        if /app/backup.sh; then
            log_success "Backup iteration #$iteration completed successfully"
            send_webhook "success" "Backup iteration #$iteration completed successfully"
        else
            log_failure "Backup iteration #$iteration failed"
            send_webhook "failure" "Backup iteration #$iteration failed"
        fi

        # Calculate next backup time
        local next_backup=$(date -d "@$(($(date +%s) + BACKUP_INTERVAL))" -Iseconds 2>/dev/null || \
                           date -v+${BACKUP_INTERVAL}S -Iseconds 2>/dev/null)

        log_info "Next backup scheduled for: $next_backup (in ${BACKUP_INTERVAL}s)"

        # Sleep in chunks to respond to shutdown signal
        local remaining=$BACKUP_INTERVAL
        while [ $remaining -gt 0 ] && [ "$SHUTDOWN" = "false" ]; do
            local sleep_time=10
            if [ $remaining -lt 10 ]; then
                sleep_time=$remaining
            fi
            sleep $sleep_time
            remaining=$((remaining - sleep_time))
        done

        iteration=$((iteration + 1))
    done

    log_info "Backup loop shutting down gracefully"
}

# Run single backup
run_backup_once() {
    log_info "Starting one-time backup mode"

    if /app/backup.sh; then
        log_success "One-time backup completed successfully"
        exit 0
    else
        log_failure "One-time backup failed"
        exit 1
    fi
}

# Run health check
run_healthcheck() {
    /app/healthcheck.sh
    exit $?
}

# Start main function
main "$@"

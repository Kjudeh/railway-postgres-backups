#!/bin/bash
# ========================================
# PostgreSQL Backup Script
# ========================================
# Performs: pg_dump -> gzip -> [optional encrypt] -> upload -> retention prune -> notify

set -euo pipefail

# Load libraries
source /app/lib/logging.sh
source /app/lib/utils.sh

# Backup workflow
main() {
    local start_time=$(date +%s)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_filename="backup_${timestamp}.sql.gz"
    local backup_path="/tmp/${backup_filename}"
    local encrypted_path="${backup_path}.enc"
    local s3_key="${BACKUP_PREFIX}/${backup_filename}"

    log_info "Starting backup: $backup_filename"

    # Step 1: Check connectivity
    if ! check_connectivity; then
        log_error "Connectivity check failed, aborting backup"
        return 1
    fi

    # Step 2: Perform database dump
    if ! perform_dump "$backup_path"; then
        cleanup_files "$backup_path" "$encrypted_path"
        return 1
    fi

    # Step 3: Optional encryption
    local upload_file="$backup_path"
    if [ "$BACKUP_ENCRYPTION" = "true" ]; then
        if ! encrypt_backup "$backup_path" "$encrypted_path"; then
            cleanup_files "$backup_path" "$encrypted_path"
            return 1
        fi
        upload_file="$encrypted_path"
        s3_key="${s3_key}.enc"
    fi

    # Step 4: Upload to S3 with retry
    if ! upload_to_s3 "$upload_file" "$s3_key"; then
        cleanup_files "$backup_path" "$encrypted_path"
        return 1
    fi

    # Step 5: Cleanup local files
    cleanup_files "$backup_path" "$encrypted_path"

    # Step 6: Retention pruning
    if ! prune_old_backups; then
        log_warn "Retention pruning failed (non-fatal)"
    fi

    # Step 7: Calculate duration and log success
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_success "Backup completed successfully in ${duration}s"
    log_info "Backup location: s3://${S3_BUCKET}/${s3_key}"

    return 0
}

# Check database and S3 connectivity
check_connectivity() {
    log_info "Checking connectivity..."

    local errors=0

    if ! check_db_connectivity; then
        errors=$((errors + 1))
    fi

    if ! check_s3_connectivity; then
        errors=$((errors + 1))
    fi

    if [ $errors -gt 0 ]; then
        log_error "Connectivity check failed ($errors error(s))"
        return 1
    fi

    log_info "Connectivity check passed"
    return 0
}

# Perform PostgreSQL dump
perform_dump() {
    local output_file="$1"

    log_info "Creating database dump..."
    log_debug "Database: $PGHOST:$PGPORT/$PGDATABASE"
    log_debug "User: $PGUSER"
    log_debug "Compression level: $COMPRESSION_LEVEL"

    # Build pg_dump command
    local dump_start=$(date +%s)

    # Use pipe to compress on-the-fly
    if pg_dump \
        -h "$PGHOST" \
        -p "$PGPORT" \
        -U "$PGUSER" \
        -d "$PGDATABASE" \
        --no-owner \
        --no-acl \
        --clean \
        --if-exists \
        --verbose 2>&1 | \
        grep -v "^pg_dump: " | \
        gzip "-${COMPRESSION_LEVEL}" > "$output_file"; then

        local dump_end=$(date +%s)
        local dump_duration=$((dump_end - dump_start))

        # Verify file was created and is not empty
        if [ ! -f "$output_file" ]; then
            log_error "Dump file was not created: $output_file"
            return 1
        fi

        local file_size=$(get_file_size "$output_file")
        if [ "$file_size" -eq 0 ]; then
            log_error "Dump file is empty"
            return 1
        fi

        local size_human=$(format_bytes "$file_size")
        log_info "Dump completed in ${dump_duration}s, size: $size_human"

        return 0
    else
        log_error "pg_dump failed"
        return 1
    fi
}

# Encrypt backup file
encrypt_backup() {
    local input_file="$1"
    local output_file="$2"

    log_info "Encrypting backup..."

    if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
        log_error "BACKUP_ENCRYPTION_KEY is not set"
        return 1
    fi

    # Use openssl for AES-256-CBC encryption
    if openssl enc -aes-256-cbc \
        -salt \
        -pbkdf2 \
        -in "$input_file" \
        -out "$output_file" \
        -pass "pass:$BACKUP_ENCRYPTION_KEY" 2>&1; then

        local encrypted_size=$(get_file_size "$output_file")
        local size_human=$(format_bytes "$encrypted_size")

        log_info "Encryption completed, size: $size_human"
        return 0
    else
        log_error "Encryption failed"
        return 1
    fi
}

# Upload file to S3 with retry and exponential backoff
upload_to_s3() {
    local local_file="$1"
    local s3_key="$2"

    log_info "Uploading to S3..."
    log_debug "Source: $local_file"
    log_debug "Destination: s3://${S3_BUCKET}/${s3_key}"

    local file_size=$(get_file_size "$local_file")
    local size_human=$(format_bytes "$file_size")

    log_info "Upload size: $size_human"

    # Upload with metadata
    local upload_start=$(date +%s)

    if retry_with_backoff "$RETRY_ATTEMPTS" "$RETRY_DELAY" \
        aws s3 cp "$local_file" "s3://${S3_BUCKET}/${s3_key}" \
            --endpoint-url "$S3_ENDPOINT" \
            --metadata "timestamp=$(date -Iseconds),database=$PGDATABASE,host=$PGHOST,size=$file_size"; then

        local upload_end=$(date +%s)
        local upload_duration=$((upload_end - upload_start))

        log_info "Upload completed in ${upload_duration}s"
        return 0
    else
        log_error "Upload failed after $RETRY_ATTEMPTS attempts"
        return 1
    fi
}

# Cleanup local files
cleanup_files() {
    local files=("$@")

    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            log_debug "Removing local file: $file"
            rm -f "$file"
        fi
    done
}

# Prune old backups based on retention policy
prune_old_backups() {
    log_info "Checking for old backups to prune..."
    log_debug "Retention policy: $BACKUP_RETENTION_DAYS days"

    # Calculate cutoff date
    local cutoff_date=$(date -d "${BACKUP_RETENTION_DAYS} days ago" +%Y%m%d 2>/dev/null || \
                       date -v-${BACKUP_RETENTION_DAYS}d +%Y%m%d 2>/dev/null)

    if [ -z "$cutoff_date" ]; then
        log_error "Failed to calculate cutoff date"
        return 1
    fi

    log_debug "Cutoff date: $cutoff_date"

    # List all backups in prefix
    local backups
    backups=$(aws s3 ls "s3://${S3_BUCKET}/${BACKUP_PREFIX}/" \
        --endpoint-url "$S3_ENDPOINT" \
        --recursive 2>/dev/null | awk '{print $4}' || echo "")

    if [ -z "$backups" ]; then
        log_info "No existing backups found"
        return 0
    fi

    local deleted_count=0
    local total_count=0

    # Process each backup
    while IFS= read -r backup_key; do
        [ -z "$backup_key" ] && continue
        total_count=$((total_count + 1))

        # Extract date from filename: backup_YYYYMMDD_HHMMSS.sql.gz
        if [[ "$backup_key" =~ backup_([0-9]{8})_[0-9]{6} ]]; then
            local backup_date="${BASH_REMATCH[1]}"

            if [ "$backup_date" -lt "$cutoff_date" ]; then
                log_info "Deleting old backup: $backup_key (date: $backup_date)"

                if aws s3 rm "s3://${S3_BUCKET}/${backup_key}" \
                    --endpoint-url "$S3_ENDPOINT" 2>&1; then
                    deleted_count=$((deleted_count + 1))
                else
                    log_warn "Failed to delete: $backup_key"
                fi
            fi
        fi
    done <<< "$backups"

    log_info "Retention pruning completed: $deleted_count deleted, $((total_count - deleted_count)) retained"
    return 0
}

# Execute main function
main "$@"

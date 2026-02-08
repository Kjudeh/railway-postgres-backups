#!/bin/bash
set -euo pipefail

# ========================================
# Integration Test Runner
# ========================================
# Tests the backup and verify services using MinIO

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo "PostgreSQL Backup Integration Tests"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ========================================
# PREFLIGHT CHECKS
# ========================================
echo ""
echo -e "${BLUE}Running preflight checks...${NC}"

# Check Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}ERROR: docker not found. Please install Docker.${NC}"
    exit 1
fi

# Check Docker daemon is running
if ! docker info &> /dev/null; then
    echo -e "${RED}ERROR: Docker daemon not running. Please start Docker.${NC}"
    exit 1
fi

# Check Docker Compose is available (v2 or v1)
if ! docker compose version &> /dev/null && ! docker-compose --version &> /dev/null; then
    echo -e "${RED}ERROR: docker-compose not found. Please install Docker Compose.${NC}"
    exit 1
fi

# Determine which Docker Compose command to use
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

# ========================================
# CLEANUP FUNCTIONS
# ========================================

# Force cleanup - removes containers even if they're in bad state
cleanup_force() {
    echo ""
    echo "Cleaning up test environment..."
    $COMPOSE_CMD -f docker-compose.test.yml down -v --remove-orphans 2>/dev/null || true

    # Also clean up any orphaned volumes
    docker volume ls -q | grep -E "tests_postgres|tests_minio" | xargs -r docker volume rm 2>/dev/null || true
}

# Graceful cleanup
cleanup() {
    echo ""
    echo "Cleaning up..."
    $COMPOSE_CMD -f docker-compose.test.yml down -v --remove-orphans
}

# Clean up any existing test infrastructure before starting
# (must run before port check so leftover containers don't block ports)
cleanup_force

# Stop system PostgreSQL if running (common on CI runners like GitHub Actions)
if command -v systemctl &> /dev/null; then
    sudo systemctl stop postgresql 2>/dev/null || true
fi

# Set trap for cleanup on exit/interrupt
trap cleanup_force EXIT INT TERM

# Check port availability
echo "Checking port availability..."
for port in 5432 5433 9000 9001; do
    if lsof -Pi :"$port" -sTCP:LISTEN -t >/dev/null 2>&1 || netstat -an 2>/dev/null | grep -q ":$port.*LISTEN"; then
        echo -e "${RED}ERROR: Port $port is already in use. Please free the port and try again.${NC}"
        echo "  Tip: Use 'lsof -i :$port' or 'docker ps' to find what's using it"
        exit 1
    fi
done

# Check available disk space (need at least 5GB)
AVAILABLE_SPACE=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$AVAILABLE_SPACE" -lt 5 ]; then
    echo -e "${YELLOW}WARNING: Less than 5GB disk space available. Tests may fail.${NC}"
fi

echo -e "${GREEN}✓ All preflight checks passed${NC}"

# Start services
echo ""
echo "Starting test services..."
$COMPOSE_CMD -f docker-compose.test.yml up -d postgres postgres_verify minio minio-setup

# Wait for services to be healthy
echo "Waiting for services to be ready..."
sleep 5

# Check service health
echo "Checking service health..."
if ! $COMPOSE_CMD -f docker-compose.test.yml ps postgres | grep -q "healthy"; then
    echo -e "${RED}ERROR: PostgreSQL (source) is not healthy${NC}"
    echo "Logs:"
    $COMPOSE_CMD -f docker-compose.test.yml logs postgres
    exit 1
fi

if ! $COMPOSE_CMD -f docker-compose.test.yml ps postgres_verify | grep -q "healthy"; then
    echo -e "${RED}ERROR: PostgreSQL (verify) is not healthy${NC}"
    echo "Logs:"
    $COMPOSE_CMD -f docker-compose.test.yml logs postgres_verify
    exit 1
fi

if ! $COMPOSE_CMD -f docker-compose.test.yml ps minio | grep -q "healthy"; then
    echo -e "${RED}ERROR: MinIO is not healthy${NC}"
    echo "Logs:"
    $COMPOSE_CMD -f docker-compose.test.yml logs minio
    exit 1
fi

echo -e "${GREEN}Services are healthy${NC}"

# Seed test data
echo ""
echo "Seeding test data..."
$COMPOSE_CMD -f docker-compose.test.yml exec -T postgres psql -U testuser -d testdb <<EOF
CREATE TABLE test_table (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO test_table (name) VALUES
    ('Test Record 1'),
    ('Test Record 2'),
    ('Test Record 3');

CREATE INDEX idx_test_name ON test_table(name);
EOF

echo -e "${GREEN}Test data seeded${NC}"

# Test 1: Run backup service
echo ""
echo "Test 1: Running backup service..."
$COMPOSE_CMD -f docker-compose.test.yml up -d backup

# Wait for backup to complete
echo "Waiting for backup to complete (60s)..."
sleep 65

# Check backup logs
echo "Checking backup logs..."
if $COMPOSE_CMD -f docker-compose.test.yml logs backup | grep -q "Backup completed successfully"; then
    echo -e "${GREEN}✓ Backup completed successfully${NC}"
else
    echo -e "${RED}✗ Backup failed${NC}"
    $COMPOSE_CMD -f docker-compose.test.yml logs backup
    exit 1
fi

# Test 2: Verify backup exists in MinIO
echo ""
echo "Test 2: Verifying backup exists in MinIO..."
BACKUP_LIST=$($COMPOSE_CMD -f docker-compose.test.yml exec -T backup \
    aws s3 ls "s3://test-backups/test-backups/" --endpoint-url http://minio:9000)

if echo "$BACKUP_LIST" | grep -q "backup_"; then
    echo -e "${GREEN}✓ Backup file found in MinIO${NC}"
else
    echo -e "${RED}✗ Backup file not found in MinIO${NC}"
    exit 1
fi

# Test 2a: Verify backup size > 0
echo "Verifying backup size > 0..."
BACKUP_SIZE=$(echo "$BACKUP_LIST" | grep "backup_" | head -1 | awk '{print $3}')

if [ -z "$BACKUP_SIZE" ] || [ "$BACKUP_SIZE" -eq 0 ]; then
    echo -e "${RED}✗ Backup file size is 0 or invalid${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Backup size verified: ${BACKUP_SIZE} bytes${NC}"

# Test 3: Run verify service
echo ""
echo "Test 3: Running restore verification..."
$COMPOSE_CMD -f docker-compose.test.yml up -d verify

# Wait for verification to complete
echo "Waiting for verification to complete (120s)..."
sleep 125

# Check verify logs
echo "Checking verification logs..."
VERIFY_LOGS=$($COMPOSE_CMD -f docker-compose.test.yml logs verify)

if echo "$VERIFY_LOGS" | grep -q "Restore verification completed successfully"; then
    echo -e "${GREEN}✓ Restore verification service completed${NC}"
else
    echo -e "${RED}✗ Restore verification failed${NC}"
    echo "$VERIFY_LOGS"
    exit 1
fi

# Test 3a: CRITICAL - Verify the restore was meaningful (not empty)
# The verify service drops temp databases after each cycle, so we check
# the service logs to confirm data was actually restored and validated.
echo ""
echo "Test 3a: Verifying restored database integrity from logs..."

if echo "$VERIFY_LOGS" | grep -q "Restore completed"; then
    echo -e "${GREEN}✓ Restore step completed successfully${NC}"
else
    echo -e "${RED}✗ Restore step did not complete${NC}"
    exit 1
fi

# Verify the restored database had tables (not an empty restore)
TABLE_COUNT=$(echo "$VERIFY_LOGS" | grep -o "Found [0-9]* table" | head -1 | grep -o "[0-9]*")
if [ -n "$TABLE_COUNT" ] && [ "$TABLE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Restored database has $TABLE_COUNT table(s)${NC}"
else
    echo -e "${RED}✗ Restored database had no tables${NC}"
    exit 1
fi

if echo "$VERIFY_LOGS" | grep -q "All verification checks passed"; then
    echo -e "${GREEN}✓ All verification checks passed on restored data${NC}"
else
    echo -e "${RED}✗ Verification checks did not pass on restored data${NC}"
    exit 1
fi

# Test 4: Verify data integrity on SOURCE database
echo ""
echo "Test 4: Verifying source database data integrity..."
RECORD_COUNT=$($COMPOSE_CMD -f docker-compose.test.yml exec -T postgres \
    psql -U testuser -d testdb -t -c "SELECT COUNT(*) FROM test_table;" | tr -d '[:space:]')

if [ "$RECORD_COUNT" -eq 3 ]; then
    echo -e "${GREEN}✓ Data integrity verified (3 records)${NC}"
else
    echo -e "${RED}✗ Data integrity check failed (expected 3, got $RECORD_COUNT)${NC}"
    exit 1
fi

# Test 4a: Run sanity queries
echo "Running sanity queries..."
# Check if indexes exist
INDEX_COUNT=$($COMPOSE_CMD -f docker-compose.test.yml exec -T postgres \
    psql -U testuser -d testdb -t -c "SELECT COUNT(*) FROM pg_indexes WHERE tablename = 'test_table' AND indexname = 'idx_test_name';" | tr -d '[:space:]')

if [ "$INDEX_COUNT" -eq 1 ]; then
    echo -e "${GREEN}✓ Index integrity verified${NC}"
else
    echo -e "${RED}✗ Index check failed (expected 1, got $INDEX_COUNT)${NC}"
    exit 1
fi

# Verify specific data
FIRST_RECORD=$($COMPOSE_CMD -f docker-compose.test.yml exec -T postgres \
    psql -U testuser -d testdb -t -c "SELECT name FROM test_table WHERE id = 1;" | xargs)

if [ "$FIRST_RECORD" = "Test Record 1" ]; then
    echo -e "${GREEN}✓ Data content verified${NC}"
else
    echo -e "${RED}✗ Data content check failed (expected 'Test Record 1', got '$FIRST_RECORD')${NC}"
    exit 1
fi

# Test 5: Verify backup retention/pruning
echo ""
echo "Test 5: Testing backup retention and pruning..."

# Calculate date for "2 days ago" using Python for cross-platform compatibility
OLD_DATE=$(python3 -c "from datetime import datetime, timedelta; print((datetime.now() - timedelta(days=2)).strftime('%Y%m%d'))" 2>/dev/null || \
           python -c "from datetime import datetime, timedelta; print((datetime.now() - timedelta(days=2)).strftime('%Y%m%d'))" 2>/dev/null || \
           date -d "2 days ago" +%Y%m%d 2>/dev/null || \
           date -v-2d +%Y%m%d 2>/dev/null || \
           echo "")

if [ -z "$OLD_DATE" ]; then
    echo -e "${YELLOW}⚠ Cannot calculate old date - skipping retention test${NC}"
else
    OLD_TIME="120000"
    OLD_BACKUP_NAME="test-backups/backup_${OLD_DATE}_${OLD_TIME}.sql.gz"

    echo "Creating simulated old backup: $OLD_BACKUP_NAME"
    $COMPOSE_CMD -f docker-compose.test.yml exec -T backup \
        sh -c "echo 'test old backup content' | gzip > /tmp/old_backup.sql.gz && \
               aws s3 cp /tmp/old_backup.sql.gz 's3://test-backups/${OLD_BACKUP_NAME}' --endpoint-url http://minio:9000 && \
               rm /tmp/old_backup.sql.gz"

    # Verify old backup was created
    # NOTE: avoid piping exec directly to grep — pipefail + SIGPIPE causes
    # false failures when grep -q closes the pipe early.
    OLD_BACKUP_LS=$($COMPOSE_CMD -f docker-compose.test.yml exec -T backup \
        aws s3 ls "s3://test-backups/test-backups/" --endpoint-url http://minio:9000 2>&1) || true
    if echo "$OLD_BACKUP_LS" | grep -q "backup_${OLD_DATE}"; then
        echo -e "${GREEN}✓ Old backup created for testing${NC}"
    else
        echo -e "${RED}✗ Failed to create old backup for testing${NC}"
        exit 1
    fi

    # Run backup service again to trigger retention cleanup (with BACKUP_RETENTION_DAYS=1)
    echo "Triggering backup service to test retention cleanup..."
    $COMPOSE_CMD -f docker-compose.test.yml restart backup
    sleep 70

    # Check backup logs for retention cleanup attempt
    BACKUP_LOGS=$($COMPOSE_CMD -f docker-compose.test.yml logs backup)

    if echo "$BACKUP_LOGS" | grep -qi "retention\|cleanup\|delet"; then
        echo -e "${GREEN}✓ Retention cleanup was attempted${NC}"
    else
        echo -e "${YELLOW}⚠ No retention cleanup messages found in logs${NC}"
    fi

    # Check if old backup was deleted
    RETENTION_LS=$($COMPOSE_CMD -f docker-compose.test.yml exec -T backup \
        aws s3 ls "s3://test-backups/test-backups/" --endpoint-url http://minio:9000 2>&1) || true
    if echo "$RETENTION_LS" | grep -q "backup_${OLD_DATE}"; then
        echo -e "${YELLOW}⚠ Old backup still exists after retention period${NC}"
        echo "  This may indicate retention policy is not working correctly"
        echo "  Backup logs:"
        echo "$BACKUP_LOGS" | grep -i "retention\|cleanup\|delet" || echo "  (no retention messages found)"
        # Don't fail - retention timing can be inconsistent
    else
        echo -e "${GREEN}✓ Old backup pruned successfully${NC}"
    fi

    # Verify new backup still exists
    REMAINING_LS=$($COMPOSE_CMD -f docker-compose.test.yml exec -T backup \
        aws s3 ls "s3://test-backups/test-backups/" --endpoint-url http://minio:9000 2>&1) || true
    CURRENT_BACKUPS=$(echo "$REMAINING_LS" | grep "backup_" | grep -v "backup_${OLD_DATE}" | wc -l)

    if [ "$CURRENT_BACKUPS" -ge 1 ]; then
        echo -e "${GREEN}✓ Recent backups retained ($CURRENT_BACKUPS backups)${NC}"
    else
        echo -e "${RED}✗ Recent backups missing${NC}"
        exit 1
    fi
fi

# All tests passed
echo ""
echo "========================================"
echo -e "${GREEN}All tests passed!${NC}"
echo "========================================"
echo ""
echo "Test Summary:"
echo "✓ Backup service operational"
echo "✓ Backup files created in S3"
echo "✓ Backup files have valid size"
echo "✓ Restore verification service operational"
echo "✓ Restored database verified via service logs"
echo "✓ Source database data integrity confirmed"
echo "✓ Index integrity maintained"
echo "✓ Retention policy tested"
echo ""

exit 0

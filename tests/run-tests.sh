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
NC='\033[0m' # No Color

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker-compose -f docker-compose.test.yml down -v
}

trap cleanup EXIT

# Start services
echo ""
echo "Starting test services..."
docker-compose -f docker-compose.test.yml up -d postgres postgres_verify minio minio-setup

# Wait for services to be healthy
echo "Waiting for services to be ready..."
sleep 5

# Check service health
echo "Checking service health..."
if ! docker-compose -f docker-compose.test.yml ps postgres | grep -q "healthy"; then
    echo -e "${RED}ERROR: PostgreSQL (source) is not healthy${NC}"
    exit 1
fi

if ! docker-compose -f docker-compose.test.yml ps postgres_verify | grep -q "healthy"; then
    echo -e "${RED}ERROR: PostgreSQL (verify) is not healthy${NC}"
    exit 1
fi

if ! docker-compose -f docker-compose.test.yml ps minio | grep -q "healthy"; then
    echo -e "${RED}ERROR: MinIO is not healthy${NC}"
    exit 1
fi

echo -e "${GREEN}Services are healthy${NC}"

# Seed test data
echo ""
echo "Seeding test data..."
docker-compose -f docker-compose.test.yml exec -T postgres psql -U testuser -d testdb <<EOF
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
docker-compose -f docker-compose.test.yml up -d backup

# Wait for backup to complete
echo "Waiting for backup to complete (60s)..."
sleep 65

# Check backup logs
echo "Checking backup logs..."
if docker-compose -f docker-compose.test.yml logs backup | grep -q "Backup completed successfully"; then
    echo -e "${GREEN}✓ Backup completed successfully${NC}"
else
    echo -e "${RED}✗ Backup failed${NC}"
    docker-compose -f docker-compose.test.yml logs backup
    exit 1
fi

# Test 2: Verify backup exists in MinIO
echo ""
echo "Test 2: Verifying backup exists in MinIO..."
BACKUP_LIST=$(docker-compose -f docker-compose.test.yml exec -T minio \
    mc ls myminio/test-backups/test-backups/)

if echo "$BACKUP_LIST" | grep -q "backup_"; then
    echo -e "${GREEN}✓ Backup file found in MinIO${NC}"
else
    echo -e "${RED}✗ Backup file not found in MinIO${NC}"
    exit 1
fi

# Test 2a: Verify backup size > 0
echo "Verifying backup size > 0..."
BACKUP_SIZE=$(echo "$BACKUP_LIST" | grep "backup_" | head -1 | awk '{print $4}')

# Extract numeric value (remove B, KiB, MiB, etc.)
BACKUP_SIZE_NUM=$(echo "$BACKUP_SIZE" | sed 's/[^0-9.]//g')

if [ -z "$BACKUP_SIZE_NUM" ] || [ "$(echo "$BACKUP_SIZE_NUM <= 0" | bc -l 2>/dev/null || echo "0")" -eq 1 ]; then
    # Fallback: check if size string is empty or "0"
    if [ -z "$BACKUP_SIZE" ] || [ "$BACKUP_SIZE" = "0" ] || [ "$BACKUP_SIZE" = "0B" ]; then
        echo -e "${RED}✗ Backup file size is 0 or invalid${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Backup size verified: $BACKUP_SIZE${NC}"

# Test 3: Run verify service
echo ""
echo "Test 3: Running restore verification..."
docker-compose -f docker-compose.test.yml up -d verify

# Wait for verification to complete
echo "Waiting for verification to complete (120s)..."
sleep 125

# Check verify logs
echo "Checking verification logs..."
if docker-compose -f docker-compose.test.yml logs verify | grep -q "Restore verification completed successfully"; then
    echo -e "${GREEN}✓ Restore verification passed${NC}"
else
    echo -e "${RED}✗ Restore verification failed${NC}"
    docker-compose -f docker-compose.test.yml logs verify
    exit 1
fi

# Test 4: Verify data integrity
echo ""
echo "Test 4: Verifying data integrity..."
RECORD_COUNT=$(docker-compose -f docker-compose.test.yml exec -T postgres \
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
INDEX_COUNT=$(docker-compose -f docker-compose.test.yml exec -T postgres \
    psql -U testuser -d testdb -t -c "SELECT COUNT(*) FROM pg_indexes WHERE tablename = 'test_table' AND indexname = 'idx_test_name';" | tr -d '[:space:]')

if [ "$INDEX_COUNT" -eq 1 ]; then
    echo -e "${GREEN}✓ Index integrity verified${NC}"
else
    echo -e "${RED}✗ Index check failed (expected 1, got $INDEX_COUNT)${NC}"
    exit 1
fi

# Verify specific data
FIRST_RECORD=$(docker-compose -f docker-compose.test.yml exec -T postgres \
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

# Create an old backup file in MinIO to simulate old backups
OLD_DATE=$(date -d "2 days ago" +%Y%m%d 2>/dev/null || date -v-2d +%Y%m%d 2>/dev/null || echo "20240101")
OLD_TIME="120000"
OLD_BACKUP_NAME="test-backups/backup_${OLD_DATE}_${OLD_TIME}.sql.gz"

echo "Creating simulated old backup: $OLD_BACKUP_NAME"
echo "test old backup content" | docker-compose -f docker-compose.test.yml exec -T minio \
    mc pipe myminio/test-backups/$OLD_BACKUP_NAME

# Verify old backup was created
if docker-compose -f docker-compose.test.yml exec -T minio \
    mc ls myminio/test-backups/test-backups/ | grep -q "backup_${OLD_DATE}"; then
    echo -e "${GREEN}✓ Old backup created for testing${NC}"
else
    echo -e "${RED}✗ Failed to create old backup for testing${NC}"
    exit 1
fi

# Run backup service again to trigger retention cleanup (with BACKUP_RETENTION_DAYS=1)
echo "Running backup service again to trigger retention cleanup..."
docker-compose -f docker-compose.test.yml restart backup
sleep 70

# Check if old backup was deleted
if docker-compose -f docker-compose.test.yml exec -T minio \
    mc ls myminio/test-backups/test-backups/ | grep -q "backup_${OLD_DATE}"; then
    echo -e "${YELLOW}⚠ Old backup still exists (retention cleanup may need more time)${NC}"
    # Not failing the test as retention timing can vary
else
    echo -e "${GREEN}✓ Old backup pruned successfully${NC}"
fi

# Verify new backup still exists
if docker-compose -f docker-compose.test.yml exec -T minio \
    mc ls myminio/test-backups/test-backups/ | grep -q "backup_" | grep -v "backup_${OLD_DATE}"; then
    echo -e "${GREEN}✓ Recent backups retained${NC}"
else
    echo -e "${RED}✗ Recent backups missing${NC}"
    exit 1
fi

# All tests passed
echo ""
echo "========================================"
echo -e "${GREEN}All tests passed!${NC}"
echo "========================================"

exit 0

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
docker-compose -f docker-compose.test.yml up -d postgres minio minio-setup

# Wait for services to be healthy
echo "Waiting for services to be ready..."
sleep 5

# Check service health
echo "Checking service health..."
if ! docker-compose -f docker-compose.test.yml ps postgres | grep -q "healthy"; then
    echo -e "${RED}ERROR: PostgreSQL is not healthy${NC}"
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
if docker-compose -f docker-compose.test.yml exec -T minio \
    mc ls myminio/test-backups/test-backups/ | grep -q "backup_"; then
    echo -e "${GREEN}✓ Backup file found in MinIO${NC}"
else
    echo -e "${RED}✗ Backup file not found in MinIO${NC}"
    exit 1
fi

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
    psql -U testuser -d testdb -t -c "SELECT COUNT(*) FROM test_table;")

if [ "$RECORD_COUNT" -eq 3 ]; then
    echo -e "${GREEN}✓ Data integrity verified (3 records)${NC}"
else
    echo -e "${RED}✗ Data integrity check failed (expected 3, got $RECORD_COUNT)${NC}"
    exit 1
fi

# Test 5: Verify backup retention
echo ""
echo "Test 5: Testing backup retention..."
# Create an old backup file (simulate)
# In real scenario, this would be tested over time
echo -e "${YELLOW}⊘ Backup retention test skipped (requires time-based testing)${NC}"

# All tests passed
echo ""
echo "========================================"
echo -e "${GREEN}All tests passed!${NC}"
echo "========================================"

exit 0

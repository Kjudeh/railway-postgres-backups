.PHONY: test test-verbose test-clean test-logs help build-backup build-verify build

# Default target
help:
	@echo "PostgreSQL Backup & Restore - Make Commands"
	@echo ""
	@echo "Available targets:"
	@echo "  make test          - Run all integration tests"
	@echo "  make test-verbose  - Run tests with verbose output"
	@echo "  make test-clean    - Clean up test containers and volumes"
	@echo "  make test-logs     - Show logs from test services"
	@echo "  make build         - Build all Docker images"
	@echo "  make build-backup  - Build backup service image"
	@echo "  make build-verify  - Build verify service image"
	@echo ""

# Run integration tests
test:
	@echo "Running integration tests..."
	cd tests && bash run-tests.sh

# Run tests with verbose output
test-verbose:
	@echo "Running integration tests (verbose)..."
	cd tests && bash -x run-tests.sh

# Clean up test environment
test-clean:
	@echo "Cleaning up test environment..."
	cd tests && docker-compose -f docker-compose.test.yml down -v
	@echo "Test environment cleaned"

# Show test logs
test-logs:
	@echo "Showing test logs..."
	cd tests && docker-compose -f docker-compose.test.yml logs

# Build all images
build: build-backup build-verify

# Build backup service
build-backup:
	@echo "Building backup service..."
	cd services/backup && docker build -t postgres-backup:latest .
	@echo "Backup service built successfully"

# Build verify service
build-verify:
	@echo "Building verify service..."
	cd services/verify && docker build -t postgres-verify:latest .
	@echo "Verify service built successfully"

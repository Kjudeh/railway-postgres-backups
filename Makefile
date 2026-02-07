.PHONY: test test-verbose test-clean test-logs help build-backup build-verify build validate-env

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

# Validate test environment
validate-env:
	@echo "Validating test environment..."
	@test -d tests || (echo "ERROR: tests/ directory not found" && exit 1)
	@test -f tests/run-tests.sh || (echo "ERROR: run-tests.sh not found" && exit 1)
	@test -f tests/docker-compose.test.yml || (echo "ERROR: docker-compose.test.yml not found" && exit 1)
	@command -v bash >/dev/null 2>&1 || (echo "ERROR: bash not found" && exit 1)
	@echo "✓ Environment validation passed"

# Run integration tests
test: validate-env
	@echo "Running integration tests..."
	@cd tests && bash run-tests.sh || (echo "ERROR: Tests failed - see output above" && exit 1)

# Run tests with verbose output
test-verbose: validate-env
	@echo "Running integration tests (verbose)..."
	@cd tests && bash -x run-tests.sh || (echo "ERROR: Tests failed - see output above" && exit 1)

# Clean up test environment
test-clean:
	@echo "Cleaning up test environment..."
	@if [ -d tests ]; then \
		cd tests && (docker compose -f docker-compose.test.yml down -v --remove-orphans 2>/dev/null || \
		            docker-compose -f docker-compose.test.yml down -v --remove-orphans 2>/dev/null || \
		            echo "WARNING: Could not clean up containers"); \
	fi
	@echo "✓ Test environment cleaned"

# Show test logs
test-logs:
	@echo "Showing test logs..."
	@if [ -d tests ]; then \
		cd tests && (docker compose -f docker-compose.test.yml logs 2>/dev/null || \
		            docker-compose -f docker-compose.test.yml logs 2>/dev/null || \
		            echo "ERROR: Could not retrieve logs"); \
	else \
		echo "ERROR: tests/ directory not found"; \
		exit 1; \
	fi

# Build all images
build: build-backup build-verify

# Build backup service
build-backup:
	@echo "Building backup service..."
	@test -d services/backup || (echo "ERROR: services/backup/ not found" && exit 1)
	@test -f services/backup/Dockerfile || (echo "ERROR: services/backup/Dockerfile not found" && exit 1)
	@cd services/backup && docker build -t postgres-backup:latest . || (echo "ERROR: Build failed" && exit 1)
	@echo "✓ Backup service built successfully"

# Build verify service
build-verify:
	@echo "Building verify service..."
	@test -d services/verify || (echo "ERROR: services/verify/ not found" && exit 1)
	@test -f services/verify/Dockerfile || (echo "ERROR: services/verify/Dockerfile not found" && exit 1)
	@cd services/verify && docker build -t postgres-verify:latest . || (echo "ERROR: Build failed" && exit 1)
	@echo "✓ Verify service built successfully"

# Contributing to PostgreSQL Backup & Restore Verification

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing.

## Code of Conduct

Be respectful, inclusive, and professional. We're all here to make better software.

## How Can I Contribute?

### Reporting Bugs

Before submitting a bug report:
1. Check existing [GitHub Issues](https://github.com/Kjudeh/railway-postgres-backups/issues)
2. Verify you're using the latest version
3. Test with the provided test suite

When submitting a bug report, include:
- Clear, descriptive title
- Steps to reproduce
- Expected behavior
- Actual behavior
- Environment details (OS, Docker version, PostgreSQL version)
- Relevant logs (redact any credentials!)
- Screenshots if applicable

**Template**:
```markdown
## Bug Description
A clear description of the bug

## Steps to Reproduce
1. Step one
2. Step two
3. Step three

## Expected Behavior
What should happen

## Actual Behavior
What actually happens

## Environment
- OS: [e.g., Ubuntu 22.04]
- Docker: [e.g., 24.0.0]
- PostgreSQL: [e.g., 16.0]
- Storage Provider: [e.g., AWS S3]

## Logs
```
Paste relevant logs here (redact credentials!)
```
```

### Suggesting Enhancements

Enhancement suggestions are welcome! Please include:
- Clear, descriptive title
- Detailed description of the enhancement
- Why it would be useful
- Examples of how it would work
- Any drawbacks or considerations

### Pull Requests

1. **Fork the repository**
2. **Create a branch** from `main`
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes**
4. **Test your changes** (see Testing section)
5. **Commit with clear messages** (see Commit Guidelines)
6. **Push to your fork**
7. **Open a Pull Request**

## Development Setup

### Prerequisites

- Docker and Docker Compose
- Bash (or Git Bash on Windows)
- Git
- Text editor

### Local Development

1. **Clone the repository**
   ```bash
   git clone https://github.com/Kjudeh/railway-postgres-backups.git
   cd railway-postgres-backups
   ```

2. **Run tests**
   ```bash
   make test
   ```

3. **Make changes**
   - Edit files in `services/backup/` or `services/verify/`
   - Update documentation if needed
   - Add/update tests

4. **Test your changes**
   ```bash
   make test
   ```

## Testing

### Running Tests

```bash
make test
```

Or for verbose output:

```bash
make test-verbose
```

Or directly:

```bash
cd tests
./run-tests.sh
```

### Writing Tests

When adding new features:
1. Add test scenarios to `tests/run-tests.sh`
2. Update `tests/docker-compose.test.yml` if needed
3. Ensure tests are deterministic and idempotent

### Test Coverage

Ensure your changes include:
- Unit tests (if applicable)
- Integration tests
- Documentation updates
- Example configurations

## Commit Guidelines

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Test changes
- `refactor`: Code refactoring
- `chore`: Maintenance tasks
- `perf`: Performance improvements
- `security`: Security fixes

**Examples**:
```
feat(backup): add support for custom compression levels

Add COMPRESSION_LEVEL environment variable to allow users
to configure gzip compression level (1-9).

Closes #123
```

```
fix(verify): handle missing backup files gracefully

Previously, verify service would crash if no backups existed.
Now it logs an error and continues.

Fixes #456
```

### Good Commit Messages

- Use imperative mood ("add feature" not "added feature")
- First line is 50 characters or less
- Body is wrapped at 72 characters
- Reference issues and PRs when relevant
- Explain *why*, not just *what*

## Code Style

### Shell Scripts

- Use `#!/bin/bash` shebang
- Use `set -euo pipefail` for safety
- Quote variables: `"$VAR"` not `$VAR`
- Use `[[` instead of `[` for conditionals
- Add comments for complex logic
- Use descriptive variable names

**Example**:
```bash
#!/bin/bash
set -euo pipefail

# Parse database URL
if [[ ! "$DATABASE_URL" =~ postgresql://([^:]+):([^@]+)@([^:]+):([^/]+)/(.+) ]]; then
    echo "ERROR: Invalid DATABASE_URL format" >&2
    exit 1
fi

PGUSER="${BASH_REMATCH[1]}"
PGPASSWORD="${BASH_REMATCH[2]}"
```

### Dockerfile

- Use official base images
- Minimize layers
- Use specific versions (not `latest`)
- Clean up in the same layer
- Use multi-stage builds when appropriate

**Example**:
```dockerfile
FROM postgres:16-alpine

RUN apk add --no-cache \
    aws-cli \
    bash \
    && rm -rf /var/cache/apk/*
```

### Documentation

- Use Markdown
- Keep lines under 100 characters
- Use code blocks with language tags
- Include examples
- Update table of contents
- Check for typos

## Documentation

### What Needs Documentation?

- New environment variables
- New features
- Breaking changes
- Configuration changes
- API changes

### Where to Document?

- `README.md` - Overview, quick start
- `docs/configuration.md` - Environment variables
- `docs/architecture.md` - System design
- `docs/troubleshooting.md` - Common issues
- `docs/runbooks.md` - Operational procedures
- Service READMEs - Service-specific details

## Project Structure

```
.
├── services/
│   ├── backup/          # Backup service
│   │   ├── Dockerfile
│   │   ├── backup.sh
│   │   ├── healthcheck.sh
│   │   └── README.md
│   └── verify/          # Restore verification service
│       ├── Dockerfile
│       ├── verify.sh
│       ├── test-queries.sql
│       └── README.md
├── tests/               # Integration tests
│   ├── docker-compose.test.yml
│   ├── run-tests.sh
│   └── README.md
├── docs/                # Documentation
│   ├── architecture.md
│   ├── configuration.md
│   ├── restore.md
│   ├── troubleshooting.md
│   └── runbooks.md
├── .github/
│   └── workflows/       # CI/CD
│       └── test.yml
├── README.md
├── LICENSE
├── SECURITY.md
├── CONTRIBUTING.md
├── CHANGELOG.md
└── railway.toml         # Railway configuration
```

## Review Process

1. **Automated Checks**
   - Tests must pass
   - No merge conflicts
   - Follows commit guidelines

2. **Manual Review**
   - Code quality
   - Documentation completeness
   - Test coverage
   - Security considerations

3. **Feedback**
   - Maintainers will review within 7 days
   - Address feedback in new commits
   - Don't force-push after review

4. **Merge**
   - Squash and merge (usually)
   - Clean commit history
   - Update CHANGELOG.md

## Release Process

1. Update version in relevant files
2. Update CHANGELOG.md
3. Create Git tag
4. Push tag to trigger release
5. Update Railway template (if applicable)

## Questions?

- Open a [GitHub Discussion](https://github.com/Kjudeh/railway-postgres-backups/discussions)
- Check existing [documentation](docs/)
- Ask in pull request comments

## Recognition

Contributors will be:
- Listed in CHANGELOG.md
- Credited in release notes
- Recognized in README.md (optional)

Thank you for contributing!

FROM postgres:16-alpine

# Install AWS CLI and required tools
RUN apk add --no-cache \
    aws-cli \
    bash \
    curl \
    gzip \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Copy verification scripts
COPY entrypoint.sh /app/entrypoint.sh
COPY verify.sh /app/verify.sh
COPY test-queries.sql /app/test-queries.sql

# Make scripts executable
RUN chmod +x /app/entrypoint.sh /app/verify.sh

# Use entrypoint for safety validation
CMD ["/app/entrypoint.sh"]

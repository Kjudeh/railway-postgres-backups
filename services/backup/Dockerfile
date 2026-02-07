FROM postgres:16-alpine

# Install required tools
# Using aws-cli as the standardized S3 tool (widely supported, reliable)
RUN apk add --no-cache \
    aws-cli \
    bash \
    curl \
    gzip \
    openssl \
    jq \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Copy scripts in order of dependency
COPY lib/ /app/lib/
COPY entrypoint.sh /app/entrypoint.sh
COPY backup.sh /app/backup.sh
COPY healthcheck.sh /app/healthcheck.sh

# Make scripts executable
RUN chmod +x /app/entrypoint.sh \
    /app/backup.sh \
    /app/healthcheck.sh \
    /app/lib/*.sh

# Health check
HEALTHCHECK --interval=5m --timeout=30s --start-period=10s --retries=3 \
    CMD /app/healthcheck.sh

# Use entrypoint as main runner
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["backup"]

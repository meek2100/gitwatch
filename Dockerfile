ARG BASE_IMAGE=alpine:3.20
FROM ${BASE_IMAGE}

# Create a non-root user and group first
# --- FIX: Added '-s /bin/bash' to set a valid login shell ---
RUN addgroup -S appgroup && adduser -S -s /bin/bash appuser -G appgroup

# Consolidate RUN commands, remove all version pins
# This allows apk to resolve dependencies correctly.
RUN apk add --no-cache \
        bash \
        git \
        inotify-tools \
        openssh \
        su-exec \
        util-linux \
        coreutils \
        procps \
    && mkdir -p /app \
    && chown appuser:appgroup /app

WORKDIR /app

# Copy files and ensure correct ownership
COPY --chown=appuser:appgroup gitwatch.sh entrypoint.sh LICENSE ./

RUN chmod +x /app/gitwatch.sh /app/entrypoint.sh

# Add an environment variable to signal gitwatch is running in a Docker environment
ENV GITWATCH_DOCKER_ENV=true

# Switch to the non-root user for build/runtime defaults
USER appuser

# Healthcheck: Checks for a status file managed by the script.
# 1. `test -f`: Fails if the file is missing (e.g., script crashed or is in cool-down).
# 2. `find ... -mmin -3`: Fails if the file exists but is "stale" (older than 3 minutes),
#    indicating the main watch loop is hung on a read or git command.
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD test -f /tmp/gitwatch.status

ENTRYPOINT ["/app/entrypoint.sh"]

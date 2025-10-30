FROM alpine:3.20

# Create a non-root user and group first
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Consolidate RUN commands, pin package versions
# Replace 'gosu' with 'su-exec' (Alpine-native alternative)
RUN apk add --no-cache \
        bash=5.2.26-r0 \
        git=2.45.4-r0 \
        inotify-tools=4.23.9.0-r0 \
        openssh=9.7_p1-r5 \
        su-exec=0.3-r0 \
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

# Healthcheck: Checks if the watcher process is active.
# The main process (PID 1)
# is gitwatch.sh, and if it crashes, the container will stop automatically.
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD bash -c ' \
    # LIVENESS CHECK: Confirm the essential child watcher process is active.
    # Checks all process command lines for the watcher tool string ("inotifywait" or "fswatch").
    cat /proc/*/cmdline 2>/dev/null | grep -q "inotifywait\|fswatch" \
  '

ENTRYPOINT ["/app/entrypoint.sh"]

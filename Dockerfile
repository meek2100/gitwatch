# Pin Alpine version instead of using latest
FROM alpine:3.20

# Create a non-root user and group first
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Consolidate RUN commands, pin package versions
RUN apk add --no-cache \
        bash=5.2.26-r0 \
        git=2.45.4-r0 \
        inotify-tools=4.23.9.0-r0 \
        openssh=9.7_p1-r5 \
        procps=procps-ng-4.0.4-r0 \
    && mkdir -p /app \
    && chown appuser:appgroup /app

WORKDIR /app

# Copy files and ensure correct ownership
COPY --chown=appuser:appgroup gitwatch.sh entrypoint.sh ./

RUN chmod +x /app/gitwatch.sh /app/entrypoint.sh

# Add an environment variable to signal gitwatch is running in a Docker environment
ENV GITWATCH_DOCKER_ENV=true

# Switch to the non-root user
USER appuser

# Healthcheck: Checks if the PID file exists, the parent is running, AND the child watcher process is active.
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD bash -c ' \
    if ! test -f /tmp/gitwatch.pid; then exit 1; fi; \
    PID=$(cat /tmp/gitwatch.pid); \
    if ! kill -0 "$PID" 2>/dev/null; then exit 1; fi; \
    # LIVENESS CHECK: Confirm the essential child process is active.
    # We search the full command line for "inotifywait" (the watcher tool).
    pgrep -f "inotifywait" >/dev/null \
  '

ENTRYPOINT ["/app/entrypoint.sh"]

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

# Healthcheck: Checks if the PID file exists AND if the main gitwatch.sh process is running.
HEALTHCHECK --interval=5s --timeout=3s --start-period=30s --retries=3 \
  CMD bash -c 'test -f /tmp/gitwatch.pid && kill -0 "$(cat /tmp/gitwatch.pid)"'

ENTRYPOINT ["/app/entrypoint.sh"]

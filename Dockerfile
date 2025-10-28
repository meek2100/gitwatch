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

# Switch to the non-root user
USER appuser

# Add a basic healthcheck (example: check if bash is runnable)
HEALTHCHECK --interval=5m --timeout=3s \
  CMD bash -c "exit 0" || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
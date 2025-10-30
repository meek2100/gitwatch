#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- PUID/PGID Switching for Volume Permissions ---
# Default user is 'appuser' (UID 1000) created in the Dockerfile.
# If PUID/PGID are set, change the UID/GID of appuser to match the host user.
PUID=${PUID:-}
PGID=${PGID:-}
CONTAINER_USER="appuser"

if [ -n "$PUID" ] && [ -n "$PGID" ]; then
  # Check if PUID/PGID are different from default (1000/1000 in Alpine)
  if [ "$PUID" != "$(id -u $CONTAINER_USER)" ] || [ "$PGID" != "$(id -g $CONTAINER_USER)" ]; then
    echo "Starting as UID: $PUID, GID: $PGID"
    # Change appuser's UID and GID
    usermod -u "$PUID" "$CONTAINER_USER" 2>/dev/null || echo "Warning: Could not set UID for $CONTAINER_USER" >&2
    groupmod -g "$PGID" "$CONTAINER_USER" 2>/dev/null || echo "Warning: Could not set GID for $CONTAINER_USER" >&2

    # NEW: Only chown critical files (like the scripts) and rely on gosu
    # to operate as the correct user on the mounted volumes. This avoids
    # slow recursive chown on large volumes.
    chown "$PUID":"$PGID" /app/entrypoint.sh /app/gitwatch.sh 2>/dev/null || true
    chown "$PUID":"$PGID" /app 2>/dev/null || true
  else
    echo "Starting as default user ($CONTAINER_USER) with ID: $PUID/$PGID"
  fi
  # Use gosu to execute the rest of the script as the correct user
  GOSU_COMMAND="gosu $CONTAINER_USER"
else
  # No PUID/PGID set, run as the default appuser (which is PID 1, but we use 'exec' later)
  echo "PUID/PGID not set. Running as default container user: $CONTAINER_USER"
  # Use 'exec' to replace the shell, will run as USER appuser defined in Dockerfile
  GOSU_COMMAND="exec"
fi
# --------------------------------------------------


# --- Environment Variable Configuration with Defaults ---
# Target directory to watch
GIT_WATCH_DIR=${GIT_WATCH_DIR:-/app/watched-repo}

# Git options
GIT_REMOTE=${GIT_REMOTE:-origin}
GIT_BRANCH=${GIT_BRANCH:-main}
GIT_EXTERNAL_DIR=${GIT_EXTERNAL_DIR:-} # Path to the external .git directory (e.g., /app/.git)
TIMEOUT=${GIT_TIMEOUT:-60} # New: Git operation timeout

# Gitwatch behavior
SLEEP_TIME=${SLEEP_TIME:-2}
COMMIT_MSG=${COMMIT_MSG:-"Auto-commit: %d"}
DATE_FMT=${DATE_FMT:-"+%Y-%m-%d %H:%M:%S"}
# New: Custom command for commit message
COMMIT_CMD=${COMMIT_CMD:-}
# Read the user-friendly glob pattern (for -X)
USER_EXCLUDE_PATTERN=${EXCLUDE_PATTERN:-""}
# New: Read the raw regex pattern (for -x)
RAW_EXCLUDE_REGEX=${RAW_EXCLUDE_REGEX:-""}
EVENTS=${EVENTS:-""}

# Boolean flags (set to "true" to enable)
PULL_BEFORE_PUSH=${PULL_BEFORE_PUSH:-false}
SKIP_IF_MERGING=${SKIP_IF_MERGING:-false}
VERBOSE=${VERBOSE:-false}
COMMIT_ON_START=${COMMIT_ON_START:-false}
PASS_DIFFS=${PASS_DIFFS:-false} # New: Pass diffs to custom command (-C)
USE_SYSLOG=${USE_SYSLOG:-false} # New: Log to Syslog (-S)


# --- Command Construction ---

# Use a bash array to safely build the command and its arguments
# Note: We do *not* include the script path here yet, it is added later with gosu/exec
cmd=( )

# Add options with arguments (remote, branch, sleep time, date format)
cmd+=( -r "${GIT_REMOTE}" )
cmd+=( -b "${GIT_BRANCH}" )
cmd+=( -s "${SLEEP_TIME}" )
cmd+=( -t "${TIMEOUT}" ) # NEW: Timeout flag
cmd+=( -d "${DATE_FMT}" )

# Add custom commit command (-c) which overrides -m and -d
if [ -n "${COMMIT_CMD}" ]; then
  cmd+=( -c "${COMMIT_CMD}" )
  # If -C is enabled, add it now
  if [ "${PASS_DIFFS}" = "true" ]; then
    cmd+=( -C )
  fi
else
  # Only include -m if no custom command is provided
  cmd+=( -m "${COMMIT_MSG}" )
fi


# Add external Git directory if set
if [ -n "${GIT_EXTERNAL_DIR}" ]; then
  cmd+=( -g "${GIT_EXTERNAL_DIR}" )
fi

# --- Exclusion Logic: Pass variables to their respective flags ---

# 1. Pass raw regex pattern (for backward compatibility) to -x
if [ -n "${RAW_EXCLUDE_REGEX}" ]; then
  cmd+=( -x "${RAW_EXCLUDE_REGEX}" )
fi

# 2. Convert and pass user-friendly glob pattern to -X
if [ -n "${USER_EXCLUDE_PATTERN}" ]; then
  # Note on pattern conversion: This logic converts comma-separated glob patterns
  # (e.g., "*.log, tmp/") into a single regex string (e.g., ".*\.log|tmp/").

  # 1. Replace commas with spaces to treat as separate words.
  PATTERNS_AS_WORDS=${USER_EXCLUDE_PATTERN//,/ }
  # 2. Use an array to store and automatically trim whitespace from each pattern.
  read -r -a PATTERN_ARRAY <<< "$PATTERNS_AS_WORDS"
  # 3. Join the array elements with the regex OR pipe `|`.
  PROCESSED_PATTERN=$(IFS=\|; echo "${PATTERN_ARRAY[*]}")

  # 4. Escape periods to treat them as literal dots in regex
  PROCESSED_PATTERN=${PROCESSED_PATTERN//./\\.}

  # 5. Convert glob stars `*` into the regex equivalent `.*`
  PROCESSED_PATTERN=${PROCESSED_PATTERN//\*/.*}

  # 6. NEW: Convert glob question mark `?` into regex single-char wildcard `.`
  PROCESSED_PATTERN=${PROCESSED_PATTERN//\?/.}

  # Pass the CONVERTED PATTERN using the NEW -X (Glob Exclude) flag
  cmd+=( -X "${PROCESSED_PATTERN}" )
fi


if [ -n "${EVENTS}" ]; then
  cmd+=( -e "${EVENTS}" )
fi

# Add boolean flags if they are set to "true"
if [ "${PULL_BEFORE_PUSH}" = "true" ]; then
  cmd+=( -R )
fi

if [ "${SKIP_IF_MERGING}" = "true" ]; then
  cmd+=( -M )
fi

if [ "${VERBOSE}" = "true" ]; then
  cmd+=( -v )
fi

if [ "${COMMIT_ON_START}" = "true" ]; then
  cmd+=( -f )
fi

if [ "${USE_SYSLOG}" = "true" ]; then
  cmd+=( -S )
fi


# The final argument is the directory to watch
cmd+=( "${GIT_WATCH_DIR}" )

# --- Execution Logic ---

echo "Starting gitwatch with the following arguments:"
printf "%q " "/app/gitwatch.sh" "${cmd[@]}"
echo # Add a newline for cleaner logging
echo "-------------------------------------------------"

# Use 'gosu' or 'exec' to run the command, replacing the entrypoint shell process.
# This ensures that signals (like TERM) go directly to gitwatch.sh (PID 1 best practice).
# If PUID/PGID were set, GOSU_COMMAND is 'gosu appuser'. Otherwise, it's 'exec'.
$GOSU_COMMAND "/app/gitwatch.sh" "${cmd[@]}"

# If 'exec' or 'gosu' fails, the script continues and exits with an error status.
echo "ERROR: Exec/Gosu failed to start gitwatch.sh. Check permissions and path." >&2
exit 1

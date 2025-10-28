#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Environment Variable Configuration with Defaults ---
# Target directory to watch
GIT_WATCH_DIR=${GIT_WATCH_DIR:-/app/watched-repo}

# Git options
GIT_REMOTE=${GIT_REMOTE:-origin}
GIT_BRANCH=${GIT_BRANCH:-main}

# Gitwatch behavior
SLEEP_TIME=${SLEEP_TIME:-2}
COMMIT_MSG=${COMMIT_MSG:-"Scripted auto-commit on change (%d) by gitwatch.sh"}
DATE_FMT=${DATE_FMT:-"+%Y-%m-%d %H:%M:%S"}
# Read the user-friendly pattern
USER_EXCLUDE_PATTERN=${EXCLUDE_PATTERN:-""}
EVENTS=${EVENTS:-""}

# Boolean flags (set to "true" to enable)
PULL_BEFORE_PUSH=${PULL_BEFORE_PUSH:-false}
SKIP_IF_MERGING=${SKIP_IF_MERGING:-false}
VERBOSE=${VERBOSE:-false}
COMMIT_ON_START=${COMMIT_ON_START:-false}

# --- NEW: Cleanup Function (Called on EXIT or signal) ---
# This ensures we remove the PID file on shutdown and gracefully stop gitwatch
cleanup_pid() {
  if [ -f /tmp/gitwatch.pid ]; then
    # Try to gracefully terminate the running gitwatch process
    if kill -0 "$(cat /tmp/gitwatch.pid)" 2>/dev/null; then
      kill "$(cat /tmp/gitwatch.pid)" 2>/dev/null || true
    fi
    rm /tmp/gitwatch.pid
  fi
}
trap cleanup_pid EXIT INT TERM

# --- Command Construction (Same as before) ---

# Use a bash array to safely build the command and its arguments
cmd=( "/app/gitwatch.sh" )

# Add options with arguments
cmd+=( -r "${GIT_REMOTE}" )
cmd+=( -b "${GIT_BRANCH}" )
cmd+=( -s "${SLEEP_TIME}" )
cmd+=( -m "${COMMIT_MSG}" )
cmd+=( -d "${DATE_FMT}" )

# --- Convert User-Friendly Exclude Pattern to Regex (Same as before) ---
if [ -n "${USER_EXCLUDE_PATTERN}" ]; then
  # 1. Replace commas with spaces to treat as separate words.
  PATTERNS_AS_WORDS=${USER_EXCLUDE_PATTERN//,/ }
  # 2. Use an array to store and automatically trim whitespace from each pattern.
  read -r -a PATTERN_ARRAY <<< "$PATTERNS_AS_WORDS"
  # 3. Join the array elements with the regex OR pipe `|`.
  PROCESSED_PATTERN=$(IFS=\|; echo "${PATTERN_ARRAY[*]}")

  # 4. Escape periods to treat them as literal dots in regex
  PROCESSED_PATTERN=${PROCESSED_PATTERN//./\\.}

  # 5. Convert glob stars `*` into the regex equivalent `.*`
  PROCESSED_PATTERN=${PROCESSED_PATTERN//\*/\.\*}

  cmd+=( -x "${PROCESSED_PATTERN}" )
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

# The final argument is the directory to watch
cmd+=( "${GIT_WATCH_DIR}" )

# --- NEW: Execution Logic for Healthcheck Compatibility ---

echo "Starting gitwatch with the following arguments:"
printf "%q " "${cmd[@]}"
echo # Add a newline for cleaner logging
echo "-------------------------------------------------"

# 1. Run gitwatch.sh in the background.
"${cmd[@]}" > /dev/stdout 2> /dev/stderr &
GITWATCH_PID=$!

# 2. Wait briefly for gitwatch to crash on startup (e.g., due to permission error/exit 7).
# This gives it time to fail immediately before creating the PID file.
sleep 1

# 3. Check if the process is still running after the initial startup phase
if kill -0 "$GITWATCH_PID" 2>/dev/null; then
  # Application started successfully. Store PID for HEALTHCHECK.
  echo "gitwatch.sh started successfully (PID: $GITWATCH_PID). Monitoring PID."
  echo "$GITWATCH_PID" > /tmp/gitwatch.pid # Store PID for HEALTHCHECK
else
  # Application crashed immediately. The PID file is not created, causing HEALTHCHECK to fail.
  echo "gitwatch.sh failed to start immediately (PID: $GITWATCH_PID). HEALTHCHECK will report failure."
fi

# 4. The container must stay alive for the healthcheck to run. Block indefinitely.
echo "Container remains running for health check evaluation."
# This is now the main foreground process, keeping the container alive.
# This prevents the container from stopping when gitwatch.sh runs in the background.
tail -f /dev/null

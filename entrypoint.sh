#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Environment Variable Configuration with Defaults ---
# Target directory to watch
GIT_WATCH_DIR=${GIT_WATCH_DIR:-/app/watched-repo}

# Git options
GIT_REMOTE=${GIT_REMOTE:-origin}
GIT_BRANCH=${GIT_BRANCH:-main}
GIT_EXTERNAL_DIR=${GIT_EXTERNAL_DIR:-} # NEW: Path to the external .git directory (e.g., /app/.git)

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


# --- Command Construction ---

# Use a bash array to safely build the command and its arguments
cmd=( "/app/gitwatch.sh" )

# Add options with arguments
cmd+=( -r "${GIT_REMOTE}" )
cmd+=( -b "${GIT_BRANCH}" )
cmd+=( -s "${SLEEP_TIME}" )
cmd+=( -m "${COMMIT_MSG}" )
cmd+=( -d "${DATE_FMT}" )

# NEW: Add external Git directory if set
if [ -n "${GIT_EXTERNAL_DIR}" ]; then
  cmd+=( -g "${GIT_EXTERNAL_DIR}" )
fi

# --- Convert User-Friendly Exclude Pattern to Regex ---
if [ -n "${USER_EXCLUDE_PATTERN}" ]; then
  # Note on pattern conversion: This logic converts comma-separated glob patterns
  # (e.g., "*.log, tmp/") into a single regex string (e.g., ".*\.log|tmp/").
  # If a raw regex is intended, glob characters like '*' must not be used.

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

# --- Execution Logic ---

echo "Starting gitwatch with the following arguments:"
printf "%q " "${cmd[@]}"
echo # Add a newline for cleaner logging
echo "-------------------------------------------------"

# Use 'exec' to replace the entrypoint shell process with gitwatch.sh.
# This ensures that signals (like TERM) go directly to gitwatch.sh, and if gitwatch.sh
# exits, the container stops immediately (PID 1 best practice).
exec "${cmd[@]}"

# If 'exec' fails, the script continues and exits with an error status.
echo "ERROR: Exec failed to start gitwatch.sh. Check permissions and path." >&2
exit 1

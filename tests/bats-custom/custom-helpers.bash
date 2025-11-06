#!/usr/bin/env bash

# Load global configuration (variables, debug flags) FIRST
load 'bats-custom/bats-config'

# BATS Custom Helper Functions

# verbose_echo: Prints a message to BATS file descriptor 3 (>&3).
# This is used for debugging/logging purposes in BATS tests, ensuring it doesn't
# interfere with stdout/stderr capture.
verbose_echo() {
  echo "$@" >&3
}


# wait_for_git_change: Executes a Git command repeatedly until its output changes
#                      from the initial value or matches an expected value.
#
# Usage: wait_for_git_change <max_attempts> <delay_seconds> <git_command...>
#   OR   wait_for_git_change --target <expected_output> <max_attempts> <delay_seconds> <git_command...>
#
# Arguments:
#   --target <expected_output>: (Optional) Wait until the command output *exactly matches* this string.
#   max_attempts:  The maximum number of times to check the command.
#   delay_seconds: The time to wait (in seconds) between checks.
#   git_command...: The Git command and its arguments to execute and check.
#
# Returns:
#   0 if the command's output changes or matches the target within the allowed attempts.
#   1 if the timeout is reached before the condition is met.
#
# Outputs:
#   Debug messages to BATS file descriptor 3 (>&3).
wait_for_git_change() {
  local target_output=""
  local check_for_change=true

  if [[ "$1" == "--target" ]];
  then
    target_output="$2"
    check_for_change=false
    shift 2 # Consume --target and <expected_output>
  fi

  local max_attempts=$1
  local delay=$2
  shift 2 # Remove max_attempts and delay from arguments
  local attempt=1
  local initial_output=""
  local current_output=""

  # Basic input validation
  if ! [[ "$max_attempts" =~ ^[0-9]+$ ]] || ! [[ "$delay" =~ ^[0-9]+(\.[0-9]+)?$ ]];
  then
    verbose_echo "Usage: wait_for_git_change [--target <expected>] <max_attempts> <delay_seconds> <command...>"
    verbose_echo "Error: max_attempts must be an integer and delay_seconds must be a number."
    return 1
  fi
  if [ $# -eq 0 ];
  then
    verbose_echo "Error: No command provided to wait_for_git_change."
    return 1
  fi

  # Get initial output, but don't fail if the command does (e.g., file not found).
  # We can wait for a change from a "failed" state to a "success" state.
  initial_output=$( "$@" 2>/dev/null ) || true

  verbose_echo "Initial output: '$initial_output'"
  if [ "$check_for_change" = false ];
  then
    verbose_echo "Target output: '$target_output'";
  fi


  while (( attempt <= max_attempts ));
  do
    verbose_echo "Waiting attempt $attempt/$max_attempts..."
    sleep "$delay"

    current_output=$( "$@" )
    local current_status=$?
    if [ "$check_for_change" = true ]; then
      # Succeed if output is different from initial AND command was successful
      if [[ "$current_output" != "$initial_output" ]] && [ $current_status -eq 0 ];
      then
        verbose_echo "Output changed to '$current_output'. Success."
        return 0
      fi
    else
      # Succeed if output matches the target
      if [[ "$current_output" == "$target_output" ]] && [ $current_status -eq 0 ];
      then
        verbose_echo "Output matches target '$target_output'. Success."
        return 0
      fi
    fi

    (( attempt++ ))
  done

  verbose_echo "Timeout reached after $max_attempts attempts. Final output: '$current_output'"
  return 1 # Timeout
}

# wait_for_process_to_die: Waits for a process to terminate.
#
# Usage: wait_for_process_to_die <pid> <max_attempts> <interval>
#
# Arguments:
#   pid: The PID of the process to wait for.
#   max_attempts:  The maximum number of times to check the command.
#   interval: The time (in seconds) to wait between checks.
#
# Returns:
#   0 if the process terminated (PID is no longer found).
#   1 if the timeout is reached and the process is still running.
#
# Outputs:
#   Debug messages to BATS file descriptor 3 (>&3).
wait_for_process_to_die() {
  local pid=$1
  local max_attempts=$2
  local interval=$3
  local attempt=0

  if ! [[ "$max_attempts" =~ ^[0-9]+$ ]] || ! [[ "$interval" =~ ^[0-9]+(\.[0-9]+)?$ ]];
  then
    verbose_echo "Error: wait_for_process_to_die requires numeric arguments."
    return 1
  fi

  while kill -0 "$pid" &>/dev/null && [ "$attempt" -lt "$max_attempts" ];
  do
    sleep "$interval"
    attempt=$((attempt + 1))
  done

  # Final check: return 1 if process is still alive, 0 otherwise
  if kill -0 "$pid" &>/dev/null;
  then
    return 1 # Failed to die
  else
    return 0 # Died successfully
  fi
}

# create_failing_watcher_bin: Creates a dummy script that mimics the watcher binary
#                             (inotifywait or fswatch) but immediately exits with an error code.
#
# Usage: create_failing_watcher_bin <name> <exit_code>
#
# Arguments:
#   name: The name of the binary (e.g., inotifywait)
#   exit_code: The exit code the binary should return (e.g., 5)
#
# Returns:
#   The absolute path to the created dummy binary (to stdout).
create_failing_watcher_bin() {
  local name="$1"
  local exit_code="$2"
  # shellcheck disable=SC2154 # testdir is sourced in the calling bats test file
  local dummy_path="$testdir/bin/$name"

  # Ensure the directory exists
  # shellcheck disable=SC2154 # testdir is sourced in the calling bats test file
  mkdir -p "$testdir/bin"

  echo "#!/usr/bin/env bash" > "$dummy_path"
  echo "echo \"*** DUMMY WATCHER: $name failed with code $exit_code ***\" >&2" >> "$dummy_path"
  echo "exit $exit_code" >> "$dummy_path"
  chmod +x "$dummy_path"
  echo "$dummy_path"
}

# create_hanging_bin: Creates a dummy script that sleeps for a very long time,
#                     simulating a hung command (e.g., git push to a dead server).
#
# Usage: create_hanging_bin <name>
#
# Arguments:
#   name: The name of the binary to mock (e.g., git)
#
# Returns:
#   The absolute path to the created dummy binary (to stdout).
create_hanging_bin() {
  local name="$1"
  # shellcheck disable=SC2154 # testdir is sourced in the calling bats test file
  local dummy_path="$testdir/bin/$name-hanging"

  # Ensure the directory exists
  # shellcheck disable=SC2154 # testdir is sourced in the calling bats test file
  mkdir -p "$testdir/bin"

  echo "#!/usr/bin/env bash" > "$dummy_path"
  # Fix SC2129: Combine redirects
  {
    # Print signature to indicate the hanging version was called
    echo "echo \"*** DUMMY HANG: $name called, will sleep 600s ***\" >&2"
    # Sleep for 10 minutes (much longer than gitwatch.sh's 60s timeout)
    echo "sleep 600"
    # Exit cleanly if it ever wakes up, though it should be killed by 'timeout'
    echo "exit 0"
  } >> "$dummy_path"

  chmod +x "$dummy_path"
  echo "$dummy_path"
}

# Tests for the availability of a command
is_command() {
  # Use command -v for better POSIX compliance and alias handling than hash
  command -v "$1" &> /dev/null
}

# ---
# Helper to generate a unique hash for a path
# This is copied from gitwatch.sh to be used in lockfile tests
# ---
_get_path_hash() {
  local path_to_hash="$1"
  local path_hash=""

  if is_command "sha256sum"; then
    path_hash=$(echo -n "$path_to_hash" | sha256sum | (read -r hash _; echo "$hash"))
  elif is_command "md5sum";
  then
    path_hash=$(echo -n "$path_to_hash" | md5sum | (read -r hash _; echo "$hash"))
  else
    # Simple "hash" for POSIX compliance, replaces / with _
    path_hash="${path_to_hash//\//_}"
  fi
  echo "$path_hash"
}

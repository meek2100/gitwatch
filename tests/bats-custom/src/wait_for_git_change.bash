#!/usr/bin/env bash

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

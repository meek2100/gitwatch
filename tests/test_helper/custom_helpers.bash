#!/usr/bin/env bash

# BATS Custom Helper Functions

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

    if [[ "$1" == "--target" ]]; then
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
    if ! [[ "$max_attempts" =~ ^[0-9]+$ ]] || ! [[ "$delay" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "Usage: wait_for_git_change [--target <expected>] <max_attempts> <delay_seconds> <command...>" >&3
        echo "Error: max_attempts must be an integer and delay_seconds must be a number." >&3
        return 1
    fi
    if [ $# -eq 0 ]; then
        echo "Error: No command provided to wait_for_git_change." >&3
        return 1
    fi

    # Get initial output
    initial_output=$( "$@" )
    local initial_status=$?
    if [ $initial_status -ne 0 ] && [ "$check_for_change" = true ]; then
         echo "Initial command failed with status $initial_status. Cannot wait for change." >&3
         # If waiting for a target, failure might be the initial state, so we continue.
         if [ "$check_for_change" = true ]; then return 1; fi
    fi
     echo "Initial output: '$initial_output'" >&3
     if [ "$check_for_change" = false ]; then echo "Target output: '$target_output'" >&3; fi


    while (( attempt <= max_attempts )); do
        echo "Waiting attempt $attempt/$max_attempts..." >&3
        sleep "$delay"

        current_output=$( "$@" )
        local current_status=$?

        if [ "$check_for_change" = true ]; then
            # Succeed if output is different from initial AND command was successful
            if [[ "$current_output" != "$initial_output" ]] && [ $current_status -eq 0 ]; then
                echo "Output changed to '$current_output'. Success." >&3
                return 0
            fi
        else
            # Succeed if output matches the target
            if [[ "$current_output" == "$target_output" ]] && [ $current_status -eq 0 ]; then
                 echo "Output matches target '$target_output'. Success." >&3
                 return 0
            fi
        fi

        (( attempt++ ))
    done

    echo "Timeout reached after $max_attempts attempts. Final output: '$current_output'" >&3
    return 1 # Timeout
}

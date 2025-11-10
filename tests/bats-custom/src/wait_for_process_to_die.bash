#!/usr/bin/env bash

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

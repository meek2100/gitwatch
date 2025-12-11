#!/usr/bin/env bash

# Tests for the availability of a command
#
# Usage: is_command <command_name>
#
# Returns:
#   0 if the command is found in the PATH.
#   1 otherwise.
is_command() {
  # Use command -v for better POSIX compliance and alias handling than hash
  command -v "$1" &> /dev/null
}

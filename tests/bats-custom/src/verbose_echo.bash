#!/usr/bin/env bash

# verbose_echo: Prints a message to BATS file descriptor 3 (>&3).
# This is used for debugging/logging purposes in BATS tests, ensuring it doesn't
# interfere with stdout/stderr capture.
#
# Usage: verbose_echo "My debug message"
#
verbose_echo() {
  echo "$@" >&3
}

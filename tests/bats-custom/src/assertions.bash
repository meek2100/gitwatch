#!/usr/bin/env bash

# assert_exit_code <expected_code> [message]
# Checks if the last run command exited with the expected status code.
assert_exit_code() {
  local expected="$1"
  local msg="${2:-}"
  if [ "$status" -ne "$expected" ]; then
    if [ -n "$msg" ]; then
      fail "$msg. Expected exit code $expected, but got $status. Output: $output"
    else
      fail "Expected exit code $expected, but got $status. Output: $output"
    fi
  fi
}

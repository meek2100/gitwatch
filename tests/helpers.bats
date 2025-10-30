#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load' # Use bats-file for temp files

# Load the custom helper file to *source* the function we are testing
load 'bats-custom/custom-helpers'

# This is a unit test for the helper, so we mock the command it calls
# We create a dummy file that our mock command will read

setup() {
  # This file will store the "output" of our mock command
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  export MOCK_OUTPUT_FILE="$testdir/mock_output.txt"
  echo "initial_state" > "$MOCK_OUTPUT_FILE"
}

# This is our mock command. It's not 'git', it's just 'cat'.
# We are testing the helper's logic, not git.
@test "wait_for_git_change: Succeeds when output changes" {
  # In 0.5s, we will change the file *in the background*
  (sleep 0.5 && echo "new_state" > "$MOCK_OUTPUT_FILE") &

  # The helper will call 'cat $MOCK_OUTPUT_FILE'
  # It will first see "initial_state"
  # After 0.5s, it will see "new_state" and succeed
  run wait_for_git_change 10 0.1 cat "$MOCK_OUTPUT_FILE"
  assert_success
  assert_output --partial "Output changed to 'new_state'. Success."
}

@test "wait_for_git_change: Fails (times out) when output does not change" {
  # We do not change the file. It will always be "initial_state"
  run wait_for_git_change 3 0.1 cat "$MOCK_OUTPUT_FILE"
  assert_failure
  assert_output --partial "Timeout reached after 3 attempts."
}

@test "wait_for_git_change --target: Succeeds when output matches target" {
  # In 0.5s, change the file to the target state
  (sleep 0.5 && echo "target_state" > "$MOCK_OUTPUT_FILE") &

  run wait_for_git_change --target "target_state" 10 0.1 cat "$MOCK_OUTPUT_FILE"
  assert_success
  assert_output --partial "Output matches target 'target_state'. Success."
}

@test "wait_for_git_change --target: Fails (times out) if target is never matched" {
  # In 0.5s, change to a *different* state
  (sleep 0.5 && echo "wrong_state" > "$MOCK_OUTPUT_FILE") &

  run wait_for_git_change --target "target_state" 3 0.1 cat "$MOCK_OUTPUT_FILE"
  assert_failure
  assert_output --partial "Timeout reached after 3 attempts."
}

@test "wait_for_git_change: Handles initial command failure" {
  # Test if the *initial* command fails (e.g., file not found)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run wait_for_git_change 3 0.1 cat "$testdir/non_existent_file.txt"
  assert_failure
  assert_output --partial "Initial command failed with status 1. Cannot wait for change."
}

@test "wait_for_git_change --target: Continues if initial command fails" {
  # When using --target, we *expect* the initial command to fail (e.g.,)
  # We are waiting for the *target* state, which might be "success"

  # In 0.5s, create the file (making the command succeed)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  (sleep 0.5 && echo "target_state" > "$testdir/non_existent_file.txt") &

  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run wait_for_git_change --target "target_state" 10 0.1 cat "$testdir/non_existent_file.txt"
  assert_success
  assert_output --partial "Output matches target 'target_state'. Success."
}

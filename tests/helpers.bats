#!/usr/bin/env bats

# Test the test helpers themselves
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
load 'bats-custom/custom-helpers'

# --- FIX: Define a writable mock output file ---
export MOCK_OUTPUT_FILE=""

setup() {
  # --- FIX: Use BATS_TEST_TMPDIR for a writable temp file ---
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR is set by BATS
  MOCK_OUTPUT_FILE="$BATS_TEST_TMPDIR/mock_output.txt"
  echo "initial_state" > "$MOCK_OUTPUT_FILE"
}

teardown() {
  rm -f "$MOCK_OUTPUT_FILE"
}

@test "helpers_wait_for_change_success: Succeeds when output changes" {
  # Run the helper in the background
  wait_for_git_change 5 0.1 cat "$MOCK_OUTPUT_FILE" &
  local wait_pid=$!
  # Wait a moment and then change the file
  sleep 0.5
  echo "new_state" > "$MOCK_OUTPUT_FILE"

  # Wait for the helper to exit
  run wait "$wait_pid"
  assert_success "Helper function failed to detect change"
}

@test "helpers_wait_for_change_timeout: Fails (times out) when output does not change" {
  # Run the helper and expect it to fail (timeout)
  run wait_for_git_change 1 0.1 cat "$MOCK_OUTPUT_FILE"
  assert_failure "Helper function succeeded when it should have timed out"
}

@test "helpers_wait_for_target_success: Succeeds when output matches target" {
  local target_state="target_state_achieved"
  # Run the helper in the background
  wait_for_git_change 5 0.1 --target "$target_state" cat "$MOCK_OUTPUT_FILE" &
  local wait_pid=$!

  # Wait a moment, change to an intermediate state, then the target state
  sleep 0.5
  echo "intermediate_state" > "$MOCK_OUTPUT_FILE"
  sleep 0.5
  echo "$target_state" > "$MOCK_OUTPUT_FILE"

  # Wait for the helper to exit
  run wait "$wait_pid"
  assert_success "Helper function failed to detect target match"
}

@test "helpers_wait_for_target_timeout: Fails (times out) if target is never matched" {
  local target_state="target_state_never_achieved"
  # Run the helper in the background
  wait_for_git_change 1 0.1 --target "$target_state" cat "$MOCK_OUTPUT_FILE" &
  local wait_pid=$!
  # Change to a different state
  sleep 0.5
  echo "some_other_state" > "$MOCK_OUTPUT_FILE"

  # Wait for the helper to exit (it should time out and fail)
  run wait "$wait_pid"
  assert_failure "Helper function succeeded when it should have timed out"
}


@test "helpers_wait_for_change_initial_fail: Handles initial command failure" {
  # Run the helper with a command that fails, but still check for file change
  rm -f "$MOCK_OUTPUT_FILE" # Ensure file doesn't exist

  wait_for_git_change 5 0.1 cat "$MOCK_OUTPUT_FILE" &
  local wait_pid=$!
  # Wait a moment and then create the file (which changes the 'cat' output)
  sleep 0.5
  echo "new_state" > "$MOCK_OUTPUT_FILE"

  # Wait for the helper to exit
  run wait "$wait_pid"
  assert_success "Helper function failed to detect change after initial error"
}

@test "helpers_wait_for_target_initial_fail: Continues if initial command fails" {
  local target_state="target_state_achieved"
  rm -f "$MOCK_OUTPUT_FILE" # Ensure file doesn't exist

  # Run the helper in the background
  wait_for_git_change 5 0.1 --target "$target_state" cat "$MOCK_OUTPUT_FILE" &
  local wait_pid=$!
  # Wait a moment, create with intermediate state, then the target state
  sleep 0.5
  echo "intermediate_state" > "$MOCK_OUTPUT_FILE"
  sleep 0.5
  echo "$target_state" > "$MOCK_OUTPUT_FILE"

  # Wait for the helper to exit
  run wait "$wait_pid"
  assert_success "Helper function failed to detect target match after initial error"
}

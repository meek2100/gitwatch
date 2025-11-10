#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# This test must manage PIDs manually for the second test case
teardown() {
  if [ -n "${GITWATCH_PID_1:-}" ] && kill -0 "$GITWATCH_PID_1" &>/dev/null; then
    kill -9 "$GITWATCH_PID_1" &>/dev/null || true
  fi
  if [ -n "${GITWATCH_PID_2:-}" ] && kill -0 "$GITWATCH_PID_2" &>/dev/null; then
    kill -9 "$GITWATCH_PID_2" &>/dev/null || true
  fi
  unset GITWATCH_PID_1
  unset GITWATCH_PID_2
  # Call common teardown for directory cleanup
  _common_teardown
}

@test "lockfile_success: flock prevents a second instance *on the same target* from starting" {
  # Skip if 'flock' is not available, as this test relies on it.
  if ! command -v flock &>/dev/null; then
    skip "Test skipped: 'flock' command not found, which is required for this test."
  fi

  local output_file_1
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file_1=$(mktemp "$testdir/output1.XXXXX")
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_path="$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Start the first gitwatch instance in the background.
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$target_path" > "$output_file_1" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID_1=$!
  local first_pid=$GITWATCH_PID_1

  # 2. Wait for the first instance to start and acquire the lock
  sleep 1

  # 3. Run the *second* gitwatch instance in the foreground *on the same target*.
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$target_path"

  # 4. Assert that the second instance failed to start
  assert_failure "Second instance should have failed to start due to lock."
  # MODIFIED: Exit code 69 is the correct code for "already running"
  assert_exit_code 69 "Second instance should exit with code 69 (already running)."

  # 5. Assert that the error message confirms the lock was busy
  assert_output --partial "Error: gitwatch is already running on this repository/target"

  # 6. Assert that the *first* instance is still running
  run kill -0 "$first_pid"
  assert_success "First gitwatch instance (PID $first_pid) is not running, but should be."
  cd /tmp
}

@test "lockfile_per_target_success: Allows a second instance *on a different target* to run" {
  # Skip if 'flock' is not available
  if ! command -v flock &>/dev/null; then
    skip "Test skipped: 'flock' command not found."
  fi

  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_path_1="$testdir/local/$TEST_SUBDIR_NAME/dir1"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_path_2="$testdir/local/$TEST_SUBDIR_NAME/dir2"
  mkdir -p "$target_path_1"
  mkdir -p "$target_path_2"

  # 1. Start the first instance on dir1
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$target_path_1" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID_1=$!
  sleep 1 # Allow lock acquisition

  # 2. Start the second instance on dir2
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$target_path_2" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID_2=$!
  sleep 1 # Allow lock acquisition

  # 3. Assert both processes are still running
  run kill -0 "$GITWATCH_PID_1"
  assert_success "Instance 1 (PID $GITWATCH_PID_1) on dir1 died unexpectedly."

  run kill -0 "$GITWATCH_PID_2"
  assert_success "Instance 2 (PID $GITWATCH_PID_2) on dir2 died unexpectedly (or failed to start)."

  cd /tmp
}

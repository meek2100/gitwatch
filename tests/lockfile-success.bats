#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "lockfile_success: flock prevents a second instance from starting" {
  # Skip if 'flock' is not available, as this test relies on it.
  if ! command -v flock &>/dev/null; then
    skip "Test skipped: 'flock' command not found, which is required for this test."
  fi

  local output_file_1
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file_1=$(mktemp "$testdir/output1.XXXXX")

  # 1. Start the first gitwatch instance in the background. This one will acquire the lock.
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" $GITWATCH_TEST_ARGS "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file_1" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  # Store PID for teardown
  local first_pid=$GITWATCH_PID

  # 2. Wait for the first instance to start and acquire the lock
  sleep 1

  # 3. Run the *second* gitwatch instance in the foreground. This one should fail.
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # 4. Assert that the second instance failed to start
  assert_failure "Second instance should have failed to start due to lock."
  assert_exit_code 1 "Second instance should exit with code 1 (already running)."
  # 5. Assert that the error message confirms the lock was busy
  assert_output --partial "Error: gitwatch is already running on this repository"

  # 6. Assert that the *first* instance is still running
  run kill -0 "$first_pid"
  assert_success "First gitwatch instance (PID $first_pid) is not running, but should be."
  cd /tmp
}

#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# This test verifies that the 'trap' logic for INT/TERM signals
# correctly cleans up the main lockfile and the timer PID file.
@test "signal_handling: SIGTERM cleans up lockfile and timer PID file" {
  # Skip if 'flock' is not available, as this test relies on flock-based locking.
  if ! command -v flock &>/dev/null; then
    skip "Test skipped: 'flock' command not found."
  fi

  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_path="$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Determine the expected lockfile and timer PID file paths
  cd "$target_path"
  local GIT_DIR_PATH
  GIT_DIR_PATH=$(git rev-parse --absolute-git-dir)
  local target_abs_path
  target_abs_path=$(pwd -P)

  local target_hash
  target_hash=$(_get_path_hash "$target_abs_path")
  local lock_basename="gitwatch-target_${target_hash}"

  local LOCKFILE="$GIT_DIR_PATH/${lock_basename}.lock"
  local TIMER_PID_FILE="${TMPDIR:-/tmp}/${lock_basename}.timer.pid"

  # 2. Start gitwatch in the background
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" ${GITWATCH_TEST_ARGS} -s 10 "$target_path" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  local test_pid=$GITWATCH_PID
  sleep 1 # Allow watcher to initialize and acquire main lock

  # 3. Assert the main lockfile was created
  assert_file_exist "$LOCKFILE" "Main lockfile was not created at $LOCKFILE"

  # 4. Trigger a change to create the timer PID file
  echo "trigger for timer file" >> signal_test.txt
  sleep 0.5 # Give time for the debounce logic to start and create the PID file

  # Find the timer PID file
  assert_file_exist "$TIMER_PID_FILE" "Timer PID file was not created at $TIMER_PID_FILE"

  # 5. Send SIGTERM (graceful shutdown) to the main gitwatch process
  verbose_echo "# DEBUG: Sending SIGTERM to PID $test_pid"
  run kill -TERM "$test_pid"
  assert_success "kill -TERM command failed"

  # 6. Wait for the process to exit
  local max_wait=5
  local wait_count=0
  while kill -0 "$test_pid" 2>/dev/null && [ "$wait_count" -lt "$max_wait" ]; do
    verbose_echo "# DEBUG: Waiting for gitwatch PID $test_pid to exit..."
    sleep 0.5
    wait_count=$((wait_count + 1))
  done

  # 7. Assert the process is truly gone
  if kill -0 "$test_pid" 2>/dev/null; then
    fail "gitwatch process (PID $test_pid) failed to exit after SIGTERM."
  fi

  # 8. Assert the cleanup trap worked
  assert_file_not_exist "$LOCKFILE" "Main lockfile was not cleaned up by trap"
  assert_file_not_exist "$TIMER_PID_FILE" "Timer PID file was not cleaned up by trap"

  # 9. Assert the log shows the signal was received
  run cat "$output_file"
  assert_output --partial "Signal TERM received, shutting down."

  # 10. Unset GITWATCH_PID so teardown doesn't try to kill it again
  unset GITWATCH_PID
  cd /tmp
}

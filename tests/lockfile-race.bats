#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# This test must manage PIDs manually because the default
# teardown only knows about one $GITWATCH_PID
teardown() {
  verbose_echo "# Manual teardown for lockfile-race"
  if [ -n "${GITWATCH_PID_A:-}" ] && kill -0 "$GITWATCH_PID_A" &>/dev/null; then
    verbose_echo "# Killing PID A: $GITWATCH_PID_A"
    kill -9 "$GITWATCH_PID_A" &>/dev/null || true
  fi
  if [ -n "${GITWATCH_PID_B:-}" ] && kill -0 "$GITWATCH_PID_B" &>/dev/null; then
    verbose_echo "# Killing PID B: $GITWATCH_PID_B"
    kill -9 "$GITWATCH_PID_B" &>/dev/null || true
  fi
  unset GITWATCH_PID_A
  unset GITWATCH_PID_B
  # Call common teardown for directory cleanup
  _common_teardown
}

@test "lockfile_race_n_n_flag_allows_concurrent_runs_race_condition" {
  # Skip if 'flock' *is not* available, as the -n flag is only
  # relevant on systems that support locking.
  if ! command -v flock &>/dev/null; then
    skip "Test skipped: 'flock' not found, -n flag behavior is irrelevant."
  fi

  local output_file_A
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file_A=$(mktemp "$testdir/outputA.XXXXX")
  local output_file_B
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file_B=$(mktemp "$testdir/outputB.XXXXX")

  # Use a short sleep time to make the race easier to trigger
  local test_sleep_time=1

  # 1. Start Instance A in the background with -n
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -n -s "$test_sleep_time" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file_A" 2>&1 &
  # shellcheck disable=SC2034 # Used by manual teardown
  GITWATCH_PID_A=$!

  # --- FIX: Wait for Instance A to initialize by checking LOGS ---
  # Since -n disables lockfiles, we cannot wait for a file.
  # We wait for the "Starting file watch" message in the log.
  local started_a=0
  local max_wait_loops=20
  local i=0

  while [ $i -lt $max_wait_loops ]; do
    if grep -q "Starting file watch" "$output_file_A"; then
      started_a=1
      break
    fi
    sleep 0.1
    i=$((i + 1))
  done

  if [ $started_a -eq 0 ]; then
     # Fail gracefully if A didn't start
     verbose_echo "# Warning: Instance A did not log start message after waiting."
  fi
  # ---------------------------------------------------------------------

  # 2. Start Instance B in the background with -n
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -n -s "$test_sleep_time" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file_B" 2>&1 &
  # shellcheck disable=SC2034 # Used by manual teardown
  GITWATCH_PID_B=$!

  # 3. Wait for both instances to initialize (B catch-up)
  sleep 1
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 4. Trigger Instance A
  echo "Change from A" >> file_a.txt
  sleep 0.2 # Wait for A to see the change and start its debounce sleep

  # 5. Trigger Instance B *while A is sleeping*
  echo "Change from B" >> file_b.txt

  # 6. Wait for both commits to finish
  # Total wait = ~1s (sleep) + ~1s (sleep) + buffer
  local total_wait=5
  verbose_echo "# DEBUG: Waiting ${total_wait}s for both commits to finish..."
  sleep "$total_wait"

  # 7. Assert: Both processes should still be running
  run kill -0 "$GITWATCH_PID_A"
  assert_success "Instance A (PID $GITWATCH_PID_A) died unexpectedly"
  run kill -0 "$GITWATCH_PID_B"
  assert_success "Instance B (PID $GITWATCH_PID_B) died unexpectedly"

  # 8. Assert: There should be TWO new commits
  # (Initial commit + commit A + commit B = 3)
  run git rev-list --count HEAD
  assert_success
  assert_equal "3" "$output" "Expected 3 total commits, but found $output. Race condition failed."

  # 9. Assert: Check the log messages to see who made which commit
  run git log -n 2 --pretty="format:%s"
  assert_success
  assert_output --partial "file_a.txt"
  assert_output --partial "file_b.txt"

  # 10. Cleanup (handled by teardown)
  cd /tmp
}

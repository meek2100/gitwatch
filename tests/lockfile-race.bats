#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

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

@test "lockfile_race_n: -n flag allows concurrent runs (race condition)" {
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
  sleep 0.5 # Stagger starts slightly

  # 2. Start Instance B in the background with -n
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -n -s "$test_sleep_time" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file_B" 2>&1 &
  # shellcheck disable=SC2034 # Used by manual teardown
  GITWATCH_PID_B=$!

  # 3. Wait for both instances to initialize
  sleep 1
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  # <-- Unused initial_hash variable removed here -->

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

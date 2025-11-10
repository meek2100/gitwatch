#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# --- HELPER ---
# Mocks 'git' to fail 'push' commands based on a state file
create_failing_mock_git() {
  local name="$1"
  local real_path="$2"
  local state_file="$3"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local dummy_path="$testdir/bin/$name"

  # Ensure the directory exists
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  mkdir -p "$testdir/bin"

  # Create the mock script
  cat > "$dummy_path" << EOF
#!/usr/bin/env bash
# Mock Git script

# Log the command for debugging
echo "# MOCK_GIT: Received command: \$@" >&2

if [ "\$1" = "push" ]; then
  if [ -f "$state_file" ]; then
    echo "# MOCK_GIT: Push command SUCCEEDING (state file exists)." >&2
    exec $real_path "\$@"
  else
    echo "# MOCK_GIT: Push command FAILING (state file not found)." >&2
    exit 1 # Fail the push
  fi
else
  # Pass all other commands (commit, rev-parse, etc.) to the real git
  exec $real_path "\$@"
fi
EOF

  chmod +x "$dummy_path"
  echo "$dummy_path"
}

# --- TESTS ---

@test "backoff: Enters cool-down and recovers" {
  # 1. Setup: Override backoff constants for a fast test
  export GW_MAX_FAIL_COUNT=3
  export GW_COOL_DOWN_SECONDS=4
  # Use a very short debounce sleep
  local test_sleep_time=0.5

  local state_file="$testdir/git_state.tmp"
  local real_git_path
  real_git_path=$(command -v git)
  local dummy_git
  dummy_git=$(create_failing_mock_git "git" "$real_git_path" "$state_file")
  export GW_GIT_BIN="$dummy_git"

  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 2. Start gitwatch with remote push enabled
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -s "$test_sleep_time" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -r origin "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1 # Allow watcher to initialize

  # 3. Trigger 3 failures (GW_MAX_FAIL_COUNT)
  verbose_echo "# DEBUG: Triggering 3 failures..."
  echo "change 1" >> file.txt; sleep 2 # Wait for commit/push to fail
  echo "change 2" >> file.txt; sleep 2 # Wait for commit/push to fail
  echo "change 3" >> file.txt; sleep 2 # Wait for commit/push to fail

  # 4. Assert: Check log for 3 failures and entry into cool-down
  run cat "$output_file"
  assert_output --partial "Incrementing failure count to 1/3"
  assert_output --partial "Incrementing failure count to 2/3"
  assert_output --partial "Incrementing failure count to 3/3"
  assert_output --partial "Max failures reached. Entering cool-down period for 4 seconds."

  # 5. Trigger a 4th change *during* the cool-down
  verbose_echo "# DEBUG: Triggering change during cool-down..."
  echo "change 4 (SKIPPED)" >> file.txt
  sleep 1 # Give time for the trigger to be logged

  # 6. Assert: Check log for the "Skipping trigger" message
  run cat "$output_file"
  assert_output --partial "In cool-down mode. Skipping trigger."

  # 7. Wait for cool-down to end (4s) + buffer (2s)
  verbose_echo "# DEBUG: Waiting for cool-down to expire..."
  sleep 5

  # 8. Trigger a 5th change (should reset and fail again)
  verbose_echo "# DEBUG: Triggering change after cool-down..."
  echo "change 5 (RETRY)" >> file.txt
  sleep 2 # Wait for commit/push to fail

  # 9. Assert: Check log for reset and new failure
  run cat "$output_file"
  assert_output --partial "Cool-down period finished. Resetting failure count and retrying."
  assert_output --partial "Incrementing failure count to 1/3" # Fails again, counter restarts

  # 10. Trigger a 6th change (to test success recovery)
  verbose_echo "# DEBUG: Triggering success..."
  touch "$state_file" # Create the state file to make 'git push' succeed
  echo "change 6 (SUCCESS)" >> file.txt
  sleep 2 # Wait for commit/push to succeed

  # 11. Assert: Check log for success and reset
  run cat "$output_file"
  assert_output --partial "Git operation succeeded. Resetting failure count."

  # 12. Cleanup
  unset GW_GIT_BIN
  unset GW_MAX_FAIL_COUNT
  unset GW_COOL_DOWN_SECONDS
  rm -f "$state_file"
  cd /tmp
}

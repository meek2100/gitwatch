#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# Helper to create a mock git that fails 'commit' once
create_failing_mock_git_commit() {
  local real_path="$1"
  local state_file="$2"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local dummy_path="$testdir/bin/git-commit-fail"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  mkdir -p "$testdir/bin"

  # Create the mock script
  cat > "$dummy_path" << EOF
#!/usr/bin/env bash
# Mock Git script
echo "# MOCK_GIT: Received command: \$@" >&2

if [ "\$1" = "commit" ]; then
  if [ -f "$state_file" ]; then
    # State file exists, so SUCCEED
    echo "# MOCK_GIT: 'commit' SUCCEEDING (state file exists)." >&2
    exec $real_path "\$@"
  else
    # State file does not exist, so FAIL and create it
    echo "# MOCK_GIT: 'commit' FAILING (exit 128)" >&2
    touch "$state_file"
    exit 128 # Simulate a generic git error (e.g., disk full)
  fi
else
  # Pass all other commands to the real git
  exec $real_path "\$@"
fi
EOF

  chmod +x "$dummy_path"
  echo "$dummy_path"
}

@test "git_command_failure: Retries on generic 'git commit' failure" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local state_file="$testdir/git_fail_state.tmp"

  # 1. Setup: Override backoff constants for a fast test
  export GW_MAX_FAIL_COUNT=2
  export GW_COOL_DOWN_SECONDS=3

  # 2. Create the mock git binary
  local real_git_path
  real_git_path=$(command -v git)
  local dummy_git
  dummy_git=$(create_failing_mock_git_commit "$real_git_path" "$state_file")
  export GW_GIT_BIN="$dummy_git"

  # 3. Start gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)
  sleep 1

  # 4. Trigger the first change (this will fail the commit)
  echo "change 1 (will fail)" >> file.txt

  # 5. Wait for the failure to be logged
  verbose_echo "# DEBUG: Waiting ${WAITTIME}s for commit to fail..."
  sleep "$WAITTIME"

  # 6. Assert: Log shows the failure and backoff
  run cat "$output_file"
  assert_output --partial "ERROR: 'git commit' failed with exit code 128."
  assert_output --partial "Incrementing failure count to 1/2"

  # 7. Assert: Commit hash has NOT changed
  run git log -1 --format=%H
  assert_success
  assert_equal "$initial_hash" "$output" "Commit hash should not have changed after failure"

  # 8. Trigger the second change (this will succeed)
  echo "change 2 (will succeed)" >> file.txt

  # 9. Wait for the *successful* commit to appear
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit failed to happen on retry"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change after retry"

  # 10. Assert: Log shows the success and reset
  run cat "$output_file"
  assert_output --partial "MOCK_GIT: 'commit' SUCCEEDING"
  assert_output --partial "Git operation succeeded. Resetting failure count."

  # 11. Cleanup
  unset GW_GIT_BIN
  unset GW_MAX_FAIL_COUNT
  unset GW_COOL_DOWN_SECONDS
  cd /tmp
}

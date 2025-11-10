#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

@test "hook_failure_commit: Git pre-commit hook failure is handled gracefully and push is skipped" {
  local output_file
  local git_dir_path
  local initial_commit_hash
  local initial_remote_hash

  # Create a temporary file to capture gitwatch output
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Initial push to ensure remote is up-to-date and get initial hashes
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  echo "initial tracked file" > initial_push.txt
  git add initial_push.txt
  git commit -q -m "Initial commit to be pushed"
  git push -q origin master

  initial_commit_hash=$(git log -1 --format=%H)
  initial_remote_hash=$(git rev-parse origin/master)
  assert_equal "$initial_commit_hash" "$initial_remote_hash" "Initial push failed"
  verbose_echo "# Initial local hash: $initial_commit_hash"

  # Start gitwatch in the background with verbose logging and remote push
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -r origin "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to initialize

  # 2. Install a failing pre-commit hook
  # Use git rev-parse to reliably locate the hooks directory
  git_dir_path=$(git rev-parse --git-path hooks)
  local hook_file="$git_dir_path/pre-commit"

  echo "#!/bin/bash" > "$hook_file"
  echo "echo 'Hook failed: Commits are disabled for this test.'" >> "$hook_file"
  echo "exit 1" >> "$hook_file"

  chmod +x "$hook_file"
  verbose_echo "# DEBUG: Installed failing hook at $hook_file"

  # --- FIRST CHANGE (Failure Expected) ---
  echo "line1" >> file1.txt
  verbose_echo "# DEBUG: Waiting $WAITTIME seconds for hook failure attempt..."

  # Wait for the commit attempt to finish
  sleep "$WAITTIME"

  # Verify commit hash has NOT changed (Commit Failure Assertion)
  run git log -1 --format=%H
  assert_success
  local first_attempt_hash=$output
  assert_equal "$initial_commit_hash" "$first_attempt_hash" "Commit hash should NOT change due to hook failure"

  # Verify remote hash has NOT changed (Push Skip Assertion)
  run git rev-parse origin/master
  assert_success
  assert_equal "$initial_remote_hash" "$output" "Remote hash should NOT change (push should have been skipped)"

  # Verify log output shows the expected error message (Logging Assertion)
  run cat "$output_file"
  assert_output --partial "ERROR: 'git commit' failed with exit code 1." "Should log the commit failure error"
  assert_output --partial "Hook failed: Commits are disabled for this test." "Should log the hook failure output"
  refute_output --partial "Executing push command:" "Should NOT show push attempt after commit failure"

  # 3. Clean up the hook to allow the next commit (Recovery Preparation)
  run rm -f "$hook_file"
  assert_success "Failed to remove the hook file"
  verbose_echo "# DEBUG: Hook removed. Ready for success test."

  # --- SECOND CHANGE (Success Expected - Proves Recovery) ---
  echo "line2" >> file2.txt

  # Wait for the successful commit and push to appear (Recovery Assertion)
  # Check local commit first
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Second local commit failed to appear"
  local second_local_hash=$output
  assert_not_equal "$first_attempt_hash" "$second_local_hash" "Commit hash MUST change after successful commit"

  # Now wait for the remote push
  run wait_for_git_change 20 0.5 git rev-parse origin/master
  assert_success "Second push (after hook removal) failed to appear"

  # Verify remote hash has changed and matches local hash
  assert_equal "$second_local_hash" "$output" "Local and remote hashes do not match after successful push"

  cd /tmp
}

@test "hook_failure_push: Git pre-push hook failure is handled gracefully" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  git_dir_path=$(git rev-parse --git-path hooks)

  # 1. Get initial remote hash
  initial_remote_hash=$(git rev-parse origin/master)
  verbose_echo "# Initial remote hash: $initial_remote_hash"

  # 2. Start gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -r origin "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to initialize

  # 3. Install a failing pre-push hook
  local hook_file="$git_dir_path/pre-push"
  echo "#!/bin/bash" > "$hook_file"
  echo "echo '*** ERROR: Push blocked by pre-push hook for testing. ***' >&2" >> "$hook_file"
  echo "exit 1" >> "$hook_file"
  chmod +x "$hook_file"
  verbose_echo "# DEBUG: Installed failing pre-push hook at $hook_file"

  # 4. Trigger a change
  echo "A change to test pre-push failure" >> push_hook_test.txt

  # 5. Wait for the *local commit* to succeed
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Local commit failed to appear"
  local local_commit_hash=$output
  assert_not_equal "$initial_remote_hash" "$local_commit_hash" "Local commit did not happen"

  # 6. Wait for the *push attempt* to fail
  verbose_echo "# DEBUG: Waiting $WAITTIME seconds for push to fail..."
  sleep "$WAITTIME"

  # 7. Assert: Remote hash has NOT changed
  run git rev-parse origin/master
  assert_success
  assert_equal "$initial_remote_hash" "$output" "Remote hash should NOT change due to pre-push hook failure"

  # 8. Assert: Log output shows the push failure and the hook's error message
  run cat "$output_file"
  assert_output --partial "ERROR: 'git push' failed." "Should log the push failure"
  assert_output --partial "Push blocked by pre-push hook" "Should capture hook's stderr message"

  # 9. Assert: Script is still running
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process crashed after 'git push' failure, but it should have continued."
  # 10. Cleanup
  rm -f "$hook_file"
  cd /tmp
}

#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# This test simulates an unwritable .git directory to ensure the lockfile logic
# correctly falls back to using a lockfile in /tmp based on a repo hash.
@test "lockfile_fallback: Falls back to /tmp lockfile when .git is unwritable" {
  # Skip if 'flock' is not available, as this test relies on flock-based locking.
  if ! command -v flock &>/dev/null; then
    skip "Test skipped: 'flock' command not found, which is required for gitwatch lock logic."
  fi

  # Skip if neither sha256sum nor md5sum is available, as the fallback logic depends on them for a unique name
  if ! command -v sha256sum &>/dev/null && ! command -v md5sum &>/dev/null;
  then
    skip "Test skipped: Neither 'sha256sum' nor 'md5sum' found, cannot verify hashed lockfile name."
  fi

  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Determine the .git path from the test repo
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  local GIT_DIR_PATH
  GIT_DIR_PATH=$(git rev-parse --absolute-git-dir)
  assert_success "Failed to find git directory path"

  # Check if we can safely test permissions (avoiding root write issues)
  if [ ! -w "$GIT_DIR_PATH" ]; then
    fail "Cannot proceed: .git directory is already unwritable. Test cannot set/reset permissions."
  fi
  cd /tmp # Move out of test dir before changing permissions

  # 2. Simulate unwritable .git directory (chmod -w)
  local ORIGINAL_PERMS
  # Use a stat command that works on both Linux and macOS
  if [ "$RUNNER_OS" == "Linux" ];
  then
    ORIGINAL_PERMS=$(stat -c "%a" "$GIT_DIR_PATH")
  else
    ORIGINAL_PERMS=$(stat -f "%A" "$GIT_DIR_PATH")
  fi

  echo "# DEBUG: Removing write permission from $GIT_DIR_PATH (Original: $ORIGINAL_PERMS)" >&3
  # Remove write permission for the owner
  run chmod u-w "$GIT_DIR_PATH"
  assert_success "Failed to change permissions on .git directory"

  # 3. Start gitwatch, which should fail to touch the lockfile in GIT_DIR_PATH and fall back
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" $GITWATCH_TEST_ARGS "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  # 4. Wait for initialization and check log
  sleep 2

  # 5. Assert: Check log output confirms fallback and the unique name format
  run cat "$output_file"
  assert_output --partial "Warning: Cannot write lockfile to $GIT_DIR_PATH. Falling back to temporary directory." \
    "Did not log the expected fallback warning"

  # Assert that the path contains /tmp/gitwatch- and a hash (which ensures uniqueness per repo)
  assert_output --regexp "/tmp/gitwatch-[0-9a-f]{32,64}\\.lock" "Did not log a temporary lockfile path with a hash"

  # 6. Trigger change and verify commit using the fallback lock
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  echo "fallback test" >> fallback_test_file.txt
  # This commit attempt proves that the lock (and therefore the script) is functional.
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit timed out, suggesting lock/commit failed even with fallback"
  assert_not_equal "$initial_hash" "$output" "Commit hash did not change"

  # 7. Cleanup: Restore original permissions before _common_teardown runs
  cd /tmp
  echo "# DEBUG: Restoring original permissions: $ORIGINAL_PERMS on $GIT_DIR_PATH" >&3
  # Use the number to restore permissions robustly
  run chmod "$ORIGINAL_PERMS" "$GIT_DIR_PATH"
  assert_success "Failed to restore original permissions"
}

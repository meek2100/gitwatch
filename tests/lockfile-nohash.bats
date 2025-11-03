#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# This test simulates missing hash commands to ensure the lockfile logic
# correctly falls back to using a basic path-based string for the lockfile name in /tmp.
@test "lockfile_nohash: Falls back to /tmp lockfile with path-based name when hash commands are missing" {
  # Skip if 'flock' is not available, as this test relies on flock-based locking.
  if ! command -v flock &>/dev/null; then
    skip "Test skipped: 'flock' command not found, which is required for gitwatch lock logic."
  fi

  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Determine the .git path from the test repo
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  local GIT_DIR_PATH
  GIT_DIR_PATH=$(git rev-parse --absolute-git-dir)
  assert_success "Failed to find git directory path"
  cd /tmp # Move out of test dir before modifying permissions

  # 2. Simulate unwritable .git directory (chmod -w)
  # This is required to force the *fallback directory* logic.
  local ORIGINAL_PERMS
  if [ "$RUNNER_OS" == "Linux" ]; then
    ORIGINAL_PERMS=$(stat -c "%a" "$GIT_DIR_PATH")
  else
    ORIGINAL_PERMS=$(stat -f "%A" "$GIT_DIR_PATH")
  fi
  run chmod u-w "$GIT_DIR_PATH"
  assert_success "Failed to change permissions on .git directory"

  # 3. Temporarily hide hash commands to force the *fallback name* logic.
  # Create a dummy bin directory that will override the system's /bin, /usr/bin for this run
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"
  local path_backup="$PATH"
  export PATH="$DUMMY_BIN:$PATH"

  # Double check that we can't find the commands now
  if command -v sha256sum &>/dev/null || command -v md5sum &>/dev/null; then
    # Restoration and cleanup
    export PATH="$path_backup"
    run chmod "$ORIGINAL_PERMS" "$GIT_DIR_PATH"
    fail "Test setup failed: Cannot reliably hide 'sha256sum'/'md5sum' to test fallback logic."
  fi
  echo "# DEBUG: Successfully hid hash commands via PATH manipulation." >&3

  # 4. Start gitwatch, which should fall back because of unwritable .git AND missing hash tools
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  # 5. Wait for initialization and check log
  sleep 2

  # 6. Assert: Check log output confirms fallback and the path-based name format
  local escaped_path_hash
  # The expected output is the path with slashes replaced by underscores (//\//_)
  escaped_path_hash="${GIT_DIR_PATH//\//_}"

  run cat "$output_file"
  assert_output --partial "Warning: Cannot write lockfile to $GIT_DIR_PATH. Falling back to temporary directory." \
    "Did not log the expected fallback warning"

  # Assert that the path contains /tmp/gitwatch- and the path-based "hash"
  assert_output --partial "/tmp/gitwatch-$escaped_path_hash.lock" "Did not log a temporary lockfile path with path-based name"

  # 7. Trigger change and verify commit using the fallback lock
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  echo "fallback no hash test" >> fallback_nohash_file.txt
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit timed out, suggesting lock/commit failed even with fallback"
  assert_not_equal "$initial_hash" "$output" "Commit hash did not change"

  # 8. Cleanup: Restore original permissions and PATH
  cd /tmp
  run chmod "$ORIGINAL_PERMS" "$GIT_DIR_PATH"
  export PATH="$path_backup"
}

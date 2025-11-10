#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# --- NEW: Source the main script to test functions directly ---
# This brings in the _get_path_hash function
# shellcheck disable=SC1091 # gitwatch.sh is intentionally sourced for unit testing
source "${BATS_TEST_DIRNAME}/../gitwatch.sh"
# --- END NEW ---

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
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_path="$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Determine the .git path from the test repo
  cd "$target_path"
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
  # shellcheck disable=SC2030,SC2031 # Modifying PATH is intentional for this test
  export PATH="$DUMMY_BIN:$PATH"

  # Double check that we can't find the commands now
  if command -v sha256sum &>/dev/null || command -v md5sum &>/dev/null; then
    # Restoration and cleanup
    export PATH="$path_backup"
    run chmod "$ORIGINAL_PERMS" "$GIT_DIR_PATH"
    fail "Test setup failed: Cannot reliably hide 'sha256sum'/'md5sum' to test fallback logic."
  fi
  verbose_echo "# DEBUG: Successfully hid hash commands via PATH manipulation."

  # 4. Start gitwatch, which should fall back because of unwritable .git AND missing hash tools
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$target_path" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!

  # 5. Wait for initialization and check log
  sleep 2

  # 6. Assert: Check log output confirms fallback and the path-based name format
  run cat "$output_file"
  assert_output --partial "Warning: Cannot write lockfile to $GIT_DIR_PATH. Falling back to temporary directory." \
    "Did not log the expected fallback warning"
  assert_output --partial "Warning: Neither 'sha256sum' nor 'md5sum' found."

  # --- MODIFIED: Call the _get_path_hash function from the sourced script ---
  # 6a. Calculate the expected path-based "hash" name *using the script's own logic*
  local target_abs_path
  target_abs_path=$(cd "$target_path" && pwd -P)
  local repo_hash_path
  repo_hash_path=$(_get_path_hash "$GIT_DIR_PATH") # Call the real function
  local target_hash_path
  target_hash_path=$(_get_path_hash "$target_abs_path") # Call the real function
  local expected_basename="gitwatch-repo_${repo_hash_path}-target_${target_hash_path}"
  # --- END MODIFICATION ---

  # Assert that the path contains /tmp/ and the path-based "hash"
  assert_output --partial "/tmp/${expected_basename}.lock" "Did not log a temporary lockfile path with path-based name: $expected_basename"

  # 7. Trigger change and verify commit using the fallback lock
  cd "$target_path"
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

# (At the end of the file tests/lockfile-nohash.bats)
@test "lockfile_nohash_writable_git: Falls back to path-based name inside .git when hash commands are missing" {
  # Skip if 'flock' is not available
  if ! command -v flock &>/dev/null; then
    skip "Test skipped: 'flock' command not found."
  fi

  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_path="$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Determine the .git path
  cd "$target_path"
  local GIT_DIR_PATH
  GIT_DIR_PATH=$(git rev-parse --absolute-git-dir)
  assert_success "Failed to find git directory path"
  cd /tmp # Move out of test dir

  # 2. Temporarily hide hash commands
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"
  # shellcheck disable=SC2031 # PATH modification is intentional for this test
  local path_backup="$PATH"
  # shellcheck disable=SC2030,SC2031 # Modifying PATH is intentional for this test
  export PATH="$DUMMY_BIN:$PATH"

  # 3. Assert hash commands are hidden
  if command -v sha256sum &>/dev/null || command -v md5sum &>/dev/null; then
    export PATH="$path_backup"
    fail "Test setup failed: Cannot reliably hide 'sha256sum'/'md5sum'."
  fi

  # 4. Start gitwatch (Note: .git IS writable)
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$target_path" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 2

  # 5. Assert: Check log output
  run cat "$output_file"
  # SHOULD NOT fall back to /tmp
  refute_output --partial "Falling back to temporary directory."
  # SHOULD warn about missing hash tools
  assert_output --partial "Warning: Neither 'sha256sum' nor 'md5sum' found."

  # --- MODIFIED: Call the _get_path_hash function from the sourced script ---
  # 6. Calculate the expected path-based "hash" name *using the script's own logic*
  local target_abs_path
  target_abs_path=$(cd "$target_path" && pwd -P)
  # Note: The script *only* uses the target hash for the basename when .git is writable
  local target_hash_path
  target_hash_path=$(_get_path_hash "$target_abs_path") # Call the real function
  local expected_basename="gitwatch-target_${target_hash_path}"
  # --- END MODIFICATION ---

  # Assert the lockfile path is in the .git dir
  assert_output --partial "Acquired main instance lock (FD 9) on $GIT_DIR_PATH/${expected_basename}.lock"

  # 7. Assert: Process is *still running*
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process exited unexpectedly"

  # 8. Cleanup
  export PATH="$path_backup"
  cd /tmp
}

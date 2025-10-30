#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# Test to ensure the SECOND critical permission check (on the .git directory)
# exits gracefully with the critical permission error (Exit Code 7) when Read/Execute fail.
@test "git_dir_perm_rx: Exits with code 7 when .git directory is unreadable or unexecutable" {
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"
  cd "$target_dir"
  local GIT_DIR_PATH
  # Get absolute path to the .git directory
  GIT_DIR_PATH=$(git rev-parse --absolute-git-dir)
  local original_perms

  # 1. Get original permissions of the .git directory
  if [ "$RUNNER_OS" == "Linux" ]; then
    original_perms=$(stat -c "%a" "$GIT_DIR_PATH")
  else
    original_perms=$(stat -f "%A" "$GIT_DIR_PATH")
  fi

  # 2. Remove read and execute permissions for the current user
  run chmod u-rx "$GIT_DIR_PATH"
  assert_success "Failed to change permissions on .git directory"

  # 3. Run gitwatch, expecting it to fail the permission check
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$target_dir"

  # 4. Assert exit code 7 and the critical permission error message
  assert_failure "Gitwatch should exit with non-zero status on critical permission error"
  assert_exit_code 7 "Gitwatch should exit with code 7 (Critical Permission Error)"
  assert_output --partial "⚠️  CRITICAL PERMISSION ERROR: Cannot Access Git Repository Metadata"
  assert_output --partial "permissions on the Git repository's metadata folder"

  # 5. Cleanup: Restore original permissions *before* teardown runs
  cd /tmp # Move out of test dir before changing permissions back
  run chmod "$original_perms" "$GIT_DIR_PATH"
  assert_success "Failed to restore original permissions"
}

# Test to ensure the FIRST critical permission check (on the target directory itself)
# exits gracefully with the critical permission error (Exit Code 7) when Read/Execute fail.
@test "target_dir_perm_rx: Exits with code 7 when target directory is unreadable or unexecutable" {
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"
  local original_perms

  # 1. Get original permissions of the target directory
  if [ "$RUNNER_OS" == "Linux" ]; then
    original_perms=$(stat -c "%a" "$target_dir")
  else
    original_perms=$(stat -f "%A" "$target_dir")
  fi

  # 2. Remove read and execute permissions for the current user
  run chmod u-rx "$target_dir"
  assert_success "Failed to change permissions on target directory"

  # 3. Run gitwatch, expecting it to fail the permission check
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$target_dir"

  # 4. Assert exit code 7 and the critical permission error message
  assert_failure "Gitwatch should exit with non-zero status on critical permission error"
  assert_exit_code 7 "Gitwatch should exit with code 7 (Critical Permission Error)"
  assert_output --partial "⚠️  CRITICAL PERMISSION ERROR: Cannot Access Target Directory"
  assert_output --partial "permissions on the target directory itself"

  # 5. Cleanup: Restore original permissions *before* teardown runs
  run chmod "$original_perms" "$target_dir"
  assert_success "Failed to restore original permissions"
}

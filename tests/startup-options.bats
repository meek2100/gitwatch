#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# Override setup to use the remote-enabled one
setup() {
  setup_with_remote
}

# Test 1: Commit on start successfully commits staged changes
@test "startup_commit_f_flag_commits_staged_changes_on_startup" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create a file and stage it, but DO NOT commit it
  echo "staged on start" > file_to_commit.txt
  git add file_to_commit.txt

  # Get the initial commit hash from the setup
  local initial_commit_hash
  initial_commit_hash=$(git log -1 --format=%H)
  verbose_echo "# Initial hash: $initial_commit_hash"

  # 2. Start gitwatch with -f
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -f "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  # 3. Wait for the new commit to appear (it should be immediate)
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Initial commit on start timed out"

  # 4. Verify the hash has changed
  local startup_commit_hash=$output
  assert_not_equal "$initial_commit_hash" "$startup_commit_hash" "Commit hash should change after startup commit"

  # 5. Verify the content of the commit message
  run git log -1 --pretty=%B
  assert_success
  # The commit message logic will use the 'file changes' summary
  assert_output --partial "File changes detected:  A file_to_commit.txt"

  cd /tmp
}

@test "startup_commit_f_with_push_f_flag_also_pushes_the_initial_commit_to_remote" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create a file and stage it, but DO NOT commit it
  echo "staged and pushed" > file_to_push.txt
  git add file_to_push.txt

  # Get the initial remote hash
  local initial_remote_hash
  initial_remote_hash=$(git rev-parse origin/master)
  verbose_echo "# Initial remote hash: $initial_remote_hash"

  # 2. Start gitwatch with -f and -r origin
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -f -r origin "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  # 3. Wait for the remote hash to change (push success)
  run wait_for_git_change 20 0.5 git rev-parse origin/master
  assert_success "Initial commit push timed out"

  # 4. Verify the remote hash has changed
  local final_remote_hash=$output
  assert_not_equal "$initial_remote_hash" "$final_remote_hash" "Remote hash should change after startup commit and push"

  # 5. Verify the local commit message
  run git log -1 --pretty=%B
  assert_success
  assert_output --partial "File changes detected:  A file_to_push.txt"

  cd /tmp
}

# --- CORRECTED TEST: -f with staged and unstaged changes ---
@test "startup_commit_f_all_changes_f_flag_commits_staged_unstaged_and_untracked_files" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create a file and STAGE it
  echo "staged change" > staged_file.txt
  git add staged_file.txt

  # 2. Create an UNSTAGED change (modification)
  echo "unstaged modification" >> initial_file.txt

  # 3. Create an UNTRACKED file
  echo "untracked content" > untracked_file.txt

  # Get the initial commit hash
  local initial_commit_hash
  initial_commit_hash=$(git log -1 --format=%H)
  verbose_echo "# Initial hash: $initial_commit_hash"

  # 4. Run gitwatch with -f, logging all output
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -f "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  # 5. Wait for the new commit to appear (it should be immediate)
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Initial commit on start timed out"

  # 6. Verify the hash has changed
  local startup_commit_hash=$output
  assert_not_equal "$initial_commit_hash" "$startup_commit_hash" "Commit hash should change after startup commit"

  # 7. Verify all files were committed
  run git log -1 --name-only --pretty=format:
  assert_success
  assert_output --partial "staged_file.txt"
  assert_output --partial "initial_file.txt" # This was unstaged, should be committed
  assert_output --partial "untracked_file.txt" # This was untracked, should be committed

  # 8. Verify the local status after the commit:
  # The working directory should be CLEAN
  run git status --porcelain
  assert_success
  assert_output "" "Working directory should be clean after -f commit"

  cd /tmp
}

# Test 2: Commit on start does nothing if no changes are pending
@test "startup_commit_no_change_f_flag_does_nothing_if_no_changes_are_pending" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # Get the initial commit hash from the setup
  local initial_commit_hash
  initial_commit_hash=$(git log -1 --format=%H)
  verbose_echo "# Initial hash: $initial_commit_hash"

  # 1. Start gitwatch with -f, logging all output
  # Note: Using WAITTIME from bats-custom/startup-shutdown.bash for the sleep duration
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -f "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  # 2. Wait longer than the script's default commit/debounce time
  sleep "$WAITTIME"

  # 3. Verify the hash has NOT changed
  run git log -1 --format=%H
  assert_success
  local after_startup_hash=$output
  assert_equal "$initial_commit_hash" "$after_startup_hash" "Commit hash should NOT change if no changes are pending"

  # 4. Verify log output confirms no commit was made
  run cat "$output_file"
  assert_output --partial "No relevant changes detected by git status (porcelain check)."
  refute_output --partial "Running git commit command:" "Should not show a commit command run"

  cd /tmp
}


# --- NEW TEST: check_git_config warning ---
@test "startup_git_config_check_warns_if_git_config_user_name_or_user_email_is_missing" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Unset the local user.name/user.email settings. The global ones (set in setup)
  # must also be unset for the warning to trigger.
  git config --local --unset user.name || true
  git config --local --unset user.email || true
  git config --global --unset user.name || true
  git config --global --unset user.email || true

  # 2. Run gitwatch, expecting the warning to be printed to stderr/output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow initialization

  # 3. Assert the warning is present
  run cat "$output_file"
  assert_output --partial "Warning: 'user.name' or 'user.email' is not set in your Git config."
  assert_output --partial "To set them globally, run:"

  # 4. Cleanup: Restore original global config before teardown runs
  git config --global user.name 'test user'
  git config --global user.email 'test@email.com'

  cd /tmp
}


# Test 3: Version flag
@test "startup_version_V_v_flag_prints_version_and_exits" {
  # 1. Get the expected version number dynamically from the VERSION file
  local version_file="${BATS_TEST_DIRNAME}/../VERSION"
  local expected_version_number
  # shellcheck disable=SC2155 # Declared on previous line
  expected_version_number=$(cat "$version_file")

  # 2. Run gitwatch with -V and verify output/exit status
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -V
  assert_success "Running gitwatch -V should exit successfully"
  assert_output "gitwatch.sh version $expected_version_number" "Output should be the version string"
}

@test "startup_non_git_repo_exits_gracefully_with_code_6_if_target_is_not_a_git_repo" {
  local non_repo_dir
  non_repo_dir=$(mktemp -d)

  # 1. Run gitwatch on a non-repo directory (no .git directory present)
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$non_repo_dir"

  # 2. Assert exit code 6 and the error message
  assert_failure "Gitwatch should exit with non-zero status on non-repo"
  assert_exit_code 6 "Gitwatch should exit with code 6 (Not a git repository)"
  assert_output --partial "Error: Not a git repository"

  # 3. Cleanup
  rm -rf "$non_repo_dir"
}

@test "startup_permission_check_target_exits_with_code_7_when_target_directory_is_unwritable" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"
  local original_perms

  # 1. Get original permissions of the target directory
  if [ "$RUNNER_OS" == "Linux" ];
  then
    original_perms=$(stat -c "%a" "$target_dir")
  else
    # Use stat -f "%A" for macOS/BSD permissions
    original_perms=$(stat -f "%A" "$target_dir")
  fi

  # 2. Remove write and execute permissions for the current user
  run chmod u-wx "$target_dir"
  assert_success "Failed to change permissions on target directory"

  # 3. Run gitwatch on the now unwritable target directory
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$target_dir"

  # 4. Assert exit code 7 and the critical permission error message
  assert_failure "Gitwatch should exit with non-zero status on permission error"
  assert_exit_code 7 "Gitwatch should exit with code 7 (Critical Permission Error)"
  assert_output --partial "CRITICAL PERMISSION ERROR: Cannot Access Target Directory"
  assert_output --partial "permissions on the target directory itself"

  # 5. Cleanup: Restore original permissions *before* teardown runs
  run chmod "$original_perms" "$target_dir"
  assert_success "Failed to restore original permissions"
}

@test "startup_commit_f_pull_rebase_conflict_f_flag_fails_commit_gracefully" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  local conflict_file="conflict_file.txt"
  local initial_remote_hash

  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create a file with conflicting content to be staged by -f
  echo "LOCAL CHANGE TO CONFLICT" > "$conflict_file"
  git add "$conflict_file"

  # 2. Simulate Upstream Change on Remote
  # shellcheck disable=SC2103 # cd is necessary here to manage clone/cleanup
  cd "$testdir"
  run git clone -q remote local_ahead
  assert_success "Cloning for local_ahead failed"
  cd local_ahead
  # Create the same file with different content
  echo "UPSTREAM CHANGE TO CONFLICT" > "$conflict_file"
  git add "$conflict_file"
  git commit -q -m "Upstream conflict commit"
  run git push -q origin master
  assert_success "Push from local_ahead failed"
  # Get the remote hash that gitwatch should not push past
  initial_remote_hash=$(git rev-parse HEAD)
  run rm -rf local_ahead

  # 3. Go back to gitwatch repo
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 4. Run gitwatch with -f, -r, and -R flags (expecting initial commit to succeed, but the subsequent pull-rebase to fail)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -f -r origin -R "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 2 # Give time for initial commit (succeeds) and pull-rebase (fails)

  # 5. Assert: Local commit hash *has* changed (due to -f)
  run git log -1 --format=%H
  assert_success
  refute_output --partial "$(git rev-parse HEAD^)" "Local commit hash should not be the setup commit"

  # 6. Assert: Repo is in a MERGE/REBASE state
  run git status --short
  assert_output --partial "UU $conflict_file" "Git status should show an unmerged file (rebase conflict)"

  # 7. Assert: Remote hash has NOT changed (Push skipped due to pull failure)
  run git rev-parse origin/master
  assert_success
  assert_equal "$initial_remote_hash" "$output" "Remote hash should NOT change (push should have been skipped)"

  # 8. Assert: Log output shows the expected error message
  run cat "$output_file"
  assert_output --partial "ERROR: 'git pull' failed. Skipping push."
  refute_output --partial "Executing push command:" "Should NOT show push attempt after pull failure"

  # 9. Cleanup: Abort the rebase so teardown can clean the repo
  git rebase --abort
  cd /tmp
}

@test "startup_shelp_flags_help_output_contains_all_expected_flags_exhaustive" {
  # 1. Run gitwatch without arguments to get the help message
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh"
  assert_failure # Should fail because no target is given (exit 0 after help is fine too)

  # 2. Assert that all flags are present
  assert_output --partial "-s <secs>"
  assert_output --partial "-t <secs>"
  assert_output --partial "-d <fmt>"
  assert_output --partial "-r <remote>"
  assert_output --partial "-R"
  assert_output --partial "-b <branch>"
  assert_output --partial "-g <path>"
  assert_output --partial "-l <lines>"
  assert_output --partial "-L <lines>"
  assert_output --partial "-m <msg>"
  assert_output --partial "-c <command>"
  assert_output --partial "-C"
  assert_output --partial "-e <events>"
  assert_output --partial "-f"
  assert_output --partial "-M"
  assert_output --partial "-S"
  assert_output --partial "-v"
  assert_output --partial "-q"
  assert_output --partial "-n"
  assert_output --partial "-V"
  assert_output --partial "-x <regex>"
  assert_output --partial "-X <glob/list>"
  assert_output --partial "SECURITY WARNING: The -c flag executes arbitrary code"
}

@test "startup_help_h_h_flag_prints_help_and_exits_with_success" {
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -h
  assert_success "Running gitwatch -h should exit successfully (code 0)"
  assert_output --partial "Usage:"
  assert_output --partial "gitwatch - watch file or directory and git commit all changes"
}

# --- NEW TEST: Empty Repository Startup ---
@test "startup_commit_empty_repo_creates_first_commit_in_an_empty_repository" {
  local empty_repo_dir
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  empty_repo_dir=$(mktemp -d "$testdir/empty-repo.XXXXX")
  cd "$empty_repo_dir"
  git init -q
  # Git config is required for the commit to succeed
  git config user.email "test@example.com"
  git config user.name "BATS Test"

  # Get initial hash (should fail or be empty)
  local initial_hash
  initial_hash=$(git log -1 --format=%H 2>/dev/null || echo "no_commit")

  # Start gitwatch
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$empty_repo_dir" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # Create the first file
  echo "first file" > first.txt

  # Wait for the commit
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "First commit in empty repo timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # Verify commit content
  run git log -1 --pretty=%B
  assert_output --partial "first.txt"

  cd /tmp
}

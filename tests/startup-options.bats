#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# Test 1: Commit on start successfully commits staged changes
@test "startup_commit_f: -f flag commits staged changes on startup" {
    cd "$testdir/local/$TEST_SUBDIR_NAME"

    # 1. Create a file and stage it, but DO NOT commit it
    echo "staged on start" > file_to_commit.txt
    git add file_to_commit.txt

    # Get the initial commit hash from the setup
    local initial_commit_hash
    initial_commit_hash=$(git log -1 --format=%H)
    echo "# Initial hash: $initial_commit_hash" >&3

    # 2. Start gitwatch with -f
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -f "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    # 3. Wait for the new commit to appear (it should be immediate)
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Initial commit on start timed out"

    # 4. Verify the hash has changed
    local startup_commit_hash=$output
    assert_not_equal "$initial_commit_hash" "$startup_commit_hash" "Commit hash should change after startup commit"

    # 5. Verify the content of the commit message (should be default)
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "Scripted auto-commit on change"


    cd /tmp
}

@test "startup_commit_f_with_push: -f flag also pushes the initial commit to remote" {
    cd "$testdir/local/$TEST_SUBDIR_NAME"

    # 1. Create a file and stage it, but DO NOT commit it
    echo "staged and pushed" > file_to_push.txt
    git add file_to_push.txt

    # Get the initial remote hash
    local initial_remote_hash
    initial_remote_hash=$(git rev-parse origin/master)
    echo "# Initial remote hash: $initial_remote_hash" >&3

    # 2. Start gitwatch with -f and -r origin
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -f -r origin "$testdir/local/$TEST_SUBDIR_NAME" &
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
    assert_output --partial "Scripted auto-commit on change"

    cd /tmp
}

# Test 2: Commit on start does nothing if no changes are pending
@test "startup_commit_no_change: -f flag does nothing if no changes are pending" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    cd "$testdir/local/$TEST_SUBDIR_NAME"

    # Get the initial commit hash from the setup
    local initial_commit_hash
    initial_commit_hash=$(git log -1 --format=%H)
    echo "# Initial hash: $initial_commit_hash" >&3

    # 1. Start gitwatch with -f, logging all output
    # Note: Using WAITTIME from bats-custom/startup-shutdown.bash for the sleep duration

    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -f "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
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
    "Gitwatch should report no changes detected"
    refute_output --partial "Running git commit command:" "Should not show a commit command run"

    cd /tmp
}

# Test 3: Version flag
@test "startup_version_V: -V flag prints version and exits" {
    # 1. Get the expected version number dynamically from the VERSION file
    local version_file="${BATS_TEST_DIRNAME}/../VERSION"
    local expected_version_number=$(cat "$version_file")

    # 2. Run gitwatch with -V and verify output/exit status
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -V
    assert_success "Running gitwatch -V should exit successfully"
    assert_output "gitwatch.sh version $expected_version_number" "Output should be the version string"
}

@test "startup_non_git_repo: Exits gracefully with code 6 if target is not a git repo" {
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

@test "startup_permission_check_target: Exits with code 7 when target directory is unwritable" {
    local target_dir="$testdir/local/$TEST_SUBDIR_NAME"
    local original_perms

    # 1. Get original permissions of the target directory
    if [ "$RUNNER_OS" == "Linux" ]; then
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
    assert_output --partial "⚠️  CRITICAL PERMISSION ERROR: Cannot Access Target Directory"
    assert_output --partial "permissions on the target directory itself"

    # 5. Cleanup: Restore original permissions *before* teardown runs
    run chmod "$original_perms" "$target_dir"
    assert_success "Failed to restore original permissions"
}

@test "startup_commit_f_pull_rebase_conflict: -f flag fails commit gracefully and skips push on pull-rebase conflict" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")
    local conflict_file="conflict_file.txt"
    local initial_remote_hash

    cd "$testdir/local/$TEST_SUBDIR_NAME"

    # 1. Create a file with conflicting content to be staged by -f
    echo "LOCAL CHANGE TO CONFLICT" > "$conflict_file"
    git add "$conflict_file"

    # 2. Simulate Upstream Change on Remote
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
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -f -r origin -R "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    sleep 2 # Give time for initial commit (succeeds) and pull-rebase (fails)

    # 5. Assert: Local commit hash *has* changed (due to -f)
    run git log -1 --format=%H
    assert_success
    local local_commit_hash=$output
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

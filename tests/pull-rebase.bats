#!/usr/bin/env bats

# Load standard helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load custom helpers
load 'test_helper/custom-helpers'
# Load setup/teardown
load 'startup-shutdown'

@test "pulling_and_rebasing_correctly: Handles upstream changes with -R flag" {
    # Start gitwatch directly in the background with pull-rebase enabled
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin -R "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for commit+push for file1 (wait for remote ref to update)
    wait_for_git_change 20 0.5 git rev-parse origin/master ||
    fail "wait_for_git_change timed out after file1 add"

    sleep 0.2

    # Now verify the state *after* the wait
    run git rev-parse origin/master
    assert_success "Git rev-parse origin/master failed after file1 add (post-wait verification)"

    run git rev-parse master
    assert_success "Git rev-parse master failed after file1 add (post-wait verification)"
    local commit1=$output
    run git rev-parse origin/master # Re-run to capture for assert_equal

    local remote_commit1=$output
    assert_equal "$commit1" "$remote_commit1" "Push after adding file1 failed"

    # Simulate another user cloning and pushing (file2)
    cd "$testdir"
    run git clone -q remote local2
    assert_success "Cloning for local2 failed"
    cd local2
    echo "line2" >> file2.txt
    git add file2.txt
    git commit -q -m "Commit from local2 (file2)"
    run git push -q origin master
    assert_success "Push from local2 failed"
    local remote_commit2=$(git rev-parse HEAD) # Get the hash of the commit pushed by local2

    # Go back to the first local repo and make another change (file3)
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1 # Short delay before modifying
    echo "line3" >> file3.txt

    # Wait LONGER for gitwatch to pull, rebase, commit, push
    wait_for_git_change 30 1 git rev-parse origin/master ||
    fail "wait_for_git_change timed out after file3 add/rebase"

    sleep 0.2

    # Verify push happened after rebase
    run git rev-parse master
    assert_success "Git rev-parse master failed after file3 add/rebase (post-wait verification)"
    local commit3=$output
    run git rev-parse origin/master # Re-run to capture for assert_equal
    assert_success "Git rev-parse origin/master failed after file3 add/rebase (post-wait verification)"
    local remote_commit3=$output
    assert_equal "$commit3" "$remote_commit3" "Push after adding file3 and rebase failed"
    assert_not_equal "$remote_commit2" "$remote_commit3" "Remote hash should have changed after gitwatch rebase/push"


    # Verify all files are present locally
    assert_file_exist "file1.txt"
    assert_file_exist "file2.txt" # Should have been pulled
    assert_file_exist "file3.txt" # Should have been committed/rebased

    # Check commit history: Ensure the commit message from the other repo is present
    run git log --oneline -n 4 # Look at recent history
    assert_success "git log failed after rebase"
    assert_output --partial "Commit from local2 (file2)" "Commit message from local2 not found in history"

    # Check that the originally added file is mentioned
    run git log --name-status -n 5 # Look further back
    assert_success
    assert_output --partial "file1.txt" # Ensure original change is still there

    cd /tmp
}


@test "pull_rebase_conflict: Handles merge conflict with -R flag gracefully" {
    # Use a shorter sleep time to speed up the test
    local test_sleep_time=0.5
    local output_file="$testdir/pull-rebase-conflict-output.txt"
    local initial_file="conflict_file.txt"

    # Start gitwatch with pull-rebase enabled, shorter sleep, and redirect output for error analysis
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s "$test_sleep_time" -r origin -R "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1

    # --- Initial Commit (Ensures gitwatch is running) ---
    echo "Original Line" > "$initial_file"
    wait_for_git_change 20 0.5 git rev-parse origin/master
    assert_success "Initial commit+push timed out"

    local commit1=$(git rev-parse HEAD)
    local remote_commit1=$(git rev-parse origin/master)
    assert_equal "$commit1" "$remote_commit1" "Push after initial change failed"

    # --- Setup Conflict (File is on same line in both branches) ---
    # 1. Simulate Upstream change (local2)
    cd "$testdir"
    run git clone -q remote local2
    assert_success "Cloning for local2 failed"
    cd local2
    echo "UPSTREAM CHANGE" > "$initial_file" # Change the file on the same line
    git add "$initial_file"
    git commit -q -m "Commit from local2 (upstream change)"
    run git push -q origin master
    assert_success "Push from local2 failed"
    local remote_commit2=$(git rev-parse HEAD)

    # 2. Simulate Local change (gitwatch repo)
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    echo "LOCAL CHANGE" > "$initial_file" # Change the same line
    sleep 1 # Wait for gitwatch to see the change

    # --- Trigger Pull/Rebase (Expected Failure) ---
    # Wait for the local commit to happen (which precedes the failing pull)
    run wait_for_git_change 30 1 git log -1 --format=%H
    assert_success "Gitwatch commit timed out after local change"
    local local_commit_after_local_change=$(git rev-parse HEAD)
    assert_not_equal "$commit1" "$local_commit_after_local_change" "Local commit didn't happen"

    # Wait an extra few seconds for the pull/rebase to attempt and fail
    sleep "$WAITTIME"

    # --- Assertions ---

    # 1. Verify push DID NOT happen
    run git rev-parse origin/master
    assert_success
    local remote_commit_final=$output
    # Remote should still be at remote_commit2, not the new local commit
    assert_equal "$remote_commit2" "$remote_commit_final" "Remote push should have been skipped due to rebase conflict"

    # 2. Verify git status is in a merging state (if rebase conflict occurred)
    run git status --short
    assert_output --partial "UU $initial_file" "Git status should show an unmerged file"

    # 3. Verify error log
    run cat "$output_file"
    assert_output --partial "ERROR: 'git pull' failed. Skipping push."
    assert_output --partial "could not apply" # Standard rebase conflict message

    # Cleanup: Resolve the conflict manually so teardown works
    git rebase --abort

    cd /tmp
}

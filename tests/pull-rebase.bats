#!/usr/bin/env bats

# Load standard helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load custom helpers
load 'test_helper/custom_helpers'
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

    # Removed the problematic assert_success check here
    sleep 0.2 # Keep small delay for potential filesystem consistency

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

    # Removed the problematic assert_success check here
    sleep 0.2 # Keep small delay

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

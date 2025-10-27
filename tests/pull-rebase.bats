#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'startup-shutdown'

@test "pulling_and_rebasing_correctly: Handles upstream changes with -R flag" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin -R "$testdir/local/remote" &
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"
    sleep 1
    echo "line1" >> file1.txt
    sleep "$WAITTIME" # Wait for commit+push for file1

    run git rev-parse master
    assert_success "Git rev-parse master failed after file1 add"
    local commit1=$output
    run git rev-parse origin/master
    assert_success "Git rev-parse origin/master failed after file1 add"
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

    # Go back to the first local repo and make another change (file3)
    cd "$testdir/local/remote"
    sleep 1 # Short delay before modifying
    echo "line3" >> file3.txt
    # *** INCREASED WAIT TIME HERE ***
    sleep $((WAITTIME * 2)) # Wait LONGER for gitwatch to pull, rebase, commit, push

    # Verify push happened after rebase
    run git rev-parse master
    assert_success "Git rev-parse master failed after file3 add/rebase"
    local commit3=$output
    run git rev-parse origin/master
    assert_success "Git rev-parse origin/master failed after file3 add/rebase"
    local remote_commit3=$output
    assert_equal "$commit3" "$remote_commit3" "Push after adding file3 and rebase failed"

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

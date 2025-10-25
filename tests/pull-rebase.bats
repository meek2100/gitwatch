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
    sleep "$WAITTIME"

    run git rev-parse master
    assert_success
    local commit1=$output
    run git rev-parse origin/master
    assert_success
    local remote_commit1=$output
    assert_equal "$commit1" "$remote_commit1"

    cd "$testdir"
    run git clone -q remote local2
    assert_success
    cd local2
    echo "line2" >> file2.txt
    git add file2.txt
    git commit -q -m "Commit from local2 (file2)"
    run git push -q origin master
    assert_success

    cd "$testdir/local/remote"
    sleep 1
    echo "line3" >> file3.txt
    sleep "$WAITTIME" # Wait for gitwatch to pull, rebase, commit, push

    run git rev-parse master
    assert_success
    local commit3=$output
    run git rev-parse origin/master
    assert_success
    local remote_commit3=$output
    assert_equal "$commit3" "$remote_commit3"

    assert_file_exist "file1.txt"
    assert_file_exist "file2.txt"
    assert_file_exist "file3.txt"

    # Check commit history - Ensure both changes are present, don't rely on exact order
    run git log --oneline -n 4 # Look at a few more commits
    assert_success
    # Check that the commit message from the other repo is present
    assert_output --partial "Commit from local2 (file2)"
    # Check that the locally added file (which got rebased) is mentioned
    # Use git log --name-status for a more reliable check based on filename
    run git log --name-status -n 4
    assert_success
    assert_output --partial "file3.txt"
    assert_output --partial "file1.txt" # Ensure original change is still there

    cd /tmp
}

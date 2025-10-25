#!/usr/bin/env bats

# Load bats-core helpers relative to the test file's location
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

# Load setup/teardown
load 'startup-shutdown' # Contains initial commit logic now

@test "pulling_and_rebasing_correctly: Handles upstream changes with -R flag" {

    # Start gitwatch with remote push and pull --rebase enabled
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin -R "$testdir/local/remote"
    assert_success
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote" # cd into the primary local clone

    # Make initial change (line1)
    sleep 1
    echo "line1" >> file1.txt
    sleep "$WAITTIME" # Wait for commit and push

    # Verify push happened
    run git rev-parse master
    assert_success
    local commit1=$output
    run git rev-parse origin/master
    assert_success
    local remote_commit1=$output
    assert_equal "$commit1" "$remote_commit1"

    # Simulate another user cloning and pushing (line2)
    cd "$testdir" # Go up to create sibling clone
    run git clone -q remote local2
    assert_success
    cd local2
    echo "line2" >> file2.txt
    git add file2.txt
    git commit -q -m "Commit from local2 (file2)"
    run git push -q origin master
    assert_success

    # Go back to the first local repo and make another change (line3)
    cd "$testdir/local/remote"
    sleep 1 # Short delay
    echo "line3" >> file3.txt
    sleep "$WAITTIME" # Wait for gitwatch to pull, rebase, commit, push

    # Verify push happened (local should match remote again)
    run git rev-parse master
    assert_success
    local commit3=$output
    run git rev-parse origin/master
    assert_success
    local remote_commit3=$output
    assert_equal "$commit3" "$remote_commit3"

    # Verify files from both changes are present
    assert_file_exist "file1.txt"
    assert_file_exist "file2.txt" # Pulled from remote
    assert_file_exist "file3.txt" # Added locally

    # Check commit order after rebase
    run git log --oneline -n 3
    assert_success
    # Expected order (most recent first):
    # 1. Commit for file3 (rebased)
    # 2. Commit from local2 (file2)
    # 3. Commit for file1
    assert_line --index 0 --partial "file3.txt" # Commit message likely includes filename due to diffstat/auto-msg
    assert_line --index 1 --partial "Commit from local2 (file2)"
    # Check that file1.txt appears in history (robust check)
    run git log --name-status -n 4
    assert_success
    assert_output --partial "file1.txt"
}

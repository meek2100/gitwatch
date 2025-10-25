#!/usr/bin/env bats

# Load bats-core helpers relative to the test file's location
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

# Load setup/teardown
load 'startup-shutdown'

@test "syncing_correctly: Commits and pushes adds, subdir adds, and removals" {
    # Start gitwatch with remote push enabled
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin "$testdir/local/remote"
    assert_success
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"

    # --- Test 1: Add initial file ---
    sleep 1
    echo "line1" >> file1.txt
    sleep "$WAITTIME"

    # Verify push happened
    run git rev-parse master
    assert_success
    local commit1=$output
    run git rev-parse origin/master
    assert_success
    local remote_commit1=$output
    assert_equal "$commit1" "$remote_commit1" "Push after adding file1 failed"

    # --- Test 2: Add file in subdirectory ---
    local lastcommit=$commit1
    mkdir subdir
    cd subdir
    echo "line2" >> file2.txt
    cd .. # Go back to repo root for git operations
    sleep "$WAITTIME"

    # Verify new commit happened
    run git rev-parse master
    assert_success
    local commit2=$output
    refute_equal "$lastcommit" "$commit2" "Commit after adding file2 in subdir failed"

    # Verify push happened
    run git rev-parse origin/master
    assert_success
    local remote_commit2=$output
    assert_equal "$commit2" "$remote_commit2" "Push after adding file2 failed"

    # --- Test 3: Remove file ---
    lastcommit=$commit2
    run rm subdir/file2.txt
    assert_success
    sleep "$WAITTIME"

    # Verify new commit happened
    run git rev-parse master
    assert_success
    local commit3=$output
    refute_equal "$lastcommit" "$commit3" "Commit after removing file2 failed"

    # Verify push happened
    run git rev-parse origin/master
    assert_success
    local remote_commit3=$output
    assert_equal "$commit3" "$remote_commit3" "Push after removing file2 failed"

    # Teardown handles cleanup
    cd /tmp # Move out of test dir before teardown
}

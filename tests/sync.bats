#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'startup-shutdown'

@test "syncing_correctly: Commits and pushes adds, subdir adds, and removals" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin "$testdir/local/remote" &
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"

    # --- Test 1: Add initial file ---
    sleep 1
    echo "line1" >> file1.txt
    sleep "$WAITTIME"

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
    # Add small delay after mkdir before writing file
    sleep 0.5
    cd subdir
    echo "line2" >> file2.txt
    cd .. # Go back to repo root
    sleep "$WAITTIME" # Wait for commit+push

    run git rev-parse master
    assert_success
    local commit2=$output
    refute_equal "$lastcommit" "$commit2" "Commit after adding file2 in subdir failed"

    run git rev-parse origin/master
    assert_success
    local remote_commit2=$output
    assert_equal "$commit2" "$remote_commit2" "Push after adding file2 failed"

    # --- Test 3: Remove file and directory ---
    lastcommit=$commit2
    run rm subdir/file2.txt
    assert_success
    # Add small delay between removing file and removing dir
    sleep 0.5
    run rmdir subdir
    assert_success
    sleep "$WAITTIME" # Wait for commit+push for removal

    run git rev-parse master
    assert_success
    local commit3=$output
    # Check that a new commit happened after the removal
    refute_equal "$lastcommit" "$commit3" "Commit after removing file2 and subdir failed"

    # Verify push happened after removal
    run git rev-parse origin/master
    assert_success
    local remote_commit3=$output
    assert_equal "$commit3" "$remote_commit3" "Push after removing file2 failed"

    # Verify the file and directory are indeed gone locally
    refute_file_exist "subdir/file2.txt"
    refute_file_exist "subdir"

    cd /tmp
}

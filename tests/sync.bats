#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "syncing_correctly: Commits and pushes adds, subdir adds, and removals" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"

    # --- Test 1: Add initial file ---
    sleep 1
    echo "line1" >> file1.txt

    # Wait for commit+push (wait for remote ref to update)
    run wait_for_git_change 20 0.5 git rev-parse origin/master
    assert_success "Git rev-parse origin/master failed after file1 add"

    run git rev-parse master
    assert_success "Git rev-parse master failed after file1 add"
    local commit1=$output
    run git rev-parse origin/master
    local remote_commit1=$output
    assert_equal "$commit1" "$remote_commit1" "Push after adding file1 failed"

    # --- Test 2: Add file in subdirectory ---
    local lastcommit=$commit1
    local lastremotecommit=$remote_commit1
    mkdir subdir
    sleep 0.5 # Small delay
    cd subdir
    echo "line2" >> file2.txt
    cd .. # Back to repo root

    # Wait for commit+push (by checking that remote hash has changed)
    run wait_for_git_change 20 0.5 git rev-parse origin/master
    assert_success "Push after adding file2 failed to appear on remote (timeout)"

     run git rev-parse master
    assert_success "Git rev-parse master failed after file2 add"
    local commit2=$output
    assert_not_equal "$lastcommit" "$commit2" "Commit after adding file2 in subdir failed"

    run git rev-parse origin/master
    assert_success "Git rev-parse origin/master failed after file2 add"
    local remote_commit2=$output
    assert_equal "$commit2" "$remote_commit2" "Push after adding file2 failed"
    assert_not_equal "$lastremotecommit" "$remote_commit2" "Remote commit hash did not change after file2 add"


    # --- Test 3: Remove file and directory ---
    lastcommit=$commit2

    lastremotecommit=$remote_commit2
    run rm subdir/file2.txt
    assert_success "rm subdir/file2.txt failed"
    sleep 0.5 # Delay between rm and rmdir might help watcher catch events separately
    run rmdir subdir
    assert_success "rmdir subdir failed"

    # Wait for potential commit+push for removal (by checking that remote hash has changed again)
    run wait_for_git_change 20 1 git rev-parse origin/master # Slightly longer delay after removal
    assert_success "Push after removal failed to appear on remote (timeout)"

    # Debug: Check git status right before hash comparison
    run git status -s
    echo "# Git status after removal wait: $output" >&3

    # Verify push happened reflecting the removal
    run git rev-parse master
    assert_success "Git rev-parse master failed after removal"
    local commit3=$output
    run git rev-parse origin/master
    assert_success "Git rev-parse origin/master failed after removal"
    local remote_commit3=$output
    assert_equal "$commit3" "$remote_commit3" "Push after removing file/subdir failed"
    assert_not_equal "$lastremotecommit" "$remote_commit3" "Remote commit hash did not change after removal"

    # Explicitly check that a new commit *did* happen locally
    assert_not_equal "$lastcommit" "$commit3" "Local commit hash did not change after removal"

    # Verify the file and directory are indeed gone locally
    assert_file_not_exists "subdir/file2.txt"
    assert_dir_not_exists "subdir"

    cd /tmp
}

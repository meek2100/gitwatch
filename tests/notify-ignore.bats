#!/usr/bin/env bats

# Load standard helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load custom helpers
load 'test_helper/custom_helpers.bash'
# Load setup/teardown
load 'startup-shutdown'

@test "notify_ignore: -x ignores changes in specified subdirectory" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")
    # Start gitwatch directly in the background, ignoring test_subdir/
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -x "test_subdir/" "$testdir/local/remote" > "$output_file" 2>&1 &
    GITWATCH_PID=$!

    cd "$testdir/local/remote"
    mkdir test_subdir
    sleep 1

    echo "line1" >> file1.txt
    # Wait for the first (allowed) commit to appear
    wait_for_git_change 20 0.5 git log -1 --format=%H
    run git log -1 --format=%H # Get the first commit hash
    local first_commit_hash=$output

    echo "line2" >> test_subdir/file2.txt
    # This is a negative test: wait to ensure a commit *does not* happen
    # We can't use wait_for_git_change directly as it expects change.
    # Instead, sleep for a generous duration and check the hash hasn't changed.
    sleep "$WAITTIME" # Use WAITTIME from setup

    run git log -1 --format=%H
    local second_commit_hash=$output
    assert_equal "$first_commit_hash" "$second_commit_hash" "Commit hash should NOT change for ignored file"

    # Verify logs and commit history
    run git log --name-status --oneline
    assert_success
    assert_output --partial "file1.txt"
    refute_output --partial "file2.txt"

    run cat "$output_file"
    assert_output --partial "Change detected" # Should detect the change in file1.txt
    assert_output --partial "file1.txt"
    # Should *not* contain log lines specific to file2.txt commit process
    refute_output --partial "test_subdir/file2.txt" # Check verbose output too
}

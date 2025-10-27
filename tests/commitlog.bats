#!/usr/bin/env bats

# Load standard helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load custom helpers
load 'test_helper/custom_helpers.bash'
# Load setup/teardown
load 'startup-shutdown'

@test "commit_log_messages_working: -l flag includes diffstat in commit message" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/remote" &
    GITWATCH_PID=$!

    cd "$testdir/local/remote"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for the first commit
    wait_for_git_change 20 0.5 git log -1 --format=%H
    run git log -1 --format=%H # Get the first commit hash
    local first_commit_hash=$output

    echo "line2" >> file1.txt

    # Wait for the second commit (checking that the log hash changes)
    wait_for_git_change 20 0.5 git log -1 --format=%H

    run git log -1 --pretty=%B
    assert_success
    # Check that the commit message contains elements from the diff/log (-l flag)
    assert_output --partial "file1.txt" # File name should be present
    assert_output --partial "line2" # Added line might be present depending on diff-lines output
}

#!/usr/bin/env bats

# Load standard helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load custom helpers
load 'test_helper/custom-helpers'
# Load setup/teardown
load 'startup-shutdown'

@test "commit_command_single: Uses simple custom command output as commit message" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c "uname" "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!

    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1 # Allow gitwatch to potentially initialize
    echo "line1" >> file1.txt

    # Wait for the first commit hash to appear/change
    wait_for_git_change 20 0.5 git log -1 --format=%H

    # Now verify the commit message
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "$(uname)"
}

@test "commit_command_format: Uses complex custom command with substitutions" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c 'echo "$(uname) is the uname of this device, the time is $(date)"' "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!

    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for the commit hash to change
    wait_for_git_change 20 0.5 git log -1 --format=%H

    # Verify commit message
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "$(uname)"
    # Check for a component likely unique to the date command (e.g., year)
    assert_output --partial "$(date +%Y)"
}

@test "commit_command_overwrite: -c flag overrides -l, -L, -d flags" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c "uname" -l 123 -L 0 -d "+%Y" "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!

    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for the commit hash to change
    wait_for_git_change 20 0.5 git log -1 --format=%H

    # Verify commit message used uname and ignored others
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "$(uname)"
    refute_output --partial "file1.txt" # Should not be in commit msg due to -c override
    refute_output --partial "$(date +%Y)" # Should not be in commit msg due to -c override
}

#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

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

@test "commit_command_pipe_C: -c and -C flags pipe list of changed files to command" {
    local custom_cmd='while IFS= read -r file; do echo "Changed: $file"; done'

    # Start gitwatch with custom command and the pipe flag -C
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c "$custom_cmd" -C "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1

    # Stage two files
    echo "change 1" > file_a.txt
    echo "change 2" > file_b.txt

    # Wait for the commit hash to change
    wait_for_git_change 20 0.5 git log -1 --format=%H

    # Verify commit message contains both file names, confirming the pipe worked
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "Changed: file_a.txt"
    assert_output --partial "Changed: file_b.txt"

    cd /tmp
}

@test "commit_command_failure: -c failure uses fallback message and logs error" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    local failing_cmd='exit 1' # Simple command that fails

    # Start gitwatch with custom command that fails, logging all output
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin -c "$failing_cmd" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1 # Allow gitwatch to initialize

    # Trigger a change
    echo "line1" >> file_fail.txt

    # Wait for the commit hash to change (the commit should succeed with the fallback message)
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Commit timed out, suggesting the commit failed entirely"

    # 1. Verify commit message contains the fallback string
    run git log -1 --pretty=%B
    assert_success
    assert_output "Custom command failed" "Commit message should be the fallback text"

    # 2. Verify log output contains the error message
    run cat "$output_file"
    assert_success
    assert_output --partial "ERROR: Custom commit command '$failing_cmd' failed." "Log should contain the error from the failing custom command"

    cd /tmp
}

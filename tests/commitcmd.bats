#!/usr/bin/env bats

# Load bats-core helpers relative to the test file's location
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

# Load setup/teardown
load 'startup-shutdown'

@test "commit_command_single: Uses simple custom command output as commit message" {
    # Start up gitwatch with custom commit command
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c "uname" "$testdir/local/remote"
    assert_success # Check if gitwatch started without immediate error

    # Capture PID (assuming gitwatch runs in background - adjust if needed)
    GITWATCH_PID=$!
    disown # Prevent kill message on terminal

    cd "$testdir/local/remote"

    # Make a change
    sleep 1 # Allow watcher to initialize
    echo "line1" >> file1.txt

    # Wait for gitwatch to commit
    sleep "$WAITTIME"

    # Check commit log
    run git log -1 --pretty=%B # Get only the commit message body
    assert_success
    assert_output --partial "$(uname)"
}

@test "commit_command_format: Uses complex custom command with substitutions" {
    # tests nested commit command

    # Use single quotes for the outer argument to prevent premature expansion by test runner
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c 'echo "$(uname) is the uname of this device, the time is $(date)"' "$testdir/local/remote"
    assert_success
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"

    sleep 1
    echo "line1" >> file1.txt

    sleep "$WAITTIME"

    run git log -1 --pretty=%B
    assert_success
    # Check that both parts of the custom command executed correctly in the commit message
    assert_output --partial "$(uname)"
    assert_output --partial "$(date +%Y)" # Check for the current year as a proxy for date expansion
}

@test "commit_command_overwrite: -c flag overrides -l, -L, -d flags" {
    # Start up gitwatch with custom commit command and other formatting flags
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c "uname" -l 123 -L 0 -d "+%Y" "$testdir/local/remote"
    assert_success
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"

    sleep 1
    echo "line1" >> file1.txt

    sleep "$WAITTIME"

    run git log -1 --pretty=%B
    assert_success
    # Verify only the output of 'uname' is used, ignoring other flags
    assert_output --partial "$(uname)"
    refute_output --partial "file1.txt" # Should not contain diff log (-l/-L ignored)
    refute_output --partial "$(date +%Y)" # Should not contain date format (-d ignored)
}

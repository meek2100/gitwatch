#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'startup-shutdown'

@test "commit_command_single: Uses simple custom command output as commit message" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c "uname" "$testdir/local/remote" &
    GITWATCH_PID=$!

    cd "$testdir/local/remote"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for the commit to appear
    retry 20 0.5 "run git log -1 --pretty=%B"

    assert_success
    assert_output --partial "$(uname)"
}

@test "commit_command_format: Uses complex custom command with substitutions" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c 'echo "$(uname) is the uname of this device, the time is $(date)"' "$testdir/local/remote" &
    GITWATCH_PID=$!

    cd "$testdir/local/remote"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for the commit to appear
    retry 20 0.5 "run git log -1 --pretty=%B"

    assert_success
    assert_output --partial "$(uname)"
    assert_output --partial "$(date +%Y)"
}

@test "commit_command_overwrite: -c flag overrides -l, -L, -d flags" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c "uname" -l 123 -L 0 -d "+%Y" "$testdir/local/remote" &
    GITWATCH_PID=$!

    cd "$testdir/local/remote"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for the commit to appear
    retry 20 0.5 "run git log -1 --pretty=%B"

    assert_success
    assert_output --partial "$(uname)"
    refute_output --partial "file1.txt"
    refute_output --partial "$(date +%Y)"
}

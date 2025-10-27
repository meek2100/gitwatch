#!/usr/bin/env bats

load 'tests/test_helper/bats-support/load'
load 'tests/test_helper/bats-assert/load'
load 'tests/test_helper/bats-file/load'
load 'tests/startup-shutdown'

@test "commit_log_messages_working: -l flag includes diffstat in commit message" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/remote" &
    GITWATCH_PID=$!

    cd "$testdir/local/remote"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for the first commit
    retry 20 0.5 "run git log -1 --pretty=%B"
    local first_commit_hash=$output

    echo "line2" >> file1.txt

    # Wait for the second commit (checking that the log message is new)
    retry 20 0.5 "run git log -1 --pretty=%B | grep line2"

    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "file1.txt"
    assert_output --partial "line2"
}

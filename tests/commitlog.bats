#!/usr/bin/env bats
set -x

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'startup-shutdown'

@test "commit_log_messages_working: -l flag includes diffstat in commit message" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/remote" &
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"
    sleep 1
    echo "line1" >> file1.txt
    sleep "$WAITTIME"

    echo "line2" >> file1.txt
    sleep "$WAITTIME"

    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "file1.txt"
}

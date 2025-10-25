#!/usr/bin/env bats

# Load bats-core helpers relative to the test file's location
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

# Load setup/teardown
load 'startup-shutdown'

@test "commit_log_messages_working: -l flag includes diffstat in commit message" {
    # Start up gitwatch with logging enabled (-l 10 limits lines, but diffstat should show)
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/remote"
    assert_success
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"

    sleep 1
    echo "line1" >> file1.txt

    sleep "$WAITTIME" # Wait for first commit

    # Make a second change
    echo "line2" >> file1.txt
    sleep "$WAITTIME" # Wait for second commit

    # Check commit log that the diffstat (mentioning the file) is in the message body
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "file1.txt" # Check if the filename appears in the diffstat/log
}

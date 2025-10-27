#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'startup-shutdown-spaces'

@test "spaces_in_target_dir: Handles paths with spaces correctly" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/rem with spaces" &
    GITWATCH_PID=$!
    debug "Testdir with spaces: $testdir"

    cd "$testdir/local/rem with spaces"
    sleep 1
    echo "line1" >> "file with space.txt"

    # Wait for first commit
    retry 20 0.5 "run git log -1 --pretty=%B"

    echo "line2" >> "file with space.txt"

    # Wait for second commit (checking that the log contains "line2")
    retry 20 0.5 "run git log -1 --pretty=%B | grep line2"

    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "file with space.txt"
    assert_output --partial "line2"

    cd /tmp
}

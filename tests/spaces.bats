#!/usr/bin/env bats
set -x

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'startup-shutdown-spaces'

@test "spaces_in_target_dir: Handles paths with spaces correctly" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/rem with spaces" &
    GITWATCH_PID=$!
    disown
    debug "Testdir with spaces: $testdir"

    cd "$testdir/local/rem with spaces"
    sleep 1
    echo "line1" >> "file with space.txt"
    sleep "$WAITTIME"

    echo "line2" >> "file with space.txt"
    sleep "$WAITTIME"

    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "file with space.txt"

    cd /tmp
}

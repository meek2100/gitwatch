#!/usr/bin/env bats
set -x

# Load bats-core helpers relative to the test file's location
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

# Load setup/teardown for paths with spaces
load 'startup-shutdown-spaces'

@test "spaces_in_target_dir: Handles paths with spaces correctly" {
    # Directory to watch has spaces: "$testdir/local/rem with spaces"
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/rem with spaces"
    assert_success "gitwatch should start successfully with space in path"
    debug "Testdir with spaces: $testdir" # Use debug helper from bats-support
    GITWATCH_PID=$!
    disown

    # cd into the directory with spaces
    cd "$testdir/local/rem with spaces"

    sleep 1
    echo "line1" >> "file with space.txt" # Use a filename with spaces too
    sleep "$WAITTIME"

    # Make a new change
    echo "line2" >> "file with space.txt"
    sleep "$WAITTIME"

    # Check commit log that the diff is in there
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "file with space.txt" # Check if filename appears correctly
}

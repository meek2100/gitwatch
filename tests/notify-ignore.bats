#!/usr/bin/env bats
set -x

# Load bats-core helpers relative to the test file's location
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

# Load setup/teardown
load 'startup-shutdown'

# Test for exclude from notifications using -x flag.
@test "notify_ignore: -x ignores changes in specified subdirectory" {

    # Start up gitwatch, excluding test_subdir, redirect output for inspection
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -x "test_subdir/" "$testdir/local/remote" > "$output_file" 2>&1
    assert_success
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"
    mkdir test_subdir

    sleep 1 # Wait for watcher setup

    # Create a file that *should* be detected
    echo "line1" >> file1.txt
    sleep "$WAITTIME" # Wait for commit

    # Create a file that *should be ignored*
    echo "line2" >> test_subdir/file2.txt
    sleep "$WAITTIME" # Wait (no commit should happen for file2)

    # Check the git log
    run git log --name-status --oneline
    assert_success
    assert_output --partial "file1.txt" # file1 should be in the commit history
    refute_output --partial "file2.txt" # file2 should NOT be in the commit history

    # Optionally, check gitwatch's verbose output file too
    run cat "$output_file"
    assert_output --partial "Change detected" # Ensure some changes were seen
    assert_output --partial "file1.txt" # file1 changes should be logged
    refute_output --partial "file2.txt" # file2 changes should NOT be logged as triggering events
}

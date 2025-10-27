#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'startup-shutdown'

@test "notify_ignore: -x ignores changes in specified subdirectory" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -x "test_subdir/" "$testdir/local/remote" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"
    mkdir test_subdir
    sleep 1

    echo "line1" >> file1.txt
    sleep "$WAITTIME"

    echo "line2" >> test_subdir/file2.txt
    sleep "$WAITTIME"

    run git log --name-status --oneline
    assert_success
    assert_output --partial "file1.txt"
    refute_output --partial "file2.txt"

    run cat "$output_file"
    assert_output --partial "Change detected"
    assert_output --partial "file1.txt"
    refute_output --partial "file2.txt"
}

#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'startup-shutdown'

@test "commit_only_when_git_status_change: Does not commit if only timestamp changes (touch)" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/remote" > "$output_file" 2>&1 &
    GITWATCH_PID=$!

    cd "$testdir/local/remote"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for the first (allowed) commit
    retry 20 0.5 "run git rev-parse HEAD"
    assert_success
    local first_commit_hash=$output

    touch file1.txt
    # This is a negative test: wait to ensure a commit *does not* happen
    sleep "$WAITTIME"

    run git rev-parse HEAD
    assert_success
    local second_commit_hash=$output

    assert_equal "$first_commit_hash" "$second_commit_hash"

    run cat "$output_file"
    assert_output --partial "No tracked changes detected."
    local commit_count
    # Count lines containing "Running git commit command:"
    commit_count=$(grep -c "Running git commit command:" "$output_file")
    assert_equal "$commit_count" "1"

    cd /tmp
}

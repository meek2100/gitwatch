#!/usr/bin/env bats
set -x

# Load bats-core helpers relative to the test file's location
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

# Load setup/teardown
load 'startup-shutdown'

@test "commit_only_when_git_status_change: Does not commit if only timestamp changes (touch)" {

    # Start up gitwatch, capture output
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/remote" > "$output_file" 2>&1
    assert_success
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"

    # Create a file and wait for the first commit
    sleep 1
    echo "line1" >> file1.txt
    sleep "$WAITTIME"

    # Get the commit hash after the first change
    run git rev-parse HEAD
    assert_success
    local first_commit_hash=$output

    # Touch the file (changes timestamp but not content)
    touch file1.txt
    sleep "$WAITTIME" # Wait to see if gitwatch commits again

    # Get the commit hash again
    run git rev-parse HEAD
    assert_success
    local second_commit_hash=$output

    # Verify the commit hash HAS NOT changed
    assert_equal "$first_commit_hash" "$second_commit_hash"

    # Verify verbose output indicates no commit happened for the touch event
    run cat "$output_file"
    # Expect "No tracked changes detected" after the touch, not another commit message
    assert_output --partial "No tracked changes detected."
    # Count occurrences of commit messages vs no-change messages (more advanced check)
    local commit_count
    commit_count=$(grep -c "Running git commit" "$output_file")
    assert_equal "$commit_count" "1" # Only the first commit should have happened
}

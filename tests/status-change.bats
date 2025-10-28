#!/usr/bin/env bats

# Load standard helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load custom helpers
load 'test_helper/custom_helpers'
# Load setup/teardown
load 'startup-shutdown'

@test "commit_only_when_git_status_change: Does not commit if only timestamp changes (touch)" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")
    # Start gitwatch directly in the background, redirecting output
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1
    echo "line1" >> file1.txt

    # Use 'run' explicitly before wait_for_git_change
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "First commit failed to appear"
    # Now get the hash *after* the wait succeeded
    local first_commit_hash
    first_commit_hash=$(git log -1 --format=%H)

    # Touch the file (changes timestamp but not content recognized by git status)
    touch file1.txt
    # This is a negative test: wait to ensure a commit *does not* happen
    sleep "$WAITTIME" # Use WAITTIME from setup


    # Verify commit hash has NOT changed
    run git log -1 --format=%H
    assert_success
    local second_commit_hash=$output
    assert_equal "$first_commit_hash" "$second_commit_hash" "Commit occurred after touch, but shouldn't have"

    # Verify verbose output indicates no changes were detected by the final diff check
    run cat "$output_file"
    # *** UPDATED ASSERTION MESSAGE ***
    assert_output --partial "No actual changes staged for commit after git add."
    # Verify only one commit command was run
    local commit_count
    # Count lines containing "Running git commit command:" in the log
    commit_count=$(grep -c "Running git commit command:" "$output_file") # grep is okay in tests
    assert_equal "$commit_count" "1" # Only the initial commit should have run

    cd /tmp
}

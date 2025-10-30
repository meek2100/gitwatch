#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "commit_only_when_git_status_change: Does not commit if only timestamp changes (touch)" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    ## NEW ##
    echo "# DEBUG: Starting gitwatch, log at $output_file" >&3

    # Start gitwatch directly in the background, redirecting output
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1

    ## NEW ##
    echo "# DEBUG: Creating first change (echo 'line1')" >&3
    echo "line1" >> file1.txt

    # Use 'run' explicitly before wait_for_git_change
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "First commit failed to appear"

    # Now get the hash *after* the wait succeeded
    local first_commit_hash
    first_commit_hash=$(git log -1 --format=%H)

    ## NEW ##
    echo "# DEBUG: First commit hash is $first_commit_hash" >&3
    echo "# DEBUG: --- Log content AFTER first commit ---" >&3
    cat "$output_file" >&3
    echo "# DEBUG: --- End log content ---" >&3

    # Touch the file (changes timestamp but not content recognized by git status)
    ## NEW ##
    echo "# DEBUG: Touching file (touch file1.txt)" >&3
    touch file1.txt

    # This is a negative test: wait to ensure a commit *does not* happen
    ## NEW ##
    echo "# DEBUG: Sleeping for $WAITTIME seconds to wait for *no* commit..." >&3
    sleep "$WAITTIME" # Use WAITTIME from setup


    # Verify commit hash has NOT changed
    run git log -1 --format=%H
    assert_success
    local second_commit_hash=$output

    ## NEW ##
    echo "# DEBUG: Second commit hash is $second_commit_hash" >&3
    assert_equal "$first_commit_hash" "$second_commit_hash" "Commit occurred after touch, but shouldn't have"

    ## NEW ##
    echo "# DEBUG: --- Log content AFTER touch + sleep ---" >&3
    cat "$output_file" >&3
    echo "# DEBUG: --- End log content ---" >&3

    # Verify verbose output indicates no changes were detected by the final diff check
    run cat "$output_file"
    assert_output --partial "No relevant changes detected by git status (porcelain check)."

    # Verify only one commit command was run
    #local commit_count

    # --- OLD: Verify via log count (Flaky) ---
    # echo "# DEBUG: Grepping log file for 'Running git commit command:'" >&3
    # Count lines containing "Running git commit command:" in the log
    # commit_count=$(grep -c "Running git commit command:" "$output_file")
    # echo "# DEBUG: Commit count found: $commit_count" >&3
    # assert_equal "$commit_count" "1" # Only the initial commit should have run

    # --- NEW: Verify commit history directly (Robust) ---
    # --- Verify commit history directly ---
    echo "# DEBUG: Verifying total commit count using git rev-list" >&3
    # Count total commits: Initial commit (1) + commit from 'echo line1' (1) = 2
    run git rev-list --count HEAD
    assert_success "Failed to count commits"
    local expected_commit_count=2
    echo "# DEBUG: Expected commit count: $expected_commit_count, Actual found: $output" >&3
    assert_equal "$output" "$expected_commit_count" "Expected $expected_commit_count commits in history (setup + echo), but found $output. Commit happened after touch."
    # --- End NEW ---

     cd /tmp
 }

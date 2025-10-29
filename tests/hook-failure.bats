#!/usr/bin/env bats

# Load standard helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load custom helpers
load 'test_helper/custom-helpers'
# Load setup/teardown
load 'startup-shutdown'

@test "hook_failure: Git commit hook failure is handled gracefully" {
    local output_file
    local git_dir_path
    local initial_commit_hash

    # Create a temporary file to capture gitwatch output
    output_file=$(mktemp "$testdir/output.XXXXX")

    # Start gitwatch in the background with verbose logging
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!

    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1 # Allow watcher to initialize

    # 1. Get the initial commit hash from the setup
    initial_commit_hash=$(git log -1 --format=%H)

    # 2. Install a failing pre-commit hook
    # Use git rev-parse to reliably locate the hooks directory
    git_dir_path=$(git rev-parse --git-path hooks)
    local hook_file="$git_dir_path/pre-commit"

    echo "#!/bin/bash" > "$hook_file"
    echo "echo 'Hook failed: Commits are disabled for this test.'" >> "$hook_file"
    echo "exit 1" >> "$hook_file"
    chmod +x "$hook_file"
    echo "# DEBUG: Installed failing hook at $hook_file" >&3

    # --- FIRST CHANGE (Failure Expected) ---
    echo "line1" >> file1.txt
    echo "# DEBUG: Waiting $WAITTIME seconds for hook failure attempt..." >&3

    # Wait for the commit attempt to finish
    sleep "$WAITTIME"

    # Verify commit hash has NOT changed (Failure Assertion)
    run git log -1 --format=%H
    assert_success
    local first_attempt_hash=$output
    assert_equal "$initial_commit_hash" "$first_attempt_hash" "Commit hash should NOT change due to hook failure"

    # Verify log output shows the expected error message (Logging Assertion)
    run cat "$output_file"
    assert_output --partial "ERROR: 'git commit' failed with exit code 1." "Should log the commit failure error"
    assert_output --partial "Hook failed: Commits are disabled for this test." "Should log the hook failure output"

    # 3. Clean up the hook to allow the next commit (Recovery Preparation)
    run rm -f "$hook_file"
    assert_success "Failed to remove the hook file"
    echo "# DEBUG: Hook removed. Ready for success test." >&3

    # --- SECOND CHANGE (Success Expected - Proves Recovery) ---
    echo "line2" >> file2.txt

    # Wait for the successful commit to appear (Recovery Assertion)
    # If the commit lock was not released on failure, this will time out.
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Second commit (after hook removal) failed to appear, implying lock/debounce was stuck"

    # Verify commit hash HAS changed
    run git log -1 --format=%H
    assert_success
    local second_attempt_hash=$output
    assert_not_equal "$first_attempt_hash" "$second_attempt_hash" "Commit hash MUST change after successful commit"

    cd /tmp
}

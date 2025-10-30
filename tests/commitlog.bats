#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "commit_log_messages_working: -l flag includes diffstat in commit message" {
    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for the first commit
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "First commit timed out"
    local first_commit_hash
    first_commit_hash=$(git log -1 --format=%H) # Get hash after wait succeeds

    echo "line2" >> file1.txt
    # *** INCREASED DELAY ***
    sleep 0.5 # Give FS/Git a bit more time to settle before waiting

    # Wait for the second commit (checking that the log hash changes)
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Second commit timed out" # Use run for assert_success

    run git log -1 --pretty=%B
    assert_success
    # Check that the commit message contains elements from the diff/log (-l flag)
    assert_output --partial "file1.txt" # File name should be present
    assert_output --partial "line2"     # Added line should be present
}

@test "commit_log_truncation: -l flag truncates long diffs and uses summary" {
    local max_lines=5
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    # Start gitwatch directly in the background with a low line limit
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l "$max_lines" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1

    # Get initial hash
    local initial_hash
    initial_hash=$(git log -1 --format=%H)

    # Generate 10 lines of content (which should exceed the max_lines=5 limit)
    local expected_total_lines=10
    for i in $(seq 1 $expected_total_lines); do
        echo "Line number $i" >> long_file.txt
    done

    # Wait for commit
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Commit timed out"
    assert_not_equal "$initial_hash" "$output" "Commit hash did not change"

    # Verify commit message: Should contain the summary, not the full diff lines
    run git log -1 --pretty=%B
    assert_success

    # 1. Assert that the summary message is present (e.g., Too many lines changed...)
    assert_output --partial "Too many lines changed"

    # 2. Assert that the file status (diff --stat) summary is present
    assert_output --partial "long_file.txt | 10"

    # 3. Assert that the detailed diff line content is NOT present
    refute_output --partial "Line number 6" "Full diff line should have been truncated"

    cd /tmp
}

# --- NEW TEST ---
@test "commit_log_mode_change: -l flag logs file mode changes" {
    cd "$testdir/local/$TEST_SUBDIR_NAME"

    # 1. Create a file and commit it
    local script_file="mode_test.sh"
    echo "#!/bin/bash" > "$script_file"
    git add "$script_file"
    git commit -q -m "Add script file"
    local initial_hash
    initial_hash=$(git log -1 --format=%H)

    # 2. Start gitwatch with -l
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    sleep 1 # Allow watcher to initialize

    # 3. Change the file mode
    chmod +x "$script_file"

    # 4. Wait for the new commit to appear
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Commit for mode change timed out"
    assert_not_equal "$initial_hash" "$output" "Commit hash did not change"

    # 5. Verify the commit message contains the mode change string
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "$script_file:?: Mode changed to 100755" \
        "Commit message did not contain the expected mode change string"

    cd /tmp
}

# --- NEW TEST ---
@test "commit_log_no_color_L: -L flag includes plain diffstat" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    # Start gitwatch with -L (no color)
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -L 10 "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1

    # Get initial hash
    local initial_hash
    initial_hash=$(git log -1 --format=%H)

    # Make a change
    echo "A new line for the no-color test" >> file_L_test.txt

    # Wait for commit
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Commit timed out for -L test"
    assert_not_equal "$initial_hash" "$output" "Commit hash did not change"

    # Verify commit message
    run git log -1 --pretty=%B
    assert_success

    # 1. Assert the content is present
    assert_output --partial "file_L_test.txt:1: +A new line for the no-color test"

    # 2. Assert NO ANSI color codes are present (the real test)
    # This grep will fail if it finds the escape character \x1B (or \033)
    refute_output --regexp $'\x1B' "Commit message should not contain ANSI escape codes"

    cd /tmp
}

# --- NEW TEST (Gap 2) ---
@test "commit_log_env_var_override: GW_LOG_LINE_LENGTH overrides default" {
    # 1. Set a short, custom line length
    export GW_LOG_LINE_LENGTH=10

    local long_line="This line is definitely longer than 10 characters"
    local truncated_line="This line " # The first 10 chars
    local initial_hash

    # 2. Start gitwatch. We use -l 0 to prove the env var overrides the flag logic's default.
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 0 "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1

    initial_hash=$(git log -1 --format=%H)

    # 3. Create a file with the long line
    echo "$long_line" >> env_var_test.txt

    # 4. Wait for the commit
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Commit timed out"
    assert_not_equal "$initial_hash" "$output" "Commit hash did not change"

    # 5. Verify the commit message contains the *truncated* line
    run git log -1 --pretty=%B
    assert_success

    # Assert that the truncated line is present (with the '+' from diff-lines)
    assert_output --partial "+${truncated_line}"

    # Assert that the *full* line is *not* present
    refute_output --partial "+${long_line}"

    # 6. Cleanup
    unset GW_LOG_LINE_LENGTH
    cd /tmp
}

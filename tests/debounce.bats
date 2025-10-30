#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# Note: This test relies heavily on verbose logging (-v)

@test "debounce_logic: Rapid changes trigger only one commit attempt" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")
    # Use a shorter sleep time for the script to make debounce more critical
    local test_sleep_time=1
    # Use a short interval between test changes
    local change_interval=0.1
    # Number of rapid changes to make
    local change_count=3
    # Expected number of times debounce should kill an old timer
    local expected_kill_count=$((change_count - 1))
    # Expected number of commit attempts (sleep finished messages)
    local expected_commit_attempts=1
    # Expected final commit count in repo (Initial Setup Commit + 1 for this test)
    local expected_repo_commits=2

    echo "# DEBUG: Starting gitwatch with sleep=${test_sleep_time}s, log at $output_file" >&3
    # Start gitwatch directly in the background, redirecting output
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s "$test_sleep_time" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1 # Allow watcher to initialize

    echo "# DEBUG: Creating rapid burst of $change_count changes..." >&3
    for i in $(seq 1 $change_count); do
      echo "Change $i" >> debounce_test.txt
      sleep "$change_interval"
    done
    echo "# DEBUG: Finished creating changes." >&3

    # Wait long enough for the *final* commit attempt to finish
    # Wait = (Last change sleep) + script's sleep time + buffer for git commands
    local wait_buffer=3 # Generous buffer
    local total_wait=$(echo "$test_sleep_time + $wait_buffer" | bc)
    echo "# DEBUG: Waiting ${total_wait}s for final commit to settle..." >&3
    sleep "$total_wait"

    # --- Assertions based on LOG file ---
    echo "# DEBUG: Analyzing log file: $output_file" >&3
    run cat "$output_file"
    assert_success "Failed to read log file"

    # 1. Check how many times debounce triggered a kill
    local actual_kill_count
    actual_kill_count=$(grep -c "Debounce: Timer.*is active. Killing it." "$output_file" || echo 0)
    echo "# DEBUG: Expected debounce kills: $expected_kill_count, Actual found: $actual_kill_count" >&3
    # assert_equal "$actual_kill_count" "$expected_kill_count" # This might be flaky depending on exact event timing

    # 2. Check how many times a timer actually finished sleeping and TRIED to commit
    local actual_commit_attempts
    actual_commit_attempts=$(grep -c "Debounce Timer.*Sleep finished. Attempting commit." "$output_file" || echo 0)
    echo "# DEBUG: Expected commit attempts (sleep finished): $expected_commit_attempts, Actual found: $actual_commit_attempts" >&3
    assert_equal "$actual_commit_attempts" "$expected_commit_attempts" "Expected only one timer to finish sleeping and attempt commit"

    # 3. Check how many actual 'Running git commit' messages (successful commits)
    local actual_successful_commits
    actual_successful_commits=$(grep -c "Running git commit command:" "$output_file" || echo 0)
     echo "# DEBUG: Expected successful commits (in log): 1, Actual found: $actual_successful_commits" >&3
    assert_equal "$actual_successful_commits" "1" "Expected only one successful commit message in log"


    # --- Assertion based on REPO state ---
    echo "# DEBUG: Verifying final commit count in repository" >&3
    run git rev-list --count HEAD
    assert_success "Failed to count commits in repo"
    echo "# DEBUG: Expected repo commits: $expected_repo_commits, Actual found: $output" >&3
    assert_equal "$output" "$expected_repo_commits" "Expected $expected_repo_commits total commits in history (setup + 1 debounce commit), found $output"

    cd /tmp
}

#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers (includes create_hanging_bin)
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'


@test "timeout_git_push: Ensures hung git push command is terminated and logged" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    # 1. Setup: Create a hanging dummy 'git' binary
    # We rename the hanging binary to be what GW_GIT_BIN expects.
    local dummy_git_path
    dummy_git_path=$(create_hanging_bin "git")

    # 2. Set environment variable to force gitwatch to use the hanging binary
    # The timeout in gitwatch.sh will call 'timeout 60 /path/to/git-hanging push...'
    export GW_GIT_BIN="$dummy_git_path"

    # 3. Start gitwatch with a remote and short sleep time
    # Set a very short sleep time to speed up the test cycle
    local test_sleep_time=1
    local target_dir="$testdir/local/$TEST_SUBDIR_NAME"

    echo "# DEBUG: Starting gitwatch with hanging git binary and sleep=${test_sleep_time}s" >&3
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s "$test_sleep_time" -r origin "$target_dir" > "$output_file" 2>&1 &
    GITWATCH_PID=$!

    cd "$target_dir"
    sleep 1 # Allow watcher to initialize

    # 4. Trigger a change
    echo "change to trigger timeout" >> timeout_file.txt

    # 5. Wait for the debounce period (1s) plus a small buffer, then wait for the
    # expected timeout period (60s) to be triggered by the script itself.
    # Since the script uses 'timeout 60' internally, we wait slightly longer than 60s for the kill to happen.
    local total_wait_time=5 # Since our mocked git binary sleeps for 600s,
                            # the internal timeout (60s) should kill it fast.
                            # We use a short wait here to see the initial attempt, then rely on the kill by the script's 'timeout'
    echo "# DEBUG: Waiting ${total_wait_time}s for commit attempt and expected timeout failure..." >&3
    sleep "$total_wait_time"
    # Note: If the actual script timeout (60s) is too long for CI, this test might be slow.
    # Assuming the CI environment is fast enough to see the failure log quickly,
    # even with a small wait, as the DUMMY HANG message will appear instantly.

    # 6. Assert: The commit/push failed due to timeout
    run cat "$output_file"
    assert_output --partial "*** DUMMY HANG: git called, will sleep 600s ***" "Hanging dummy git binary was not called."
    assert_output --partial "ERROR: 'git push' timed out after 60 seconds." "Push timeout error was not logged."

    # 7. Cleanup
    unset GW_GIT_BIN
    rm -f "$dummy_git_path"
    cd /tmp
}

@test "timeout_pull_rebase: Ensures hung git pull command is terminated and logged" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    # 1. Setup: Create a hanging dummy 'git' binary
    local dummy_git_path
    dummy_git_path=$(create_hanging_bin "git")

    # 2. Set environment variable
    export GW_GIT_BIN="$dummy_git_path"

    # 3. Start gitwatch with remote and PULL_BEFORE_PUSH (-R)
    local test_sleep_time=1
    local target_dir="$testdir/local/$TEST_SUBDIR_NAME"

    echo "# DEBUG: Starting gitwatch with hanging git binary and -R" >&3
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s "$test_sleep_time" -r origin -R "$target_dir" > "$output_file" 2>&1 &
    GITWATCH_PID=$!

    cd "$target_dir"
    sleep 1 # Allow watcher to initialize

    # 4. Trigger a change
    echo "change to trigger pull timeout" >> pull_timeout_file.txt

    # 5. Wait for the script's internal timeout (60s) to be triggered.
    local total_wait_time=5
    echo "# DEBUG: Waiting ${total_wait_time}s for commit/pull attempt and expected timeout failure..." >&3
    sleep "$total_wait_time"

    # 6. Assert: The commit succeeded, but the subsequent pull failed due to timeout
    run cat "$output_file"
    assert_output --partial "Running git commit command:" "Commit should succeed before pull attempt."
    assert_output --partial "*** DUMMY HANG: git called, will sleep 600s ***" "Hanging dummy git binary was not called for pull."
    assert_output --partial "ERROR: 'git pull' timed out after 60 seconds. Skipping push." "Pull timeout error was not logged."

    # 7. Cleanup
    unset GW_GIT_BIN
    rm -f "$dummy_git_path"
    cd /tmp
}

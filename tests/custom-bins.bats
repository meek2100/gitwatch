#!/usr/bin/env bats

# Load standard helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load custom helpers
load 'test_helper/custom_helpers'
# Load setup/teardown
load 'startup-shutdown'

# Helper function to create a dummy binary
create_dummy_bin() {
    local name="$1"
    local real_path="$2"
    local signature="$3"
    local dummy_path="$testdir/bin/$name"

    echo "#!/usr/bin/env bash" > "$dummy_path"
    echo "echo \"*** DUMMY BIN: $signature ***\" >&2" >> "$dummy_path"
    # Execute the real binary with all arguments
    echo "exec $real_path \"\$@\"" >> "$dummy_path"
    chmod +x "$dummy_path"
    echo "$dummy_path"
}

@test "custom_bins_env_vars: Uses GW_GIT_BIN, GW_INW_BIN, GW_FLOCK_BIN if set" {
    # Skip if running on macOS as fswatch replacement is more complex
    if [ "$RUNNER_OS" == "macOS" ]; then
        skip "Custom bins test skipped: requires Linux environment for simple inotifywait setup."
    fi

    mkdir "$testdir/bin"

    # 1. Create dummy binaries
    local real_git_path
    real_git_path=$(command -v git)
    local dummy_git=$(create_dummy_bin "git" "$real_git_path" "GIT_OK")

    local real_inw_path
    real_inw_path=$(command -v inotifywait)
    local dummy_inw=$(create_dummy_bin "inotifywait" "$real_inw_path" "INW_OK")

    local real_flock_path
    real_flock_path=$(command -v flock)
    local dummy_flock=$(create_dummy_bin "flock" "$real_flock_path" "FLOCK_OK")

    # 2. Set environment variables
    export GW_GIT_BIN="$dummy_git"
    export GW_INW_BIN="$dummy_inw"
    export GW_FLOCK_BIN="$dummy_flock"

    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    # 3. Start gitwatch (should use the dummy binaries)
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1

    # 4. Trigger a change and wait for commit
    echo "change_for_dummy" >> file_dummy.txt
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Commit timed out, suggesting dummy git/inw failed"

    # 5. Assert: Check output for signature messages (which go to STDERR/STDOUT)
    run cat "$output_file"
    assert_output --partial "*** DUMMY BIN: GIT_OK ***" "Dummy Git command was not executed or its message not captured"
    assert_output --partial "*** DUMMY BIN: INW_OK ***" "Dummy Inotifywait command was not executed or its message not captured"
    assert_output --partial "*** DUMMY BIN: FLOCK_OK ***" "Dummy Flock command was not executed or its message not captured"

    # 6. Cleanup environment variables for next test
    unset GW_GIT_BIN
    unset GW_INW_BIN
    unset GW_FLOCK_BIN
    cd /tmp
}

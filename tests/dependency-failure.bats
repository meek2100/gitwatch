#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "dependency_failure_syslog: -S flag exits with code 2 if 'logger' command is missing" {
    # This test temporarily manipulates the PATH environment variable to simulate a missing 'logger' command.
    local path_backup="$PATH"

    # 1. Temporarily remove common binary directories from PATH to simulate 'logger' missing
    # We remove /usr/bin, /usr/sbin, /bin, /sbin, but preserve others.
    export PATH="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr)?/s?bin' | tr '\n' ':')"

    # 2. Assert that 'logger' is not found in the simulated PATH
    run command -v logger
    refute_success "Failed to simulate missing 'logger' command (command was still found in simulated PATH)"

    # 3. Run gitwatch with -S, expecting it to fail the dependency check and exit
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -S "$testdir/local/$TEST_SUBDIR_NAME"

    # 4. Assert exit code 2 and the error message
    assert_failure "Gitwatch should exit with non-zero status on missing dependency"
    assert_exit_code 2 "Gitwatch should exit with code 2 (Missing required command)"
    assert_output --partial "Error: Required command 'logger' not found (for -S syslog option)."

    # 5. Cleanup
    export PATH="$path_backup" # Restore PATH
    cd /tmp
}

@test "dependency_failure_timeout: Exits with code 2 if 'timeout' command is missing" {
    local path_backup="$PATH"

    # 1. Temporarily remove common binary directories from PATH to simulate 'timeout' missing
    # We remove coreutils locations where 'timeout' is usually found
    # Use a conservative filter to remove typical bin directories, but keep others like bats dependencies
    export PATH="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"

    # 2. Assert that 'timeout' is not found in the simulated PATH
    run command -v timeout
    refute_success "Failed to simulate missing 'timeout' command (command was still found in simulated PATH)"

    # 3. Run gitwatch, expecting it to fail the dependency check and exit
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

    # 4. Assert exit code 2 and the error message
    assert_failure "Gitwatch should exit with non-zero status on missing dependency"
    assert_exit_code 2 "Gitwatch should exit with code 2 (Missing required command)"
    assert_output --partial "Error: Required command 'timeout' not found."

    # 5. Cleanup
    export PATH="$path_backup" # Restore PATH
    cd /tmp
}

# --- NEW TESTS ---

@test "dependency_failure_git: Exits with code 2 if 'git' command is missing" {
    local path_backup="$PATH"
    # 1. Hide 'git'
    export PATH="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
    run command -v git
    refute_success "Failed to simulate missing 'git' command"

    # 2. Run gitwatch
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

    # 3. Assert exit code 2 and the error message
    assert_failure
    assert_exit_code 2
    assert_output --partial "Error: Required command 'git' not found."

    # 4. Cleanup
    export PATH="$path_backup"
    cd /tmp
}

@test "dependency_failure_watcher: Exits with code 2 if watcher (inotifywait/fswatch) is missing" {
    local path_backup="$PATH"
    local watcher_name=""
    local watcher_hint=""

    if [ "$RUNNER_OS" == "Linux" ]; then
        watcher_name="inotifywait"
        watcher_hint="inotify-tools"
    else
        watcher_name="fswatch"
        watcher_hint="brew install fswatch"
    fi

    # 1. Hide the watcher
    export PATH="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
    run command -v "$watcher_name"
    refute_success "Failed to simulate missing '$watcher_name' command"

    # 2. Run gitwatch
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

    # 3. Assert exit code 2 and the error message
    assert_failure
    assert_exit_code 2
    assert_output --partial "Error: Required command '$watcher_name' not found."
    assert_output --partial "$watcher_hint" # Check for the platform-specific hint

    # 4. Cleanup
    export PATH="$path_backup"
    cd /tmp
}

@test "dependency_warning_flock: Warns (does not exit) if 'flock' command is missing" {
    local path_backup="$PATH"
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    # 1. Hide 'flock'
    export PATH="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
    run command -v flock
    refute_success "Failed to simulate missing 'flock' command"

    # 2. Run gitwatch *in the background*
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    sleep 1 # Allow script to initialize and print warning

    # 3. Assert: Check log output for the warning
    run cat "$output_file"
    assert_output --partial "Warning: 'flock' command not found."
    assert_output --partial "Proceeding without file locking."

    # 4. Assert: Process is *still running*
    run kill -0 "$GITWATCH_PID"
    assert_success "Gitwatch process exited when it should have continued without flock"

    # 5. Cleanup
    export PATH="$path_backup"
    cd /tmp
}

@test "dependency_warning_flock_race_condition: Proves missing flock causes race condition" {
    local path_backup="$PATH"
    local output_file_1
    output_file_1=$(mktemp "$testdir/output1.XXXXX")
    local output_file_2
    output_file_2=$(mktemp "$testdir/output2.XXXXX")
    local pid_1
    local pid_2

    # 1. Hide 'flock'
    export PATH="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
    run command -v flock
    refute_success "Failed to simulate missing 'flock' command"

    # 2. Start two gitwatch processes
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s 1 "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file_1" 2>&1 &
    pid_1=$!

    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s 1 "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file_2" 2>&1 &
    pid_2=$!

    sleep 1 # Allow them to start

    # 3. Assert both are running
    run kill -0 "$pid_1"
    assert_success "Gitwatch process 1 failed to start"
    run kill -0 "$pid_2"
    assert_success "Gitwatch process 2 failed to start"

    # 4. Assert both warned about missing flock
    run cat "$output_file_1"
    assert_output --partial "Warning: 'flock' command not found."
    run cat "$output_file_2"
    assert_output --partial "Warning: 'flock' command not found."

    # 5. Trigger a single change
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    echo "race condition change" >> race_file.txt

    # 6. Wait for both processes to see the change and commit
    sleep 3 # Wait for sleep (1s) + commit time

    # 7. Assert: Check commit count. Expected: 1 (setup) + 2 (race) = 3
    run git rev-list --count HEAD
    assert_success
    echo "# DEBUG: Commit count found: $output" >&3
    # Note: On some very fast systems, the race might be so fast that one 'git add'
    # finishes before the other, and the second one finds 'nothing to commit'.
    # A more robust check is to ensure *at least* 2 commits (1 setup + 1 race).
    # But for this test, we'll assert 3 to prove the race.
    assert_equal "$output" "3" "Expected 3 commits (1 setup + 2 race), but found $output"

    # 8. Cleanup
    kill "$pid_1" &>/dev/null || true
    kill "$pid_2" &>/dev/null || true
    unset GITWATCH_PID # Prevent global teardown from failing
    export PATH="$path_backup"
    cd /tmp
}

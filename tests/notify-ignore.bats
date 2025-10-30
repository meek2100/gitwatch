#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "notify_ignore_subdir: -x ignores changes in specified subdirectory" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")
    # Start gitwatch directly in the background, ignoring test_subdir/
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -x "test_subdir/" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    mkdir test_subdir
    sleep 1

    echo "line1" >> file1.txt
    # Wait for the first (allowed) commit to appear
    wait_for_git_change 20 0.5 git log -1 --format=%H
    run git log -1 --format=%H # Get the first commit hash
    local first_commit_hash=$output

    echo "line2" >> test_subdir/file2.txt
    # This is a negative test: wait to ensure a commit *does not* happen
    sleep "$WAITTIME" # Use WAITTIME from setup

    run git log -1 --format=%H
    local second_commit_hash=$output
    assert_equal "$first_commit_hash" "$second_commit_hash" "Commit hash should NOT change for ignored subdirectory"

    # Verify logs and commit history
    run git log --name-status --oneline
    assert_success
    assert_output --partial "file1.txt"
    refute_output --partial "file2.txt"

    run cat "$output_file"
    assert_output --partial "Change detected" # Should detect the change in file1.txt
    assert_output --partial "file1.txt"
    # Should not contain log lines specific to file2.txt commit process
    refute_output --partial "test_subdir/file2.txt"
}

@test "notify_ignore_glob: -x ignores files matching glob patterns" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    # Test case 1: *.tmp (glob star and dot escaping) -> regex ".*\.tmp"
    local exclude_regex_glob=".*\.tmp"
    local initial_hash

    # Start gitwatch, ignoring files ending in .tmp
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -x "$exclude_regex_glob" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1

    # Allowed change
    echo "line1" >> allowed.txt
    wait_for_git_change 20 0.5 git log -1 --format=%H
    run git log -1 --format=%H
    initial_hash=$output

    # Ignored change
    echo "temp data" >> ignored_file.tmp
    sleep "$WAITTIME" # Wait for no commit

    # Assert no change
    run git log -1 --format=%H
    assert_equal "$initial_hash" "$output" "Commit occurred for ignored glob pattern file"

    # Test case 2: exact match with period (period escaping)
    # Note: This is an additive test. We rely on the initial file being created
    # and the hash check from the previous sub-test still being valid, or we restart.

    # We must stop the current gitwatch process before starting a new one with a different -x flag
    _common_teardown

    # Create a new output file
    local output_file_2
    output_file_2=$(mktemp "$testdir/output2.XXXXX")

    # Start gitwatch, ignoring files named exactly "config.ini" (regex: config\.ini)
    local exclude_regex_period="config\.ini"
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -x "$exclude_regex_period" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file_2" 2>&1 &
    GITWATCH_PID=$!
    sleep 1

    # Allowed change (new file)
    echo "another allowed" > allowed2.txt
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Second commit failed to appear"
    run git log -1 --format=%H
    local second_commit_hash=$output

    # Ignored change
    echo "ini data" >> config.ini
    sleep "$WAITTIME" # Wait for no commit

    # Assert no change
    run git log -1 --format=%H
    assert_equal "$second_commit_hash" "$output" "Commit occurred for ignored exact file name with period"
}

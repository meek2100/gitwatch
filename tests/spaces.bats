#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown specific for paths with spaces
load 'bats-custom/startup-shutdown'

# Override the default setup for this test file
setup() {
    setup_with_spaces
}

@test "spaces_in_target_dir: Handles paths with spaces correctly" {
    # Start gitwatch directly in the background - paths need careful quoting
    # BATS_TEST_DIRNAME should handle spaces if the script itself is in such a path
    # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    echo "# Testdir with spaces: $testdir" >&3
    echo "# Local clone dir: $testdir/local/$TEST_SUBDIR_NAME" >&3

    cd "$testdir/local/$TEST_SUBDIR_NAME" # cd into the directory with spaces
    sleep 1
    echo "line1" >> "file with space.txt" # Modify file with space

    # *** Use 'run' explicitly before wait_for_git_change ***
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "First commit timed out"
    # Now get the hash *after* the wait succeeded
    local first_commit_hash
    first_commit_hash=$(git log -1 --format=%H)

    echo "line2" >> "file with space.txt"

    # *** Use 'run' explicitly before wait_for_git_change ***
    run wait_for_git_change 20 0.5 git log -1 --format=%H --grep="line2" # Wait for the *specific* commit
    assert_success "Second commit timed out"

    # Verify commit message content of the *second* commit
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "file with space.txt" # Check filename appears
    assert_output --partial "line2"               # Check content appears

    cd /tmp
}

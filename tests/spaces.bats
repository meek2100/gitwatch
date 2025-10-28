#!/usr/bin/env bats

# Load standard helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load custom helpers
load 'test_helper/custom_helpers'
# Load setup/teardown specific for paths with spaces
load 'startup-shutdown.bash' # Load the combined file

# Override the default setup for this test file
setup() {
    setup_with_spaces
}

@test "spaces_in_target_dir: Handles paths with spaces correctly" {
    # Start gitwatch directly in the background - paths need careful quoting
    # BATS_TEST_DIRNAME should handle spaces if the script itself is in such a path
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/rem with spaces" &
    GITWATCH_PID=$!
    debug "Testdir with spaces: $testdir"

    cd "$testdir/local/rem with spaces" # cd into the directory with spaces
    sleep 1
    echo "line1" >> "file with space.txt" # Modify file with space

    # Wait for first commit hash to appear/change
    wait_for_git_change 20 0.5 git log -1 --format=%H
    local first_commit_hash=$(git log -1 --format=%H)

    echo "line2" >> "file with space.txt"

    # Wait for second commit (checking that the hash changes)
    wait_for_git_change 20 0.5 git log -1 --format=%H

    # Verify commit message content
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "file with space.txt" # Check filename appears
    assert_output --partial "line2" # Check content might appear

    cd /tmp
}

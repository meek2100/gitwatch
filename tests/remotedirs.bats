#!/usr/bin/env bats

# Load helpers FIRST
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load custom helpers
load 'test_helper/custom_helpers'

# Define the custom cleanup logic specific to this file
# Use standard echo to output debug info to avoid relying on bats-support inside teardown
_remotedirs_cleanup() {
  echo "# Running custom cleanup for remotedirs" >&3
  if [ -n "${dotgittestdir:-}" ] && [ -d "$dotgittestdir" ];
then
    echo "# Removing external git dir: $dotgittestdir" >&3
    rm -rf "$dotgittestdir"
  fi
}

# Load the base setup/teardown AFTER defining the custom helper
load 'startup-shutdown'
# The original teardown() is now defined.
# Copy the original teardown function to a new name
# This must happen AFTER loading startup-shutdown and BEFORE overriding teardown again.
eval "$(declare -f teardown | sed 's/teardown/original_teardown/')"

# Define the final teardown override that calls both parts
teardown() {
  _remotedirs_cleanup # Call custom part first
  original_teardown   # Then call the original part
}


@test "remote_git_dirs_working_with_commit_logging: -g flag works with external .git dir" {
    dotgittestdir=$(mktemp -d)
    run mv "$testdir/local/$TEST_SUBDIR_NAME/.git" "$dotgittestdir/"
    assert_success

    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 -g "$dotgittestdir/.git" "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for first commit using the external git dir
    wait_for_git_change 20 0.5 git --git-dir="$dotgittestdir/.git" log -1 --format=%H
    assert_success "First commit timed out"
    local lastcommit=$(git --git-dir="$dotgittestdir/.git" log -1 --format=%H)


    echo "line2" >> file1.txt

    # Wait for second commit event (by checking that the hash changes) using the external git dir
    wait_for_git_change 20 0.5 git --git-dir="$dotgittestdir/.git" log -1 --format=%H
    assert_success "Second commit timed out"

    # Verify that new commit hash is different
    local currentcommit=$(git --git-dir="$dotgittestdir/.git" log -1 --format=%H)
    assert_not_equal "$lastcommit" "$currentcommit" "Commit hash should be different after second change"

    # Verify commit message content
    run git --git-dir="$dotgittestdir/.git" log -1 --pretty=%B
    assert_success
    assert_output --partial "file1.txt"
    assert_output --partial "line2" # Depends on diff-lines output

    cd /tmp # Move out before teardown
}

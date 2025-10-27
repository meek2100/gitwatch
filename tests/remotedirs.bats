#!/usr/bin/env bats

load 'tests/test_helper/bats-support/load'
load 'tests/test_helper/bats-assert/load'
load 'tests/test_helper/bats-file/load'
load 'tests/startup-shutdown'

# Define the custom cleanup logic specific to this file
# Use standard echo to output debug info to avoid relying on bats-support inside teardown
_remotedirs_cleanup() {
  echo "# Running custom cleanup for remotedirs" >&3
  if [ -n "${dotgittestdir:-}" ] && [ -d "$dotgittestdir" ]; then
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
    run mv "$testdir/local/remote/.git" "$dotgittestdir/"
    assert_success

    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 -g "$dotgittestdir/.git" "$testdir/local/remote" &
    GITWATCH_PID=$!

    cd "$testdir/local/remote"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for first commit
    retry 20 0.5 "run git --git-dir=\"$dotgittestdir/.git\" rev-parse master"
    assert_success
    local lastcommit=$output

    echo "line2" >> file1.txt

    # Wait for second commit event (by checking that the hash changes)
    retry 20 0.5 "run test \"\$(git --git-dir=\"$dotgittestdir/.git\" rev-parse master)\" != \"$lastcommit\""
    assert_success "Commit hash should change after modification"

    # Add a small delay for ref update to settle, especially on macOS
    sleep 0.5

    # Verify that new commit has happened
    run git --git-dir="$dotgittestdir/.git" rev-parse master
    assert_success
    local currentcommit=$output
    refute_equal "$lastcommit" "$currentcommit" "Commit hash should be different"

    run git --git-dir="$dotgittestdir/.git" log -1 --pretty=%B
    assert_success
    assert_output --partial "file1.txt"
    assert_output --partial "line2"

    cd /tmp # Move out before teardown
}

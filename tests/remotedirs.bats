#!/usr/bin/env bats

# Load bats-core helpers relative to the test file's location
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

# Load setup/teardown
load 'startup-shutdown'

@test "remote_git_dirs_working_with_commit_logging: -g flag works with external .git dir" {
    # Move .git directory somewhere else
    local dotgittestdir
    dotgittestdir=$(mktemp -d)
    run mv "$testdir/local/remote/.git" "$dotgittestdir/"
    assert_success

    # Start gitwatch pointing to the external .git dir and the work tree
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 -g "$dotgittestdir/.git" "$testdir/local/remote"
    assert_success
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"

    sleep 1
    echo "line1" >> file1.txt
    sleep "$WAITTIME" # Wait for first commit

    # Store commit for later comparison
    run git --git-dir="$dotgittestdir/.git" rev-parse master
    assert_success
    local lastcommit=$output

    # Make a new change
    echo "line2" >> file1.txt
    sleep "$WAITTIME" # Wait for second commit

    # Verify that new commit has happened
    run git --git-dir="$dotgittestdir/.git" rev-parse master
    assert_success
    local currentcommit=$output
    refute_equal "$lastcommit" "$currentcommit"

    # Check commit log (using external git dir) that the diff is in there
    run git --git-dir "$dotgittestdir/.git" log -1 --pretty=%B
    assert_success
    assert_output --partial "file1.txt"

    # Clean up the external .git dir in teardown (or explicitly if needed)
    teardown() {
      rm -rf "$dotgittestdir"
      # Call original teardown if loaded from file
      # original_teardown # You'd need to adapt startup-shutdown.bash if you do this
    }
}

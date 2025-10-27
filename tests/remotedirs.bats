#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'startup-shutdown' # This defines the original teardown()

# 1. Copy the original teardown function to a new name
#    This must be done *after* loading startup-shutdown and *before* overriding teardown.
eval "$(declare -f teardown | sed 's/teardown/original_teardown/')"

# 2. Now, override teardown() with your custom version
teardown() {
  debug "Running custom teardown for remotedirs"
  # Clean up the external .git dir created in this test
  if [ -n "${dotgittestdir:-}" ] && [ -d "$dotgittestdir" ];
  then
      debug "Removing external git dir: $dotgittestdir"
      rm -rf "$dotgittestdir"
  fi

  debug "Calling original teardown"
  # 3. Call the saved original function
  original_teardown
}


@test "remote_git_dirs_working_with_commit_logging: -g flag works with external .git dir" {
    dotgittestdir=$(mktemp -d)
    run mv "$testdir/local/remote/.git" "$dotgittestdir/"
    assert_success

    # Start gitwatch directly in the background
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 -g "$dotgittestdir/.git" "$testdir/local/remote" &
    GITWATCH_PID=$!
    disown

    cd "$testdir/local/remote"
    sleep 1
    echo "line1" >> file1.txt
    sleep "$WAITTIME" # Wait for first commit

    run git --git-dir="$dotgittestdir/.git" rev-parse master
    assert_success
    local lastcommit=$output

    echo "line2" >> file1.txt
    sleep "$WAITTIME" # Wait for second commit event

    # Add a small delay for ref update to settle, especially on macOS
    sleep 0.5

    # Verify that new commit has happened
    run git --git-dir="$dotgittestdir/.git" rev-parse master
    assert_success
    local currentcommit=$output
    refute_equal "$lastcommit" "$currentcommit" "Commit hash should change after modification"

    run git --git-dir="$dotgittestdir/.git" log -1 --pretty=%B
    assert_success
    assert_output --partial "file1.txt"

    cd /tmp # Move out before teardown
}

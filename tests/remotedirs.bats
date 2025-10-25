#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'startup-shutdown'

# Note: Need a custom teardown here to clean the external .git dir
_original_teardown() {
  # This assumes the original teardown function from startup-shutdown.bash
  # is available globally or can be called. Adjust if needed.
  if command -v teardown >/dev/null && [[ "$(type -t teardown)" == "function" ]]; then
     # Temporarily rename our teardown to avoid recursion if names clash
     eval "$(declare -f teardown | sed 's/teardown/_local_teardown/')"
     teardown # Call the original teardown from startup-shutdown
     eval "$(declare -f _local_teardown | sed 's/_local_teardown/teardown/')" # Restore our teardown
  fi
}

teardown() {
  # Clean up the external .git dir created in this test
  if [ -n "${dotgittestdir:-}" ] && [ -d "$dotgittestdir" ]; then
      rm -rf "$dotgittestdir"
  fi
  _original_teardown # Call the original teardown function
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
    sleep "$WAITTIME"

    run git --git-dir="$dotgittestdir/.git" rev-parse master
    assert_success
    local lastcommit=$output

    echo "line2" >> file1.txt
    sleep "$WAITTIME"

    run git --git-dir="$dotgittestdir/.git" rev-parse master
    assert_success
    local currentcommit=$output
    refute_equal "$lastcommit" "$currentcommit"

    run git --git-dir="$dotgittestdir/.git" log -1 --pretty=%B
    assert_success
    assert_output --partial "file1.txt"

    cd /tmp # Move out before teardown
}

#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
load 'startup-shutdown'

# Note: Need a custom teardown here to clean the external .git dir
_original_teardown() {
  if command -v teardown >/dev/null && [[ "$(type -t teardown)" == "function" ]]; then
     # Check if the function body is different to avoid infinite recursion
     # This is a basic check; might need refinement if function bodies are complex
     if [[ "$(declare -f teardown)" != "$(declare -f _original_teardown)" ]]; then
       teardown # Call the original teardown from startup-shutdown
     fi
  fi
}

teardown() {
  # Clean up the external .git dir created in this test
  if [ -n "${dotgittestdir:-}" ] && [ -d "$dotgittestdir" ]; then
      debug "Removing external git dir: $dotgittestdir"
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

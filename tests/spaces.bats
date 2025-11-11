#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown specific for paths with spaces
load 'bats-custom/startup-shutdown'

<<<<<<< HEAD
# Override the default setup for this test file
setup() {
  setup_with_spaces
}

@test "spaces_in_target_dir_handles_paths_with_spaces_correctly" {
  # Start gitwatch directly in the background - paths need careful quoting
  # BATS_TEST_DIRNAME should handle spaces if the script itself is in such a path
  # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -l 10 "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  verbose_echo "# Testdir with spaces: $testdir"
  verbose_echo "# Local clone dir: $testdir/local/$TEST_SUBDIR_NAME"

  cd "$testdir/local/$TEST_SUBDIR_NAME" # cd into the directory with spaces
  sleep 1
  echo "line1" >> "file with space.txt" # Modify file with space

  # *** Use 'run' explicitly before wait_for_git_change ***
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "First commit timed out"
  # Now get the hash *after* the wait succeeded
  # shellcheck disable=SC2034 # Not used in this test, but retained for clarity
  local first_commit_hash
  # shellcheck disable=SC2034 # Not used in this test, but retained for clarity
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
=======
load startup-shutdown-spaces

function spaces_in_target_dir { #@test
  # Start up gitwatch with logging, see if works
  "${BATS_TEST_DIRNAME}"/../gitwatch.sh -l 10 "$testdir/local/rem with spaces" 3>&- &
  echo "Testdir: $testdir" >&3
  GITWATCH_PID=$!

  # Keeps kill message from printing to screen
  disown

  # Create a file, verify that it hasn't been added yet, then commit
  cd "rem with spaces"

  # According to inotify documentation, a race condition results if you write
  # to directory too soon after it has been created; hence, a short wait.
  sleep 1
  echo "line1" >> file1.txt

  # Wait a bit for inotify to figure out the file has changed, and do its add,
  # and commit
  sleep "$WAITTIME"

  # Make a new change
  echo "line2" >> file1.txt
  sleep "$WAITTIME"

  # Check commit log that the diff is in there
  run git log -1 --oneline
  [[ $output == *"file1.txt"* ]]
}
>>>>>>> master

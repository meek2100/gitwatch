#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

<<<<<<< HEAD
@test "syncing_correctly_commits_and_pushes_adds_subdir_adds_and_removals" {
  # Start gitwatch directly in the background
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -r origin "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # --- Test 1: Add initial file ---
  sleep 1
  echo "line1" >> file1.txt

  # Wait for commit+push (wait for remote ref to update)
  run wait_for_git_change 20 0.5 git rev-parse origin/master
  assert_success "Git rev-parse origin/master failed after file1 add"

  run git rev-parse master
  assert_success "Git rev-parse master failed after file1 add"
  local commit1=$output
  run git rev-parse origin/master
  local remote_commit1=$output
  assert_equal "$commit1" "$remote_commit1" "Push after adding file1 failed"

  # --- Test 2: Add file in subdirectory ---
  local lastcommit=$commit1
  local lastremotecommit=$remote_commit1
  mkdir subdir

  sleep 0.5 # Small delay
  cd subdir
  echo "line2" >> file2.txt
  # shellcheck disable=SC2103 # cd is necessary here to manage nested folder operation
  cd .. # Back to repo root

  # Wait for commit+push (by checking that remote hash has changed)
  run wait_for_git_change 20 0.5 git rev-parse origin/master
  assert_success "Push after adding file2 failed to appear on remote (timeout)"

  run git rev-parse master
  assert_success "Git rev-parse master failed after file2 add"
  local commit2=$output
  assert_not_equal "$lastcommit" "$commit2" "Commit after adding file2 in subdir failed"

  run git rev-parse origin/master
  assert_success "Git rev-parse origin/master failed after file2 add"
  local remote_commit2=$output

  assert_equal "$commit2" "$remote_commit2" "Push after adding file2 failed"
  assert_not_equal "$lastremotecommit" "$remote_commit2" "Remote commit hash did not change after file2 add"


  # --- Test 3: Remove file and directory ---
  lastcommit=$commit2
  lastremotecommit=$remote_commit2
  run rm subdir/file2.txt
  assert_success "rm subdir/file2.txt failed"
  sleep 0.5 # Delay between rm and rmdir might help watcher catch events separately
  run rmdir subdir
  assert_success "rmdir subdir failed"

  # Wait for potential commit+push for removal (by checking that remote hash has changed again)
  run wait_for_git_change 20 1 git rev-parse origin/master # Slightly longer delay after removal
  assert_success "Push after removal failed to appear on remote (timeout)"

  # Debug: Check git status right before hash comparison
  run git status -s
  verbose_echo "# Git status after removal wait: $output"

  # Verify push happened reflecting the removal
  run git rev-parse master
  assert_success "Git rev-parse master failed after removal"
  local commit3=$output
  run git rev-parse origin/master
  assert_success "Git rev-parse origin/master failed after removal"
  local remote_commit3=$output
  assert_equal "$commit3" "$remote_commit3" "Push after removing file/subdir failed"
  assert_not_equal "$lastremotecommit" "$remote_commit3" "Remote commit hash did not change after removal"

  # Explicitly check that a new commit *did* happen locally
  assert_not_equal "$lastcommit" "$commit3" "Local commit hash did not change after removal"

  # Verify the file and directory are indeed gone locally
  assert_file_not_exists "subdir/file2.txt"
  assert_dir_not_exists "subdir"

  cd /tmp
}

# --- NEW TEST ---
@test "atomic_save_move_handles_atomic_saves_move_correctly" {
  # Start gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -l 10 "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create and commit the initial file
  echo "initial" > file_atomic.txt
  git add .
  git commit -q -m "Initial atomic file"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)
  sleep 1

  # 2. Simulate an atomic save (write to temp, move to final)
  echo "atomic save content" > file_atomic.txt.tmp
  run mv file_atomic.txt.tmp file_atomic.txt
  assert_success "mv command for atomic save failed"

  # 3. Wait for the commit to appear (triggered by the 'move' event)
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for atomic save (move) timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # 4. Verify commit message
  run git log -1 --pretty=%B
  assert_success
  assert_output --partial "file_atomic.txt"
  assert_output --partial "atomic save content"

  cd /tmp
}
# --- END NEW TEST ---
=======
function syncing_correctly { #@test
  # Start up gitwatch and see if commit and push happen automatically
  # after waiting two seconds
  ${BATS_TEST_DIRNAME}/../gitwatch.sh -r origin "$testdir/local/remote" 3>- &
  GITWATCH_PID=$!

  # Keeps kill message from printing to screen
  disown

  # Create a file, verify that it hasn't been added yet,
  # then commit and push
  cd remote

  # According to inotify documentation, a race condition results if you write
  # to directory too soon after it has been created; hence, a short wait.
  sleep 1
  echo "line1" >> file1.txt

  # Wait a bit for inotify to figure out the file has changed, and do its add,
  # commit, and push.
  sleep $WAITTIME

  # Verify that push happened
  currentcommit=$(git rev-parse master)
  remotecommit=$(git rev-parse origin/master)
  [ "$currentcommit" = "$remotecommit" ]

  # Try making subdirectory with file
  lastcommit=$(git rev-parse master)
  mkdir subdir
  cd subdir
  echo "line2" >> file2.txt

  sleep $WAITTIME

  # Verify that new commit has happened
  currentcommit=$(git rev-parse master)
  [ "$lastcommit" != "$currentcommit" ]

  # Verify that push happened
  currentcommit=$(git rev-parse master)
  remotecommit=$(git rev-parse origin/master)
  [ "$currentcommit" = "$remotecommit" ]


  # Try removing file to see if can work
  rm file2.txt
  sleep $WAITTIME

  # Verify that new commit has happened
  currentcommit=$(git rev-parse master)
  [ "$lastcommit" != "$currentcommit" ]

  # Verify that push happened
  currentcommit=$(git rev-parse master)
  remotecommit=$(git rev-parse origin/master)
  [ "$currentcommit" = "$remotecommit" ]

  # Remove testing directories
  cd /tmp
  rm -rf $testdir
}
>>>>>>> master

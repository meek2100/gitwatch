#!/usr/bin/env bats

# Load helpers FIRST
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'

<<<<<<< HEAD
# Define the custom cleanup logic specific to this file
# Use standard echo to output debug info to avoid relying on bats-support inside teardown
_remotedirs_cleanup() {
  verbose_echo "# Running custom cleanup for remotedirs"
  if [ -n "${dotgittestdir:-}" ] && [ -d "$dotgittestdir" ];
  then
    verbose_echo "# Removing external git dir: $dotgittestdir"
    rm -rf "$dotgittestdir"
  fi
}

# Load the base setup/teardown AFTER defining the custom helper
# This file now contains _common_teardown() and a default teardown() wrapper
load 'bats-custom/startup-shutdown'

# Define the final teardown override that calls both the custom
# cleanup for this file and the common teardown logic.
teardown() {
  _remotedirs_cleanup # Call custom part first
  _common_teardown    # Then call the common part directly from the loaded file
}


@test "remote_git_dirs_working_with_commit_logging_g_flag_works_with_external_git_dir" {
  local dotgittestdir
  dotgittestdir=$(mktemp -d)
  # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run mv "$testdir/local/$TEST_SUBDIR_NAME/.git" "$dotgittestdir/"
  assert_success

  # Start gitwatch directly in the background
  # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -l 10 -g "$dotgittestdir/.git" "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1
  echo "line1" >> file1.txt

  # Wait for first commit using the external git dir
  wait_for_git_change 20 0.5 git --git-dir="$dotgittestdir/.git" log -1 --format=%H
  assert_success "First commit timed out"
  local lastcommit
  # shellcheck disable=SC2155 # Declared on previous line
  lastcommit=$(git --git-dir="$dotgittestdir/.git" log -1 --format=%H)


  echo "line2" >> file1.txt

  # Wait for second commit event (by checking that the hash changes) using the external git dir
  wait_for_git_change 20 0.5 git --git-dir="$dotgittestdir/.git" log -1 --format=%H
  assert_success "Second commit timed out"

  # Verify that new commit hash is different

  local currentcommit
  # shellcheck disable=SC2155 # Declared on previous line
  currentcommit=$(git --git-dir="$dotgittestdir/.git" log -1 --format=%H)
  assert_not_equal "$lastcommit" "$currentcommit" "Commit hash should be different after second change"

  # Verify commit message content
  run git --git-dir="$dotgittestdir/.git" log -1 --pretty=%B
  assert_success
  assert_output --partial "file1.txt"
  assert_output --partial "line2" # Depends on diff-lines output

  cd /tmp # Move out before teardown
}

@test "remote_git_dirs_working_with_commit_and_push_g_flag_works_with_external_git_dir_and_r_push" {
  local dotgittestdir
  dotgittestdir=$(mktemp -d)
  # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run mv "$testdir/local/$TEST_SUBDIR_NAME/.git" "$dotgittestdir/"
  assert_success

  # Start gitwatch directly in the background with -r and -g
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -r origin -g "$dotgittestdir/.git" "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1
  echo "line1" >> file_for_remote.txt

  # Wait for the change to be pushed to the remote (by checking remote hash)
  wait_for_git_change 30 1 git rev-parse origin/master
  assert_success "Commit and push with -g timed out"

  # Verify that the local and remote hashes match (indicating successful push)
  # Use the external .git dir for the local check
  local local_commit_hash
  # shellcheck disable=SC2155 # Declared on previous line
  local_commit_hash=$(git --git-dir="$dotgittestdir/.git" rev-parse master)
  local remote_commit_hash
  # shellcheck disable=SC2155 # Declared on previous line
  remote_commit_hash=$(git rev-parse origin/master)
  assert_equal "$local_commit_hash" "$remote_commit_hash" "Local and remote hashes do not match after -g push"

  # Verify commit message content
  run git --git-dir="$dotgittestdir/.git" log -1 --pretty=%B
  assert_success
  assert_output --partial "file_for_remote.txt"

  cd /tmp # Move out before teardown
}

@test "remote_git_dirs_file_target_g_flag_works_with_external_git_dir_and_single_file_target" {
  local target_file="single_watched_file.txt"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local watched_file_path="$testdir/local/$TEST_SUBDIR_NAME/$target_file"
  local dotgittestdir
  dotgittestdir=$(mktemp -d)

  # 1. Create the target file and commit it locally (needed for setup)
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  echo "Initial content for single file watch" > "$target_file"
  git add "$target_file"
  git commit -q -m "Initial commit for single file test"


  # 2. Move the .git directory externally
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run mv "$testdir/local/$TEST_SUBDIR_NAME/.git" "$dotgittestdir/"
  assert_success

  # 3. Get the initial commit hash using the external git dir
  local initial_hash
  # shellcheck disable=SC2155 # Declared on previous line
  initial_hash=$(git --git-dir="$dotgittestdir/.git" log -1 --format=%H)

  # 4. Start gitwatch targeting the file AND specifying the external git dir
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -g "$dotgittestdir/.git" "$watched_file_path" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 5. Modify the file to trigger the commit
  echo "Change to the single file" >> "$target_file"

  # 6. Wait for the commit to happen using the external git dir
  run wait_for_git_change 20 0.5 git --git-dir="$dotgittestdir/.git" log -1 --format=%H
  assert_success "Commit timed out, suggesting -g with file target failed"

  # 7. Verify the hash changed
  local final_hash
  # shellcheck disable=SC2155 # Declared on previous line
  final_hash=$(git --git-dir="$dotgittestdir/.git" log -1 --format=%H)
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash should change after modifying single file"

  # 8. Verify the file content is in the index (proving the 'git add' used the correct work-tree)
  run git --git-dir="$dotgittestdir/.git" show HEAD:"$target_file"
  assert_output --partial "Change to the single file"

  cd /tmp # Move out before teardown
}

# --- NEW TEST: -g suspicious path warning ---
@test "remote_git_dirs_g_warning_g_flag_warns_on_suspicious_relative_path_input" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Start gitwatch with a non-absolute path for -g (e.g., just a name)
  # The script should try to resolve it and issue a warning.
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -g "mygitdir" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to initialize

  # 2. Assert: Check log output for the expected warning
  run cat "$output_file"
  assert_output --partial "Warning: GIT_DIR 'mygitdir' specified with -g looks like a relative name, not a full path. Proceeding..." \
    "The script failed to issue the expected warning for a suspicious -g path."
  # 3. Assert: The script is running (not a fatal error)
  if ! kill -0 "$GITWATCH_PID" 2>/dev/null;
  then
    fail "Gitwatch exited unexpectedly after the -g warning."
  fi

  # 4. Cleanup
  cd /tmp
}
=======
load startup-shutdown

function remote_git_dirs_working_with_commit_logging { #@test
  # Move .git somewhere else
  dotgittestdir=$(mktemp -d)
  mv "$testdir/local/remote/.git" "$dotgittestdir"

  # Start up gitwatch, intentionally in wrong directory, with remote dir specified
  ${BATS_TEST_DIRNAME}/../gitwatch.sh -l 10 -g "$dotgittestdir/.git" "$testdir/local/remote" 3>&- &
  GITWATCH_PID=$!

  # Keeps kill message from printing to screen
  disown

  # Create a file, verify that it hasn't been added yet, then commit
  cd remote

  # According to inotify documentation, a race condition results if you write
  # to directory too soon after it has been created; hence, a short wait.
  sleep 1
  echo "line1" >> file1.txt

  # Wait a bit for inotify to figure out the file has changed, and do its add,
  # and commit
  sleep $WAITTIME

  # Store commit for later comparison
  lastcommit=$(git --git-dir $dotgittestdir/.git rev-parse master)

  # Make a new change
  echo "line2" >> file1.txt
  sleep $WAITTIME

  # Verify that new commit has happened
  currentcommit=$(git --git-dir $dotgittestdir/.git rev-parse master)
  [ "$lastcommit" != "$currentcommit" ]

  # Check commit log that the diff is in there
  run git --git-dir $dotgittestdir/.git log -1 --oneline
  [[ $output == *"file1.txt"* ]]

  rm -rf $dotgittestdir
}
>>>>>>> master

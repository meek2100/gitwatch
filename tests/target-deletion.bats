#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# This test checks that gitwatch exits gracefully when the target it is watching
# (either a file or a directory) is deleted, as the underlying watcher tool will
# terminate in this scenario.
@test "target_deletion_file: Commits deletion and exits gracefully" {
  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")
  local watch_file="file_to_watch.txt"
  local watched_file_path="$testdir/local/$TEST_SUBDIR_NAME/$watch_file"

  # 1. Create and commit a file to watch
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  echo "initial content" > "$watch_file"
  git add "$watch_file"
  git commit -q -m "Initial commit of watched file"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Start gitwatch watching the file, logging all output
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$watched_file_path" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  local watch_pid=$GITWATCH_PID
  sleep 1 # Allow watcher to initialize

  # 3. Delete the watched file
  echo "# DEBUG: Deleting the watched file: $watched_file_path" >&3
  run rm "$watch_file"
  assert_success "Failed to delete watched file"

  # 4. Wait for the DELETION COMMIT to appear
  run wait_for_git_change 10 0.5 git log -1 --format=%H
  assert_success "Deletion commit timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change after deletion"

  # 5. Verify the commit message reflects a deletion
  run git log -1 --pretty=%B
  assert_output --partial "File deleted."

  # 6. Wait for the main gitwatch process to terminate (should be quick now)
  local max_wait=5
  local wait_count=0
  # Use 'kill -0' to check if PID is alive
  while kill -0 "$watch_pid" 2>/dev/null && [ "$wait_count" -lt "$max_wait" ]; do
    echo "# DEBUG: Waiting for gitwatch PID $watch_pid to exit..." >&3
    sleep 1
    wait_count=$((wait_count + 1))
  done

  # If the process is still running after the wait, fail
  if kill -0 "$watch_pid" 2>/dev/null; then
    fail "gitwatch process (PID $watch_pid) failed to exit after watched file deletion."
  fi

  # 7. Assert: Check log output confirms loop termination
  run cat "$output_file"
  assert_output --partial "File watcher process ended (or failed). Exiting via loop termination."

  # 8. Cleanup: Unset the PID
  unset GITWATCH_PID
  cd /tmp
}

@test "target_deletion_dir: Exits gracefully when the watched directory is deleted" {
  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")
  local sub_dir_path="$testdir/local/watched_sub_dir"

  # 1. Setup: Create a subdirectory to watch and initialize an inner repo
  cd "$testdir/local"
  mkdir watched_sub_dir
  cd watched_sub_dir
  git init -q # Ensure it's a valid, watchable target

  # 2. Start gitwatch watching the subdirectory, logging all output
  _common_teardown # Ensures no zombie processes from the previous file test remain

  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$sub_dir_path" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  local watch_pid=$GITWATCH_PID
  sleep 1 # Allow watcher to initialize

  # 3. Delete the watched directory
  echo "# DEBUG: Deleting the watched directory: $sub_dir_path" >&3
  cd /tmp # Move out of the directory before deletion
  run rm -rf "$sub_dir_path"
  assert_success "Failed to delete watched directory"

  # 4. Wait for the main gitwatch process to terminate
  local max_wait=5
  local wait_count=0
  while kill -0 "$watch_pid" 2>/dev/null && [ "$wait_count" -lt "$max_wait" ]; do
    echo "# DEBUG: Waiting for gitwatch PID $watch_pid to exit..." >&3
    sleep 1
    wait_count=$((wait_count + 1))
  done

  if kill -0 "$watch_pid" 2>/dev/null; then
    fail "gitwatch process (PID $watch_pid) failed to exit after watched directory deletion."
  fi

  # 5. Assert: Check log output confirms loop termination
  run cat "$output_file"
  assert_output --partial "File watcher process ended (or failed). Exiting via loop termination."

  # 6. Cleanup
  unset GITWATCH_PID
  cd /tmp
}

@test "watcher_process_failure: Exits gracefully when the watcher binary terminates unexpectedly" {
  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")
  local exit_code=5

  # Determine watcher name for dummy creation
  local watcher_name
  if [ "$RUNNER_OS" == "Linux" ]; then
    watcher_name="inotifywait"
  else
    watcher_name="fswatch"
  fi

  # 1. Create a dummy watcher binary that fails immediately
  local dummy_watcher
  # Note: Requires create_failing_watcher_bin from custom-helpers.bash
  dummy_watcher=$(create_failing_watcher_bin "$watcher_name" "$exit_code")

  # 2. Export the environment variable to force gitwatch.sh to use the dummy
  export GW_INW_BIN="$dummy_watcher"

  # 3. Start gitwatch (it will execute the failing dummy watcher)
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  local watch_pid=$GITWATCH_PID

  # Give a short moment for the watcher to fail and the loop to exit
  sleep 1

  # 4. Wait for the main gitwatch process to terminate
  local max_wait=5
  local wait_count=0
  while kill -0 "$watch_pid" 2>/dev/null && [ "$wait_count" -lt "$max_wait" ]; do
    echo "# DEBUG: Waiting for gitwatch PID $watch_pid to exit..." >&3
    sleep 1
    wait_count=$((wait_count + 1))
  done

  # 5. Assert process terminated
  if kill -0 "$watch_pid" 2>/dev/null; then
    fail "gitwatch process (PID $watch_pid) failed to exit after watcher failure."
  fi

  # 6. Assert log output confirms failure and exit
  run cat "$output_file"
  assert_output --partial "DUMMY WATCHER: $watcher_name failed with code $exit_code" \
    "The dummy watcher failure message was not captured."
  assert_output --partial "File watcher process ended (or failed). Exiting via loop termination." \
    "Did not log loop termination message."
  # 7. Cleanup
  unset GITWATCH_PID
  unset GW_INW_BIN
  rm -f "$dummy_watcher"
  cd /tmp
}

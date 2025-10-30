#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# This utility creates a wrapper binary for the watcher to capture the arguments passed to it.
# Copied from watcher-args.bats to keep this test self-contained.
create_watcher_wrapper() {
  local watcher_name="$1"
  local real_path="$2"
  local dummy_path="$testdir/bin/${watcher_name}_wrapper"
  mkdir -p "$testdir/bin"
  echo "#!/usr/bin/env bash" > "$dummy_path"
  echo "echo \"*** ${watcher_name}_CALLED ***\" >&2" >> "$dummy_path"
  # Print arguments to stderr for assertion, using printf %q for safe quoting
  echo "echo \"*** ARGS: \$(printf '%q ' \"\$@\") ***\" >&2" >> "$dummy_path"
  # Execute the real binary with a minimal set of non-blocking arguments, piping to true to prevent indefinite blocking
  echo "exec $real_path \"\$@\" | true" >> "$dummy_path"
  chmod +x "$dummy_path"
  echo "$dummy_path"
}

@test "watcher_args_custom_events_linux: -e flag passes custom events to inotifywait" {
  if [ "$RUNNER_OS" != "Linux" ]; then
    skip "Test skipped: only runs on Linux runners."
  fi

  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup Environment: Use a dummy inotifywait to capture arguments
  local real_inw_path
  real_inw_path=$(command -v inotifywait)
  local dummy_inw=$(create_watcher_wrapper "inotifywait" "$real_inw_path")
  export GW_INW_BIN="$dummy_inw"

  # The expected custom events string
  local custom_events="modify,create"
  local expected_regex="'(\\.git/|\\.git\\$)'" # Default regex

  # 2. Start gitwatch with -e
  # Expected args: -qmr -e <custom_events> --exclude <regex> <path>
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -e "$custom_events" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to start

  # 3. Assert: Check log output for custom inotifywait arguments
  run cat "$output_file"
  assert_output --partial "*** inotifywait_CALLED ***" "Dummy inotifywait was not executed"
  # Check that the custom event string was passed
  local expected_args="-qmr -e $custom_events --exclude $expected_regex $testdir/local/$TEST_SUBDIR_NAME"
  assert_output --partial "ARGS: $expected_args" "Inotifywait custom arguments not passed correctly"

  # 4. Cleanup
  unset GW_INW_BIN
  cd /tmp
}

@test "watcher_args_custom_events_macos: -e flag passes custom events to fswatch" {
  if [ "$RUNNER_OS" != "macOS" ]; then
    skip "Test skipped: only runs on macOS runners."
  fi

  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup Environment: Use a dummy fswatch to capture arguments
  local real_fswatch_path
  real_fswatch_path=$(command -v fswatch)
  local dummy_fswatch=$(create_watcher_wrapper "fswatch" "$real_fswatch_path")
  export GW_INW_BIN="$dummy_fswatch"

  # The expected custom events number (e.g., 2 = Created)
  local custom_events="2"
  local expected_regex="'(\\.git/|\\.git\\$)'" # Default regex

  # 2. Start gitwatch with -e
  # Expected args: --recursive --event <custom_number> -E --exclude <regex> <path>
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -e "$custom_events" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to start

  # 3. Assert: Check log output for fswatch arguments
  run cat "$output_file"
  assert_output --partial "*** fswatch_CALLED ***" "Dummy fswatch was not executed"
  # Check that the custom event number was passed
  local expected_args="--recursive --event $custom_events -E --exclude $expected_regex $testdir/local/$TEST_SUBDIR_NAME"
  assert_output --partial "ARGS: $expected_args" "Fswatch custom arguments not passed correctly"

  # 4. Cleanup
  unset GW_INW_BIN
  cd /tmp
}

@test "watcher_behavior_custom_events: -e create only commits on file creation" {
  # This test is behavior-based and does not need the wrapper
  unset GW_INW_BIN

  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  local existing_file="existing_file.txt"
  local new_file="new_file.txt"

  # 1. Create and commit an initial file
  echo "initial" > "$existing_file"
  git add "$existing_file"
  git commit -q -m "Initial file"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Determine platform-specific 'create' event flag
  local create_event=""
  if [ "$RUNNER_OS" == "Linux" ]; then
    create_event="create"
  else
    # fswatch numeric flag for "Created" is 2
    create_event="2"
  fi

  # 3. Start gitwatch watching ONLY for 'create' events
  echo "# DEBUG: Starting gitwatch with -e $create_event" >&3
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -e "$create_event" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  sleep 1

  # 4. Modify the existing file (this is NOT a 'create' event)
  echo "modification" >> "$existing_file"

  # 5. Wait to ensure no commit happens
  echo "# DEBUG: Waiting ${WAITTIME}s to ensure NO commit happens on 'modify'..." >&3
  sleep "$WAITTIME"

  # 6. Assert commit hash has NOT changed
  run git log -1 --format=%H
  assert_success
  assert_equal "$initial_hash" "$output" "Commit occurred on 'modify' event but should not have"

  # 7. Create a new file (this IS a 'create' event)
  echo "new" > "$new_file"

  # 8. Wait for the commit to appear
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for 'create' event timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change after 'create' event"

  # 9. Verify commit log shows only the new file
  run git log -1 --name-only
  assert_output --partial "$new_file"
  refute_output --partial "$existing_file"

  cd /tmp
}

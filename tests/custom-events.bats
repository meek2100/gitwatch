#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# This utility creates a wrapper binary for the watcher to capture the arguments passed to it.
# Copied from watcher-args.bats to keep this test self-contained.
create_watcher_wrapper() {
  local watcher_name="$1"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local dummy_path="$testdir/bin/${watcher_name}_wrapper"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  mkdir -p "$testdir/bin"

  # shellcheck disable=SC2129 # Fix SC2129: Use single redirect to pipe commands
  {
    echo "#!/usr/bin/env bash"
    echo "echo \"*** ${watcher_name}_CALLED ***\" >&2"
    # Print arguments to stderr for assertion, using printf %q for safe quoting
    echo "echo \"*** ARGS: \$(printf '%q ' \"\$@\") ***\" >&2"
    # MODIFIED: Keep the process alive so gitwatch.sh doesn't exit.
    # The BATS teardown hook will kill this sleep and the main GITWATCH_PID.
    echo "sleep 10"
  } > "$dummy_path"

  chmod +x "$dummy_path"
  echo "$dummy_path"
}

@test "watcher_args_custom_events_linux_e_flag_passes_custom_events_to_inotifywait" {
  if [ "$RUNNER_OS" != "Linux" ];
  then
    skip "Test skipped: only runs on Linux runners."
  fi

  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup Environment: Use a dummy inotifywait to capture arguments
  local dummy_inw
  # shellcheck disable=SC2155 # Declared on previous line
  dummy_inw=$(create_watcher_wrapper "inotifywait")
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export GW_INW_BIN="$dummy_inw"

  # The expected custom events string
  local custom_events="modify,create"
  local expected_regex="'(\\.git/|\\.git\\$)'" # Default regex

  # 2. Start gitwatch with -e
  # Expected args: -qmr -e <custom_events> --exclude <regex> <path>
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -e "$custom_events" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
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

@test "watcher_args_custom_events_macos_e_flag_passes_custom_events_to_fswatch" {
  if [ "$RUNNER_OS" != "macOS" ];
  then
    skip "Test skipped: only runs on macOS runners."
  fi

  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup Environment: Use a dummy fswatch to capture arguments
  local dummy_fswatch
  # shellcheck disable=SC2155 # Declared on previous line
  dummy_fswatch=$(create_watcher_wrapper "fswatch")
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export GW_INW_BIN="$dummy_fswatch"

  # The expected custom events number (e.g., 2 = Created)
  local custom_events="2"
  local expected_regex="'(\\.git/|\\.git\\$)'" # Default regex

  # 2. Start gitwatch with -e
  # Expected args: --recursive --event <custom_number> -E --exclude <regex> <path>
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -e "$custom_events" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
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

@test "watcher_behavior_custom_events_e_create_only_commits_on_file_creation" {
  # This test is behavior-based and does not need the wrapper
  unset GW_INW_BIN

  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  # shellcheck disable=SC2154 # testdir is sourced via setup function
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
  if [ "$RUNNER_OS" == "Linux" ];
  then
    create_event="create"
  else
    # fswatch numeric flag for "Created" is 2
    create_event="2"
  fi

  # 3. Start gitwatch watching ONLY for 'create' events
  verbose_echo "# DEBUG: Starting gitwatch with -e $create_event"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -e "$create_event" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 4. Modify the existing file (this is NOT a 'create' event)
  echo "modification" >> "$existing_file"

  # 5. Wait to ensure no commit happens
  verbose_echo "# DEBUG: Waiting ${WAITTIME}s to ensure NO commit happens on 'modify'..."
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

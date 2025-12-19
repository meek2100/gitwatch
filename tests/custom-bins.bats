#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# Helper function to create a dummy binary
create_dummy_bin() {
  local name="$1"
  local real_path="$2"
  local signature="$3"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local dummy_path="$testdir/bin/$name"

  # Ensure the directory exists
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  mkdir -p "$testdir/bin"

  echo "#!/usr/bin/env bash" > "$dummy_path"
  echo "echo \"*** DUMMY BIN: $signature ***\" >&2" >> "$dummy_path"
  # Execute the real binary with all arguments
  echo "exec $real_path \"\$@\"" >> "$dummy_path"
  chmod +x "$dummy_path"
  echo "$dummy_path"
}

@test "custom_bins_env_vars_uses_gw_git_bin_gw_inw_bin_gw_flock_bin_gw_timeout_bin_gw_pkill_bin_if_set" {
  # Skip if running on macOS as fswatch replacement is more complex
  if [ "$RUNNER_OS" == "macOS" ];
  then
    skip "Custom bins test skipped: requires Linux environment for simple inotifywait setup."
  fi

  # shellcheck disable=SC2154 # testdir is sourced via setup function
  mkdir "$testdir/bin"

  # 1. Create dummy binaries
  local real_git_path
  real_git_path=$(command -v git)
  local dummy_git
  # shellcheck disable=SC2155 # Declared on previous line
  dummy_git=$(create_dummy_bin "git" "$real_git_path" "GIT_OK")

  local real_inw_path
  real_inw_path=$(command -v inotifywait)
  local dummy_inw
  # shellcheck disable=SC2155 # Declared on previous line
  dummy_inw=$(create_dummy_bin "inotifywait" "$real_inw_path" "INW_OK")

  local real_flock_path
  real_flock_path=$(command -v flock)
  local dummy_flock
  # shellcheck disable=SC2155 # Declared on previous line
  dummy_flock=$(create_dummy_bin "flock" "$real_flock_path" "FLOCK_OK")

  # --- Create dummy timeout ---
  local real_timeout_path
  real_timeout_path=$(command -v timeout)
  local dummy_timeout
  # shellcheck disable=SC2155 # Declared on previous line
  dummy_timeout=$(create_dummy_bin "timeout" "$real_timeout_path" "TIMEOUT_OK")
  # --- End new dummy timeout ---

  # --- Create dummy pkill ---
  local real_pkill_path
  real_pkill_path=$(command -v pkill)
  local dummy_pkill
  # shellcheck disable=SC2155 # Declared on previous line
  dummy_pkill=$(create_dummy_bin "pkill" "$real_pkill_path" "PKILL_OK")
  # --- End new dummy pkill ---

  # 2. Set environment variables
  export GW_GIT_BIN="$dummy_git"
  export GW_INW_BIN="$dummy_inw"
  export GW_FLOCK_BIN="$dummy_flock"
  export GW_TIMEOUT_BIN="$dummy_timeout" # --- Export dummy timeout bin ---
  export GW_PKILL_BIN="$dummy_pkill"      # --- Export dummy pkill bin ---

  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 3. Start gitwatch (should use the dummy binaries)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -s 1 "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1

  # 4. Trigger a change and wait for commit
  echo "change_for_dummy" >> file_dummy.txt
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit timed out, suggesting dummy git/inw failed"

  # 5. Assert: Check output for signature messages (which go to STDERR/STDOUT)
  run cat "$output_file"
  assert_output --partial "*** DUMMY BIN: GIT_OK ***" "Dummy Git command was not executed or its message not captured"
  assert_output --partial "*** DUMMY BIN: INW_OK ***" "Dummy Inotifywait command was not executed or its message not captured"
  assert_output --partial "*** DUMMY BIN: FLOCK_OK ***" "Dummy Flock command was not executed or its message not captured"
  # --- Assert dummy timeout was used ---
  # Note: The dependency check for GNU timeout will fail if the dummy bin doesn't forward --version.
  # The create_dummy_bin helper *does* forward all args, so this test is valid.
  assert_output --partial "*** DUMMY BIN: TIMEOUT_OK ***" "Dummy Timeout command was not executed or its message not captured"

  # --- Trigger debounce logic to check for pkill ---
  echo "change_for_pkill_1" >> file_dummy.txt
  sleep 0.1 # Must be less than script sleep time (1s)
  echo "change_for_pkill_2" >> file_dummy.txt
  sleep 3 # Wait for debounce/commit to finish

  run cat "$output_file"
  assert_output --partial "*** DUMMY BIN: PKILL_OK ***" "Dummy pkill command was not executed or its message not captured"
  # --- End new pkill check ---


  # 6. Cleanup environment variables for next test
  unset GW_GIT_BIN
  unset GW_INW_BIN
  unset GW_FLOCK_BIN
  unset GW_TIMEOUT_BIN # --- Unset dummy timeout bin ---
  unset GW_PKILL_BIN   # --- Unset dummy pkill bin ---
  cd /tmp
}

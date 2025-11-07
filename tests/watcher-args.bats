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

@test "watcher_args_linux: Verifies correct arguments for inotifywait" {

  if [ "$(uname)" != "Linux" ];
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

  # The expected default events string
  local default_events="close_write,move,move_self,delete,create,modify"

  # 2. Start gitwatch (should use inotifywait syntax and arguments)
  # Expected args: -qmr -e <events> --exclude <regex> <path>
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to start

  # 3. Assert: Check log output for inotifywait arguments
  run cat "$output_file"
  assert_output --partial "*** inotifywait_CALLED ***" "Dummy inotifywait was not executed"

  # --- FIX 2: Assert against the [INFO] log line, which is more stable ---
  local info_log_regex="\(\(\.git/\|\.git\$\)\)" # Regex in info log is double-parented
  local expected_info_log_line="[INFO] Starting file watch. Command: $dummy_inw -qmr -e $default_events --exclude $info_log_regex $testdir/local/$TEST_SUBDIR_NAME"
  assert_output --partial "$expected_info_log_line" "gitwatch.sh did not log the correct inotifywait command"

  # 4. Cleanup
  unset GW_INW_BIN
  cd /tmp
}

@test "watcher_args_macos: Verifies correct arguments for fswatch" {
  if [ "$(uname)" != "Darwin" ];
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

  # The expected default events number (414)
  local default_events="414"

  # 2. Start gitwatch (should use fswatch syntax and arguments)
  # Expected args: --recursive --event <number> -E --exclude <regex> <path>
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to start

  # 3. Assert: Check log output for fswatch arguments
  run cat "$output_file"
  assert_output --partial "*** fswatch_CALLED ***" "Dummy fswatch was not executed"

  # --- FIX: Assert against the [INFO] log line ---
  local info_log_regex="\(\(\.git/\|\.git\$\)\)" # Regex in info log is double-parented
  local expected_info_log_line="[INFO] Starting file watch. Command: $dummy_fswatch --recursive --event $default_events -E --exclude $info_log_regex $testdir/local/$TEST_SUBDIR_NAME"
  assert_output --partial "$expected_info_log_line" "gitwatch.sh did not log the correct fswatch command"

  # 4. Cleanup
  unset GW_INW_BIN
  cd /tmp
}

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

@test "watcher_args_linux: Verifies correct arguments for inotifywait" {
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

  # The expected default events string
  local default_events="close_write,move,move_self,delete,create,modify"
  # The expected default exclude regex (must match the quoted regex output from printf %q in gitwatch.sh)
  local expected_regex="'(\\.git/|\\.git\\$)'"

  # 2. Start gitwatch (should use inotifywait syntax and arguments)
  # Expected args: -qmr -e <events> --exclude <regex> <path>
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to start

  # 3. Assert: Check log output for inotifywait arguments
  run cat "$output_file"
  assert_output --partial "*** inotifywait_CALLED ***" "Dummy inotifywait was not executed"
  # Check for core inotifywait args, matching the expected format exactly
  local expected_args="-qmr -e $default_events --exclude $expected_regex $testdir/local/$TEST_SUBDIR_NAME"
  assert_output --partial "ARGS: $expected_args" "Inotifywait default arguments not passed correctly"

  # 4. Cleanup
  unset GW_INW_BIN
  cd /tmp
}

@test "watcher_args_macos: Verifies correct arguments for fswatch" {
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

  # The expected default events number (414)
  local default_events="414"
  # The expected default exclude regex (must match the quoted regex output from printf %q in gitwatch.sh)
  local expected_regex="'(\\.git/|\\.git\\$)'"

  # 2. Start gitwatch (should use fswatch syntax and arguments)
  # Expected args: --recursive --event <number> -E --exclude <regex> <path>
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to start

  # 3. Assert: Check log output for fswatch arguments
  run cat "$output_file"
  assert_output --partial "*** fswatch_CALLED ***" "Dummy fswatch was not executed"
  # Check for core fswatch args, matching the expected format exactly
  local expected_args="--recursive --event $default_events -E --exclude $expected_regex $testdir/local/$TEST_SUBDIR_NAME"
  assert_output --partial "ARGS: $expected_args" "Fswatch default arguments not passed correctly"

  # 4. Cleanup
  unset GW_INW_BIN
  cd /tmp
}

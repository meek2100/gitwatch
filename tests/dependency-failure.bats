#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

@test "dependency_failure_syslog_S_flag_exits_with_code_2_if_logger_command_is_missing" {
  # This test temporarily manipulates the PATH environment variable to simulate a missing 'logger' command.
  local path_backup="$PATH"

  # 1. Temporarily remove common binary directories from PATH to simulate 'logger' missing
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr)?/s?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"

  # 2. Run gitwatch with -S, expecting it to fail the dependency check and exit
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -S "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Cleanup: Restore PATH *immediately* after run
  export PATH="$path_backup" # Restore PATH
  cd /tmp

  # 4. Assert exit code 2 and the error message (Assertions run *after* PATH is restored)
  assert_failure "Gitwatch should exit with non-zero status on missing dependency"
  assert_exit_code 2 "Gitwatch should exit with code 2 (Missing required command)"
  assert_output --partial "Error: Required command 'logger' not found (for -S syslog option)."
}

@test "dependency_failure_timeout_exits_with_code_2_if_timeout_command_is_missing" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"

  # 1. Temporarily remove common binary directories from PATH to simulate 'timeout' missing
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"

  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"

  # 2. Run gitwatch, expecting it to fail the dependency check and exit
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Cleanup: Restore PATH *immediately* after run
  export PATH="$path_backup" # Restore PATH
  cd /tmp

  # 4. Assert exit code 2 and the error message
  assert_failure "Gitwatch should exit with non-zero status on missing dependency"
  assert_exit_code 2 "Gitwatch should exit with code 2 (Missing required command)"
  assert_output --partial "Error: Required command 'timeout' not found."
}

# --- END OLD TESTS ---

@test "dependency_failure_git_exits_with_code_2_if_git_command_is_missing" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"

  # 1. Hide 'git'
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"

  # 2. Run gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Cleanup: Restore PATH *immediately* after run
  export PATH="$path_backup"
  cd /tmp

  # 4. Assert exit code 2 and the error message
  assert_failure
  assert_exit_code 2
  assert_output --partial "Error: Required command 'git' not found."
}

@test "dependency_failure_watcher_exits_with_code_2_if_watcher_inotifywait_fswatch_is_missing" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"
  local watcher_name=""
  local watcher_hint=""

  if [ "$RUNNER_OS" == "Linux" ]; then
    watcher_name="inotifywait"
    watcher_hint="inotify-tools"
  else
    watcher_name="fswatch"
    watcher_hint="brew install fswatch"
  fi

  # 1. Hide the watcher
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"

  # 2. Run gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Cleanup: Restore PATH *immediately* after run
  export PATH="$path_backup"
  cd /tmp

  # 4. Assert exit code 2 and the error message
  assert_failure
  assert_exit_code 2
  assert_output --partial "Error: Required command '$watcher_name' not found."
  assert_output --partial "$watcher_hint" # Check for the platform-specific hint
}

@test "dependency_failure_flock_exits_with_code_2_if_flock_command_is_missing_and_n_is_not_used" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Hide 'flock'
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"

  # 2. Run gitwatch *without -n*
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Cleanup: Restore PATH *immediately* after run
  export PATH="$path_backup"
  cd /tmp

  # 4. Assert: Script exits with failure code 2
  assert_failure "Gitwatch should have exited with an error"
  assert_exit_code 2 "Exit code should be 2 for missing dependency"

  # 5. Assert: Log output shows the ERROR message
  assert_output --partial "Error: Required command 'flock' not found"
  assert_output --partial "Install 'flock' or re-run with the -n flag"
  refute_output --partial "Proceeding without file locking."
  # This is the old warning
}

@test "dependency_failure_flock_with_n_flag_bypasses_check_and_runs_successfully_with_n" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Hide 'flock'
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"

  # 2. Run gitwatch *WITH -n* (in background)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -n "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow script to initialize

  # 3. Cleanup: Restore PATH *immediately*
  export PATH="$path_backup"

  # 4. Assert: Log output shows the bypass message
  run cat "$output_file"
  assert_output --partial "File locking explicitly disabled via -n flag."
  refute_output --partial "Error: Required command 'flock' not found" # Should not error out

  # 5. Assert: Process is *still running*
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process exited when it should have continued with -n"

  # 6. Final Cleanup
  cd /tmp
}

@test "dependency_failure_non_gnu_timeout_exits_with_code_2_if_timeout_is_not_gnu_coreutils" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"


  # 1. Create a dummy 'timeout' script that does NOT output "GNU coreutils"
  cat > "$DUMMY_BIN/timeout" << 'EOF'
#!/bin/bash
echo "This is BSD timeout"
exit 0
EOF
  chmod +x "$DUMMY_BIN/timeout"

  # 2. Prepend the dummy bin to the PATH
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$DUMMY_BIN:$PATH"

  # 3. Run gitwatch, which should fail the GNU version check
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME"

  # 4. Cleanup: Restore PATH *immediately* after run
  export PATH="$path_backup"
  cd /tmp

  # 5. Assert exit code 2 and the correct error
  assert_failure
  assert_exit_code 2
  assert_output --partial "Error: GNU 'timeout' (from coreutils) not found"
  assert_output --partial "Hint: If your GNU timeout is named 'gtimeout', run: export GW_TIMEOUT_BIN=gtimeout"
}

@test "dependency_failure_non_gnu_timeout_with_override_succeeds_with_gw_timeout_bin" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"

  # 1. Create a dummy 'timeout' (BSD version)
  cat > "$DUMMY_BIN/timeout" << 'EOF'
#!/bin/bash
echo "This is BSD timeout"
exit 0
EOF
  chmod +x "$DUMMY_BIN/timeout"

  # 2. Create a dummy 'gtimeout' (GNU version)
  local real_timeout_path
  real_timeout_path=$(command -v timeout) # Find the *real* GNU timeout on the runner
  cat > "$DUMMY_BIN/gtimeout" << EOF
#!/bin/bash
# Pass all args to the real GNU timeout
exec $real_timeout_path "\$@"
EOF
  chmod +x "$DUMMY_BIN/gtimeout"

  # 3. Prepend the dummy bin to the PATH and set override
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$DUMMY_BIN:$PATH"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export GW_TIMEOUT_BIN="$DUMMY_BIN/gtimeout"

  # 4. Run gitwatch.
  # It should find 'timeout', see it's non-GNU,
  # but then use GW_TIMEOUT_BIN, check 'gtimeout', see it's GNU, and run.
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow script to initialize

  # 5. Cleanup: Restore PATH *immediately*
  export PATH="$path_backup"
  unset GW_TIMEOUT_BIN

  # 6. Assert: Process is *still running*
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process exited when it should have continued"

  # 7. Assert: Log shows it found the GNU version at the override path
  run cat "$output_file"
  refute_output --partial "Error: GNU 'timeout' (from coreutils) not found"

  # 8. Final Cleanup
  cd /tmp
}

@test "dependency_failure_pkill_exits_with_code_2_if_pkill_command_is_missing" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"

  # 1. Hide 'pkill'
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"

  # 2. Run gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Cleanup: Restore PATH *immediately* after run
  export PATH="$path_backup"
  cd /tmp

  # 4. Assert exit code 2 and the error message
  assert_failure
  assert_exit_code 2
  assert_output --partial "Error: Required command 'pkill' not found."
  assert_output --partial "procps" # Part of the hint
}

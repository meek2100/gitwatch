#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

@test "dependency_failure_syslog: -S flag exits with code 2 if 'logger' command is missing" {
  # This test temporarily manipulates the PATH environment variable to simulate a missing 'logger' command.
  local path_backup="$PATH"

  # 1. Temporarily remove common binary directories from PATH to simulate 'logger' missing
  # We remove /usr/bin, /usr/sbin, /bin, /sbin, but preserve others.
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr)?/s?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"

  # 2. Assert that 'logger' is not found in the simulated PATH
  run command -v logger
  refute_success "Failed to simulate missing 'logger' command (command was still found in simulated PATH)"

  # 3. Run gitwatch with -S, expecting it to fail the dependency check and exit
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -S "$testdir/local/$TEST_SUBDIR_NAME"

  # 4. Assert exit code 2 and the error message
  assert_failure "Gitwatch should exit with non-zero status on missing dependency"
  assert_exit_code 2 "Gitwatch should exit with code 2 (Missing required command)"
  assert_output --partial "Error: Required command 'logger' not found (for -S syslog option)."

  # 5. Cleanup
  export PATH="$path_backup" # Restore PATH
  cd /tmp
}

@test "dependency_failure_timeout: Exits with code 2 if 'timeout' command is missing" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"

  # 1. Temporarily remove common binary directories from PATH to simulate 'timeout' missing
  # We remove coreutils locations where 'timeout' is usually found
  # Use a conservative filter to remove typical bin directories, but keep others like bats dependencies
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"

  # 2. Assert that 'timeout' is not found in the simulated PATH
  run command -v timeout
  refute_success "Failed to simulate missing 'timeout' command (command was still found in simulated PATH)"

  # 3. Run gitwatch, expecting it to fail the dependency check and exit
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # 4. Assert exit code 2 and the error message
  assert_failure "Gitwatch should exit with non-zero status on missing dependency"
  assert_exit_code 2 "Gitwatch should exit with code 2 (Missing required command)"
  assert_output --partial "Error: Required command 'timeout' not found."

  # 5. Cleanup
  export PATH="$path_backup" # Restore PATH
  cd /tmp
}

# --- END OLD TESTS ---

@test "dependency_failure_git: Exits with code 2 if 'git' command is missing" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"
  # 1. Hide 'git'
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"
  run command -v git
  refute_success "Failed to simulate missing 'git' command"

  # 2. Run gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Assert exit code 2 and the error message
  assert_failure
  assert_exit_code 2
  assert_output --partial "Error: Required command 'git' not found."

  # 4. Cleanup
  export PATH="$path_backup"
  cd /tmp
}

@test "dependency_failure_watcher: Exits with code 2 if watcher (inotifywait/fswatch) is missing" {
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
  run command -v "$watcher_name"
  refute_success "Failed to simulate missing '$watcher_name' command"

  # 2. Run gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Assert exit code 2 and the error message
  assert_failure
  assert_exit_code 2
  assert_output --partial "Error: Required command '$watcher_name' not found."
  assert_output --partial "$watcher_hint" # Check for the platform-specific hint

  # 4. Cleanup
  export PATH="$path_backup"
  cd /tmp
}

@test "dependency_failure_flock: Exits with code 2 if 'flock' command is missing (and -n is not used)" {
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
  run command -v flock
  refute_success "Failed to simulate missing 'flock' command"

  # 2. Run gitwatch *without -n*
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Assert: Script exits with failure code 2
  assert_failure "Gitwatch should have exited with an error"
  assert_exit_code 2 "Exit code should be 2 for missing dependency"

  # 4. Assert: Log output shows the ERROR message
  assert_output --partial "Error: Required command 'flock' not found"
  assert_output --partial "Install 'flock' or re-run with the -n flag"
  refute_output --partial "Proceeding without file locking." # This is the old warning

  # 5. Cleanup
  export PATH="$path_backup"
  cd /tmp
}

@test "dependency_failure_flock_with_n_flag: Bypasses check and runs successfully with -n" {
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
  run command -v flock
  refute_success "Failed to simulate missing 'flock' command"

  # 2. Run gitwatch *WITH -n*
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -n "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow script to initialize

  # 3. Assert: Log output shows the bypass message
  run cat "$output_file"
  assert_output --partial "File locking explicitly disabled via -n flag."
  refute_output --partial "Error: Required command 'flock' not found" # Should not error out

  # 4. Assert: Process is *still running*
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process exited when it should have continued with -n"

  # 5. Cleanup
  export PATH="$path_backup"
  cd /tmp
}

@test "dependency_failure_non_gnu_timeout: Exits with code 2 if 'timeout' is not GNU coreutils" {
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
  run command -v timeout
  assert_output --partial "$DUMMY_BIN/timeout" "Failed to override timeout command"

  # 3. Run gitwatch, which should fail the GNU version check
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME"

  # 4. Assert exit code 2 and the correct error
  assert_failure
  assert_exit_code 2
  assert_output --partial "Error: GNU 'timeout' (from coreutils) not found"
  assert_output --partial "Hint: If your GNU timeout is named 'gtimeout', run: export GW_TIMEOUT_BIN=gtimeout"

  # 5. Cleanup
  export PATH="$path_backup"
  cd /tmp
}

@test "dependency_failure_non_gnu_timeout_with_override: Succeeds with GW_TIMEOUT_BIN" {
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

  # 3. Prepend the dummy bin to the PATH
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$DUMMY_BIN:$PATH"
  # Set the override variable
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export GW_TIMEOUT_BIN="$DUMMY_BIN/gtimeout"

  # 4. Run gitwatch. It should find 'timeout', see it's non-GNU,
  # but then use GW_TIMEOUT_BIN, check 'gtimeout', see it's GNU, and run.
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow script to initialize

  # 5. Assert: Process is *still running*
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process exited when it should have continued"

  # 6. Assert: Log shows it found the GNU version at the override path
  run cat "$output_file"
  refute_output --partial "Error: GNU 'timeout' (from coreutils) not found"

  # 7. Cleanup
  export PATH="$path_backup"
  unset GW_TIMEOUT_BIN
  cd /tmp
}

@test "dependency_failure_pkill: Exits with code 2 if 'pkill' command is missing" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"
  # 1. Hide 'pkill'
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"
  run command -v pkill
  refute_success "Failed to simulate missing 'pkill' command"

  # 2. Run gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Assert exit code 2 and the error message
  assert_failure
  assert_exit_code 2
  assert_output --partial "Error: Required command 'pkill' not found."
  assert_output --partial "procps" # Part of the hint

  # 4. Cleanup
  export PATH="$path_backup"
  cd /tmp
}

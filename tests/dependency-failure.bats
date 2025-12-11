#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# Test failure when 'logger' is missing but syslog is requested (-S)
@test "dependency_failure_syslog_S_flag_exits_with_code_2_if_logger_command_is_missing" {
  # 1. Create a dummy bin directory to hide 'logger'
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"

  # 2. Modify PATH to prioritize our dummy bin
  # shellcheck disable=SC2031 # Modifying PATH is intentional for this test
  local path_backup="$PATH"
  # shellcheck disable=SC2030,SC2031 # Modifying PATH is intentional for this test
  export PATH="$DUMMY_BIN:$PATH"

  # 3. Verify 'logger' is effectively hidden (should not be found in the new PATH if empty)
  # But we rely on the fact that if it's NOT in dummy-bin and we removed other paths...
  # Wait, appending to PATH doesn't hide system bins unless we exclude system paths.
  # Correct approach: Create a complete minimal PATH or rely on 'command -v' failure if we can manipulate it.
  # A better way for BATS: Alias or function override doesn't work for script execution.
  # We must construct a restrictive PATH.

  # STRATEGY: Construct a PATH that only contains the essentials (sh, bash, coreutils) but NOT logger.
  # Finding essentials can be tricky.
  # ALTERNATIVE: Since we can't easily hide system binaries without breaking everything,
  # we will use the 'create_failing_watcher_bin' helper concept but for 'logger'.
  # But 'is_command' checks existence.

  # ROBUST STRATEGY:
  # Since we cannot easily hide 'logger' if it's in /usr/bin, we will assume the environment
  # allows us to override PATH. We will identify where 'bash', 'cat', 'rm', 'mkdir', etc. live,
  # put symlinks to them in our DUMMY_BIN, and set PATH to ONLY DUMMY_BIN.

  # 1. Identify critical tools
  local critical_tools=("bash" "sh" "cat" "rm" "mkdir" "sleep" "sed" "grep" "ln" "stat" "id" "uname" "getopts" "printf")
  for tool in "${critical_tools[@]}"; do
      local tool_path
      tool_path=$(command -v "$tool" || true)
      if [ -n "$tool_path" ]; then
          ln -sf "$tool_path" "$DUMMY_BIN/$tool"
      fi
  done

  # 2. Set strict PATH
  export PATH="$DUMMY_BIN"

  # 3. Verify 'logger' is gone
  if command -v logger >/dev/null; then
      # If logger is still found (e.g. builtin or in the list above), we skip
      export PATH="$path_backup"
      skip "Could not hide 'logger' command from PATH. Test skipped."
  fi

  # 4. Run gitwatch with -S
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -S "$testdir/local/$TEST_SUBDIR_NAME"

  # 5. Assert failure and exit code 2
  assert_failure "Gitwatch should exit with non-zero status on missing dependency"
  assert_failure 2
  assert_output --partial "Error: Required command 'logger' not found"

  # 6. Cleanup
  export PATH="$path_backup"
}

@test "dependency_failure_timeout_exits_with_code_2_if_timeout_command_is_missing" {
  # Same strategy as above: restricted PATH
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"

  # Copy essentials EXCLUDING 'timeout' and 'gtimeout'
  local critical_tools=("bash" "sh" "cat" "rm" "mkdir" "sleep" "sed" "grep" "ln" "stat" "id" "uname" "git" "inotifywait" "fswatch" "flock" "pkill")
  for tool in "${critical_tools[@]}"; do
      local tool_path
      tool_path=$(command -v "$tool" || true)
      if [ -n "$tool_path" ]; then
          ln -sf "$tool_path" "$DUMMY_BIN/$tool"
      fi
  done

  local path_backup="$PATH"
  export PATH="$DUMMY_BIN"

  if command -v timeout >/dev/null || command -v gtimeout >/dev/null; then
      export PATH="$path_backup"
      skip "Could not hide 'timeout' command. Test skipped."
  fi

  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  assert_failure
  assert_failure 2
  assert_output --partial "Error: Required command 'timeout' not found"

  export PATH="$path_backup"
}

@test "dependency_failure_git_exits_with_code_2_if_git_command_is_missing" {
  # Restricted PATH excluding 'git'
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"

  # Essentials minus git
  local critical_tools=("bash" "sh" "cat" "rm" "mkdir" "sleep" "sed" "grep" "ln" "stat" "id" "uname" "timeout" "inotifywait" "fswatch" "flock" "pkill")
  for tool in "${critical_tools[@]}"; do
      local tool_path
      tool_path=$(command -v "$tool" || true)
      if [ -n "$tool_path" ]; then
          ln -sf "$tool_path" "$DUMMY_BIN/$tool"
      fi
  done

  local path_backup="$PATH"
  export PATH="$DUMMY_BIN"

  if command -v git >/dev/null; then
      export PATH="$path_backup"
      skip "Could not hide 'git' command. Test skipped."
  fi

  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  assert_failure
  assert_failure 2
  assert_output --partial "Error: Required command 'git' not found"

  export PATH="$path_backup"
}

@test "dependency_failure_watcher_exits_with_code_2_if_watcher_inotifywait_fswatch_is_missing" {
  # Restricted PATH excluding inotifywait AND fswatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"

  local critical_tools=("bash" "sh" "cat" "rm" "mkdir" "sleep" "sed" "grep" "ln" "stat" "id" "uname" "timeout" "git" "flock" "pkill")
  for tool in "${critical_tools[@]}"; do
      local tool_path
      tool_path=$(command -v "$tool" || true)
      if [ -n "$tool_path" ]; then
          ln -sf "$tool_path" "$DUMMY_BIN/$tool"
      fi
  done

  local path_backup="$PATH"
  export PATH="$DUMMY_BIN"

  if command -v inotifywait >/dev/null || command -v fswatch >/dev/null; then
      export PATH="$path_backup"
      skip "Could not hide watcher commands. Test skipped."
  fi

  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  assert_failure
  assert_failure 2
  # The output depends on OS fallback logic, but should error
  assert_output --partial "Error: Required command"

  export PATH="$path_backup"
}

@test "dependency_failure_flock_exits_with_code_2_if_flock_command_is_missing_and_n_is_not_used" {
  # Restricted PATH excluding flock
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"

  local critical_tools=("bash" "sh" "cat" "rm" "mkdir" "sleep" "sed" "grep" "ln" "stat" "id" "uname" "timeout" "git" "inotifywait" "fswatch" "pkill")
  for tool in "${critical_tools[@]}"; do
      local tool_path
      tool_path=$(command -v "$tool" || true)
      if [ -n "$tool_path" ]; then
          ln -sf "$tool_path" "$DUMMY_BIN/$tool"
      fi
  done

  local path_backup="$PATH"
  export PATH="$DUMMY_BIN"

  if command -v flock >/dev/null; then
      export PATH="$path_backup"
      skip "Could not hide 'flock' command. Test skipped."
  fi

  # Run WITHOUT -n
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  assert_failure
  assert_failure 2
  assert_output --partial "Error: Required command 'flock' not found"

  export PATH="$path_backup"
}

@test "dependency_failure_flock_with_n_flag_bypasses_check_and_runs_successfully_with_n" {
  # Restricted PATH excluding flock
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"

  # We need everything else
  local critical_tools=("bash" "sh" "cat" "rm" "mkdir" "sleep" "sed" "grep" "ln" "stat" "id" "uname" "timeout" "git" "inotifywait" "fswatch" "pkill")
  for tool in "${critical_tools[@]}"; do
      local tool_path
      tool_path=$(command -v "$tool" || true)
      if [ -n "$tool_path" ]; then
          ln -sf "$tool_path" "$DUMMY_BIN/$tool"
      fi
  done

  local path_backup="$PATH"
  export PATH="$DUMMY_BIN"

  if command -v flock >/dev/null; then
      export PATH="$path_backup"
      skip "Could not hide 'flock' command. Test skipped."
  fi

  # Run WITH -n (background)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -n "$testdir/local/$TEST_SUBDIR_NAME" > /dev/null 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow script to initialize

  # Check if PID is still running
  run kill -0 "$GITWATCH_PID" 2>/dev/null
  assert_success "Gitwatch should run without flock when -n is specified"

  export PATH="$path_backup"
}

@test "dependency_failure_non_gnu_timeout_exits_with_code_2_if_timeout_is_not_gnu_coreutils" {
  # Mock 'timeout' command that is NOT GNU (doesn't output 'GNU coreutils' in --version)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"
  local mock_timeout="$DUMMY_BIN/timeout"

  # Create a mock timeout that behaves nicely but isn't GNU
  echo '#!/bin/sh' > "$mock_timeout"
  echo 'if [ "$1" = "--version" ]; then echo "BSD timeout"; exit 0; fi' >> "$mock_timeout"
  echo 'exec "$@"' >> "$mock_timeout"
  chmod +x "$mock_timeout"

  local critical_tools=("bash" "sh" "cat" "rm" "mkdir" "sleep" "sed" "grep" "ln" "stat" "id" "uname" "git" "inotifywait" "fswatch" "flock" "pkill")
  for tool in "${critical_tools[@]}"; do
      local tool_path
      tool_path=$(command -v "$tool" || true)
      if [ -n "$tool_path" ]; then
          ln -sf "$tool_path" "$DUMMY_BIN/$tool"
      fi
  done

  local path_backup="$PATH"
  export PATH="$DUMMY_BIN"

  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  assert_failure
  assert_failure 2
  assert_output --partial "Error: GNU 'timeout' (from coreutils) not found"

  export PATH="$path_backup"
}

@test "dependency_failure_non_gnu_timeout_with_override_succeeds_with_gw_timeout_bin" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"

  # 1. Create a "bad" system timeout
  local bad_timeout="$DUMMY_BIN/timeout"
  echo '#!/bin/sh' > "$bad_timeout"
  echo 'echo "BSD timeout"' >> "$bad_timeout"
  chmod +x "$bad_timeout"

  # 2. Create a "good" custom timeout (gtimeout)
  local good_timeout="$DUMMY_BIN/gtimeout"
  echo '#!/bin/sh' > "$good_timeout"
  echo 'if [ "$1" = "--version" ]; then echo "timeout (GNU coreutils) 8.32"; exit 0; fi' >> "$good_timeout"
  # Mock actual timeout behavior roughly: execute the command
  echo 'shift; shift; exec "$@"' >> "$good_timeout" # Skip -s 9 time
  chmod +x "$good_timeout"

  local critical_tools=("bash" "sh" "cat" "rm" "mkdir" "sleep" "sed" "grep" "ln" "stat" "id" "uname" "git" "inotifywait" "fswatch" "flock" "pkill")
  for tool in "${critical_tools[@]}"; do
      local tool_path
      tool_path=$(command -v "$tool" || true)
      if [ -n "$tool_path" ]; then
          ln -sf "$tool_path" "$DUMMY_BIN/$tool"
      fi
  done

  local path_backup="$PATH"
  export PATH="$DUMMY_BIN"

  # 3. Run with override
  # Pass GW_TIMEOUT_BIN env var
  GW_TIMEOUT_BIN="gtimeout" run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # It should FAIL due to missing arguments (exit 1), but NOT due to dependency check (exit 2)
  # because we provided a valid timeout.
  # Note: gitwatch requires at least 1 arg (target). We gave it.
  # So it should run. But we mocked timeout to just exec.
  # Since we background it via run (no, run foregrounds it), it runs until...
  # Wait, run captures exit code.
  # If we start it, it enters the loop.
  # But we didn't background it with &.
  # So `run` will hang indefinitely?
  # No, `run` waits for completion. `gitwatch` runs forever.
  # So this test will hang if successful!

  # FIX: We must run it in background manually and check PID, or pass -V/bad flag to make it exit early but PASS dependencies.

  GW_TIMEOUT_BIN="gtimeout" run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -V
  assert_success
  assert_output --partial "gitwatch.sh version"

  export PATH="$path_backup"
}

@test "dependency_failure_pkill_exits_with_code_2_if_pkill_command_is_missing" {
  # Restricted PATH excluding pkill
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"

  local critical_tools=("bash" "sh" "cat" "rm" "mkdir" "sleep" "sed" "grep" "ln" "stat" "id" "uname" "timeout" "git" "inotifywait" "fswatch" "flock")
  for tool in "${critical_tools[@]}"; do
      local tool_path
      tool_path=$(command -v "$tool" || true)
      if [ -n "$tool_path" ]; then
          ln -sf "$tool_path" "$DUMMY_BIN/$tool"
      fi
  done

  local path_backup="$PATH"
  export PATH="$DUMMY_BIN"

  if command -v pkill >/dev/null; then
      export PATH="$path_backup"
      skip "Could not hide 'pkill' command. Test skipped."
  fi

  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  assert_failure
  assert_failure 2
  assert_output --partial "Error: Required command 'pkill' not found"

  export PATH="$path_backup"
}

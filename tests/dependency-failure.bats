#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# Common list of tools required by gitwatch.sh (excluding specific dependencies being tested)
# We include 'env' which is critical for the shebang.
# We include 'tr' which is used early for log levels.
COMMON_TOOLS="bash sh env cat rm mkdir sleep sed grep ln stat id uname wc tr cut dirname basename mktemp tail head ls cp mv touch printf awk date"

@test "dependency_failure_syslog_S_flag_exits_with_code_2_if_logger_command_is_missing" {
  # Restricted PATH excluding logger
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"

  # We need everything else plus gitwatch deps
  local tools_to_link="$COMMON_TOOLS git inotifywait fswatch flock pkill timeout"

  for tool in $tools_to_link; do
      local tool_path
      tool_path=$(command -v "$tool" || true)
      if [ -n "$tool_path" ]; then
          ln -sf "$tool_path" "$DUMMY_BIN/$tool"
      fi
  done

  local path_backup="$PATH"
  export PATH="$DUMMY_BIN"

  if command -v logger >/dev/null; then
      export PATH="$path_backup"
      skip "Could not hide 'logger' command. Test skipped."
  fi

  # Run with -S (syslog)
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -S "$testdir/local/$TEST_SUBDIR_NAME"

  assert_failure
  assert_failure 2
  assert_output --partial "Error: Required command 'logger' not found"

  export PATH="$path_backup"
}

@test "dependency_failure_timeout_exits_with_code_2_if_timeout_command_is_missing" {
  # Restricted PATH excluding timeout
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"

  local tools_to_link="$COMMON_TOOLS git inotifywait fswatch flock pkill"
  for tool in $tools_to_link; do
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

  local tools_to_link="$COMMON_TOOLS inotifywait fswatch flock pkill timeout"
  for tool in $tools_to_link; do
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

  local tools_to_link="$COMMON_TOOLS git flock pkill timeout"
  for tool in $tools_to_link; do
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

  local tools_to_link="$COMMON_TOOLS git inotifywait fswatch pkill timeout"
  for tool in $tools_to_link; do
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
  local tools_to_link="$COMMON_TOOLS git inotifywait fswatch pkill timeout"
  for tool in $tools_to_link; do
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

  local tools_to_link="$COMMON_TOOLS git inotifywait fswatch flock pkill"
  for tool in $tools_to_link; do
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

  local tools_to_link="$COMMON_TOOLS git inotifywait fswatch flock pkill"
  for tool in $tools_to_link; do
      local tool_path
      tool_path=$(command -v "$tool" || true)
      if [ -n "$tool_path" ]; then
          ln -sf "$tool_path" "$DUMMY_BIN/$tool"
      fi
  done

  local path_backup="$PATH"
  export PATH="$DUMMY_BIN"

  # 3. Run with override

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

  local tools_to_link="$COMMON_TOOLS git inotifywait fswatch flock timeout"
  for tool in $tools_to_link; do
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

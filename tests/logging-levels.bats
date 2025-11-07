#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# --- NEW setup/teardown for this file ---
local path_backup=""
local DUMMY_BIN=""

setup() {
  # Call the common setup first
  _common_setup 0

  # Set up manual mock for the FATAL test
  path_backup="$PATH"
  # shellcheck disable=SC2154 # testdir is sourced
  DUMMY_BIN="$testdir/dummy-bin"
  mkdir -p "$DUMMY_BIN"
  echo "#!/bin/bash" > "$DUMMY_BIN/flock"
  echo "exit 127" >> "$DUMMY_BIN/flock"
  chmod +x "$DUMMY_BIN/flock"
  export PATH="$DUMMY_BIN:$PATH"
}

teardown() {
  # Restore the path
  export PATH="$path_backup"
  # Call the common teardown
  _common_teardown
}
# --- END NEW setup/teardown ---


# --- HELPER: Create Mock Git ---
create_mock_git_fail_commit() {
  local real_path="$1"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local dummy_path="$testdir/bin/git-fail-commit"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  mkdir -p "$testdir/bin"

  cat > "$dummy_path" << EOF
#!/usr/bin/env bash
echo "# MOCK_GIT: Received command: \$@" >&2
if [ "\$1" = "commit" ];
then
  echo "# MOCK_GIT: Simulating 'git commit' failure" >&2
  exit 1
else
  exec $real_path "\$@"
fi
EOF
  chmod +x "$dummy_path"
  echo "$dummy_path"
}


@test "logging_level_FATAL: -o FATAL only shows fatal errors" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Mock 'flock' to be missing
  # (This is now handled by the file's setup() function)
  # export BATS_MOCK_DEPENDENCIES="flock"

  # 2. Run gitwatch with -o FATAL (or 1)
  # It should fail, and only the FATAL error should be in the log.
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -o FATAL "$testdir/local/$TEST_SUBDIR_NAME"
  assert_failure
  assert_exit_code 2

  # 3. Check logs
  assert_output --partial "[FATAL] Error: Required command 'flock' not found"
}

@test "logging_level_ERROR: -o ERROR shows ERROR and FATAL" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create a mock git that fails on 'commit'
  local real_git_path
  real_git_path=$(command -v git)
  local dummy_git
  dummy_git=$(create_mock_git_fail_commit "$real_git_path")
  export GW_GIT_BIN="$dummy_git"

  # 2. Start gitwatch with -o ERROR
  # --- FIX: Replaced > "$output_file" 2&>1 & with &> "$output_file" & ---
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -o ERROR "$testdir/local/$TEST_SUBDIR_NAME" &> "$output_file" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 3. Trigger a change
  echo "change" >> file.txt
  verbose_echo "# DEBUG: Waiting ${WAITTIME}s for commit to fail..."
  sleep "$WAITTIME"

  # 4. Check logs
  run cat "$output_file"
  assert_output --partial "[ERROR] 'git commit' failed with exit code 1"
  refute_output --partial "[WARN]"
  refute_output --partial "[INFO]"
  refute_output --partial "[DEBUG]"
  refute_output --partial "[TRACE]"

  # 5. Cleanup
  unset GW_GIT_BIN
  cd /tmp
}

@test "logging_level_WARN: -o WARN shows WARN, ERROR, FATAL" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Unset git config to trigger warning
  git config --global --unset user.name || true
  git config --global --unset user.email || true

  # 2. Start gitwatch with -o WARN (or 3)
  # --- FIX: Replaced > "$output_file" 2&>1 & with &> "$output_file" & ---
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -o 3 "$testdir/local/$TEST_SUBDIR_NAME" &> "$output_file" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Wait for config check to run

  # 3. Check logs
  run cat "$output_file"
  assert_output --partial "[WARN] Warning: 'user.name' or 'user.email' is not set"
  refute_output --partial "[INFO]"
  refute_output --partial "[DEBUG]"
  refute_output --partial "[TRACE]"

  # 4. Cleanup
  git config --global user.name "BATS Test"
  git config --global user.email "test@example.com"
  cd /tmp
}

@test "logging_level_INFO: -o INFO (default) shows INFO, WARN, ERROR, FATAL" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Start gitwatch with -o INFO
  # --- FIX: Replaced > "$output_file" 2&>1 & with &> "$output_file" & ---
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -o INFO "$testdir/local/$TEST_SUBDIR_NAME" &> "$output_file" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Wait for startup

  # 2. Check logs
  run cat "$output_file"
  assert_output --partial "[INFO] Starting file watch. Command:"
  refute_output --partial "[DEBUG]"
  refute_output --partial "[TRACE]"

  cd /tmp
}

@test "logging_level_DEBUG: -o DEBUG (or -v) shows DEBUG and up" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Start gitwatch with -v
  # --- FIX: Replaced > "$output_file" 2&>1 & with &> "$output_file" & ---
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" &> "$output_file" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Wait for startup

  # 2. Check logs for DEBUG messages
  run cat "$output_file"
  assert_output --partial "[INFO] Starting file watch. Command:"
  assert_output --partial "[DEBUG] Log level set to 5."
  assert_output --partial "[DEBUG] Acquired main instance lock"
  refute_output --partial "[TRACE]"

  cd /tmp
}

@test "logging_level_TRACE: -o TRACE (or 6) shows TRACE and up" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Start gitwatch with -o TRACE
  # --- FIX: Replaced > "$output_file" 2&>1 & with &> "$output_file" & ---
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -o TRACE "$testdir/local/$TEST_SUBDIR_NAME" &> "$output_file" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Wait for startup

  # 2. Trigger a change to get TRACE messages from commit logic
  echo "trace test" >> file.txt
  verbose_echo "# DEBUG: Waiting ${WAITTIME}s for commit..."
  sleep "$WAITTIME"

  # 3. Check logs for TRACE messages
  run cat "$output_file"
  assert_output --partial "[DEBUG] Acquired main instance lock"
  assert_output --partial "[TRACE] Entering function _get_path_hash"
  assert_output --partial "[TRACE] Entering function perform_commit"
  assert_output --partial "[TRACE] Entering commit lock subshell"
  assert_output --partial "[TRACE] Entering function _perform_commit"
  assert_output --partial "[TRACE] Entering function generate_commit_message"

  cd /tmp
}

#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# Get the timeout from the global test args (e.g., "-v -t 10")
# This is more robust than hard-coding '10'
TEST_TIMEOUT=$(echo "$GITWATCH_TEST_ARGS" | grep -oE -- '-t [0-9]+' | cut -d' ' -f2 || echo 10)

# --- Setup Function ---
# This test file requires a remote for push/pull tests
setup() {
  setup_with_remote
}

# --- Helper ---
# Helper to poll a log file for a specific message
wait_for_log_message() {
  local file="$1"
  local pattern="$2"
  local max_attempts=15 # Total wait 15s (must be > $TEST_TIMEOUT)
  local delay=1
  local attempt=1

  while (( attempt <= max_attempts )); do
    verbose_echo "# DEBUG: Checking log '$file' for '$pattern' (Attempt $attempt/$max_attempts)..."
    if [ -f "$file" ] && grep -q "$pattern" "$file";
    then
      verbose_echo "# DEBUG: Found log message."
      return 0
    fi
    sleep "$delay"
    (( attempt++ ))
  done

  verbose_echo "# DEBUG: Timeout waiting for log message: '$pattern'"
  return 1
}

# --- Helper ---
# Creates a mock 'git' binary that hangs *only* on a specific command
create_mock_git_hang_on_cmd() {
  local hang_cmd="$1"
  local real_path
  real_path=$(command -v git)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local dummy_path="$testdir/bin/git-mock-hang"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  mkdir -p "$testdir/bin"

  # Create the mock script
  cat > "$dummy_path" << EOF
#!/usr/bin/env bash
# Mock Git script
echo "# MOCK_GIT: Received command: \$@" >&2

if [ "\$1" = "$hang_cmd" ];
then
  echo "# MOCK_GIT: Hanging on '$hang_cmd', will sleep 600s..." >&2
  sleep 600
else
  # Pass all other commands (config, add, commit, rev-parse) to the real git
  exec $real_path "\$@"
fi
EOF

  chmod +x "$dummy_path"
  echo "$dummy_path"
}

# --- NEW HELPER: Find stdbuf ---
# Finds the correct 'stdbuf' command (stdbuf on Linux, gstdbuf on macOS)
get_stdbuf_cmd() {
  if command -v "stdbuf" &>/dev/null;
  then
    echo "stdbuf"
  elif command -v "gstdbuf" &>/dev/null;
  then
    echo "gstdbuf"
  else
    # Fallback to 'stdbuf' and let it fail if not found
    echo "stdbuf"
  fi
}


@test "timeout_git_push: Ensures hung git push command is terminated and logged" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup: Create a hanging dummy 'git' binary that hangs on 'push'
  local dummy_git_path
  dummy_git_path=$(create_mock_git_hang_on_cmd "push")

  # 2. Set environment variable to force gitwatch to use the hanging binary
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export GW_GIT_BIN="$dummy_git_path"

  # 3. Start gitwatch with a remote, short sleep time, and explicit default timeout
  local test_sleep_time=1
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"

  verbose_echo "# DEBUG: Starting gitwatch with hanging 'push' binary and sleep=${test_sleep_time}s and -t ${TEST_TIMEOUT}"

  # --- FIX: Use stdbuf helper ---
  local stdbuf_cmd
  stdbuf_cmd=$(get_stdbuf_cmd)
  verbose_echo "# DEBUG: Using stdbuf command: '$stdbuf_cmd'"
  # --- MODIFIED: Changed redirection to &> ---
  "$stdbuf_cmd" -oL -eL "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -s "$test_sleep_time" -r origin "$target_dir" &> "$output_file" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$target_dir"
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger timeout" >> timeout_file.txt

  # 5. Wait for the script's internal timeout to be triggered.
  run wait_for_log_message "$output_file" "ERROR: 'git push' timed out"
  assert_success "Did not find push timeout error message in log."
  # 6. Assert: The commit/push failed due to timeout
  run cat "$output_file"
  assert_output --partial "# MOCK_GIT: Hanging on 'push'" "Hanging dummy git binary was not called."
  assert_output --partial "ERROR: 'git push' timed out after ${TEST_TIMEOUT} seconds." "Push timeout error was not logged."
  # 7. Cleanup
  unset GW_GIT_BIN
  rm -f "$dummy_git_path"
  cd /tmp
}

@test "timeout_git_pull_rebase: Ensures hung git pull command is terminated and logged" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup: Create a hanging dummy 'git' binary that hangs on 'pull'
  local dummy_git_path
  dummy_git_path=$(create_mock_git_hang_on_cmd "pull")

  # 2. Set environment variable
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export GW_GIT_BIN="$dummy_git_path"

  # 3. Start gitwatch with remote and PULL_BEFORE_PUSH (-R), and explicit default timeout
  local test_sleep_time=1
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"

  verbose_echo "# DEBUG: Starting gitwatch with hanging 'pull' binary and -R and -t ${TEST_TIMEOUT}"
  # --- FIX: Use stdbuf helper ---
  local stdbuf_cmd
  stdbuf_cmd=$(get_stdbuf_cmd)
  verbose_echo "# DEBUG: Using stdbuf command: '$stdbuf_cmd'"
  # --- MODIFIED: Changed redirection to &> ---
  "$stdbuf_cmd" -oL -eL "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -s "$test_sleep_time" -r origin -R "$target_dir" &> "$output_file" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$target_dir"
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger pull timeout" >> pull_timeout_file.txt

  # 5. Wait for the script's internal timeout (10s) to be triggered.
  run wait_for_log_message "$output_file" "ERROR: 'git pull' timed out"
  assert_success "Did not find pull timeout error message in log."
  # 6. Assert: The commit succeeded, but the subsequent pull failed due to timeout
  run cat "$output_file"
  assert_output --partial "Running git commit command:" "Commit should succeed before pull attempt."
  assert_output --partial "# MOCK_GIT: Hanging on 'pull'" "Hanging dummy git binary was not called for pull."
  assert_output --partial "ERROR: 'git pull' timed out after ${TEST_TIMEOUT} seconds. Skipping push." "Pull timeout error was not logged."
  # 7. Cleanup
  unset GW_GIT_BIN
  rm -f "$dummy_git_path"
  cd /tmp
}

@test "timeout_git_commit: Ensures hung git commit command is terminated and logged" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup: Create a hanging dummy 'git' binary that hangs on 'commit'
  local dummy_git_path
  dummy_git_path=$(create_mock_git_hang_on_cmd "commit")

  # 2. Set environment variable to force gitwatch to use the hanging binary
  # We must use the full path to the hanging binary here.
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export GW_GIT_BIN="$dummy_git_path"

  # 3. Start gitwatch
  local test_sleep_time=1
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"
  local initial_hash

  cd "$target_dir"
  initial_hash=$(git log -1 --format=%H)
  verbose_echo "# DEBUG: Starting gitwatch with hanging 'commit' binary and -t ${TEST_TIMEOUT}"

  # --- FIX: Use stdbuf helper ---
  local stdbuf_cmd
  stdbuf_cmd=$(get_stdbuf_cmd)
  verbose_echo "# DEBUG: Using stdbuf command: '$stdbuf_cmd'"
  # --- MODIFIED: Changed redirection to &> ---
  "$stdbuf_cmd" -oL -eL "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -s "$test_sleep_time" "$target_dir" &> "$output_file" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger commit timeout" >> commit_timeout_file.txt

  # 5. Wait for the script's internal timeout (10s) to be triggered.
  run wait_for_log_message "$output_file" "ERROR: 'git commit' timed out"
  assert_success "Did not find commit timeout error message in log."
  # 6. Assert: Commit did NOT happen, and timeout error was logged
  run git log -1 --format=%H
  assert_equal "$initial_hash" "$output" "Commit hash should NOT change"

  run cat "$output_file"
  assert_output --partial "# MOCK_GIT: Hanging on 'commit'" "Hanging dummy git binary was not called for commit."
  assert_output --partial "ERROR: 'git commit' timed out after ${TEST_TIMEOUT} seconds." "Commit timeout error was not logged."
  # 7. Cleanup
  unset GW_GIT_BIN
  rm -f "$dummy_git_path"
  cd /tmp
}

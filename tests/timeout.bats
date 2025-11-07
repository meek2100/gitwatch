#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers (includes create_hanging_bin)
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

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
    if [ -f "$file" ] && grep -q "$pattern" "$file"; then
      verbose_echo "# DEBUG: Found log message."
      return 0
    fi
    sleep "$delay"
    (( attempt++ ))
  done

  verbose_echo "# DEBUG: Timeout waiting for log message: '$pattern'"
  return 1
}

@test "timeout_git_push: Ensures hung git push command is terminated and logged" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup: Create a hanging dummy 'git' binary
  # We rename the hanging binary to be what GW_GIT_BIN expects.
  local dummy_git_path
  dummy_git_path=$(create_hanging_bin "git")

  # 2. Set environment variable to force gitwatch to use the hanging binary
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export GW_GIT_BIN="$dummy_git_path"

  # 3. Start gitwatch with a remote, short sleep time, and explicit default timeout
  local test_sleep_time=1
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"

  verbose_echo "# DEBUG: Starting gitwatch with hanging git binary and sleep=${test_sleep_time}s and -t ${TEST_TIMEOUT}"

  # Note: GITWATCH_TEST_ARGS already contains the -t flag
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -s "$test_sleep_time" -r origin "$target_dir" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$target_dir"
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger timeout" >> timeout_file.txt

  # 5. Wait for the debounce period (1s) plus a small buffer, then wait for the
  # expected timeout period (10s) to be triggered by the script itself.
  local total_wait_time=12
  verbose_echo "# DEBUG: Waiting ${total_wait_time}s for commit attempt and expected timeout failure..."
  # Wait for a fraction of the timeout period, just enough to see the failure log
  sleep "$total_wait_time"

  # 6. Assert: The commit/push failed due to timeout
  run cat "$output_file"
  assert_output --partial "*** DUMMY HANG: git called, will sleep 600s ***" "Hanging dummy git binary was not called."
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

  # 1. Setup: Create a hanging dummy 'git' binary
  local dummy_git_path
  dummy_git_path=$(create_hanging_bin "git")

  # 2. Set environment variable
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export GW_GIT_BIN="$dummy_git_path"

  # 3. Start gitwatch with remote and PULL_BEFORE_PUSH (-R), and explicit default timeout
  local test_sleep_time=1
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"

  verbose_echo "# DEBUG: Starting gitwatch with hanging git binary and -R and -t ${TEST_TIMEOUT}"
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -s "$test_sleep_time" -r origin -R "$target_dir" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$target_dir"
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger pull timeout" >> pull_timeout_file.txt

  # 5. Wait for the script's internal timeout (10s) to be triggered.
  local total_wait_time=12
  verbose_echo "# DEBUG: Waiting ${total_wait_time}s for commit/pull attempt and expected timeout failure..."
  sleep "$total_wait_time"

  # 6. Assert: The commit succeeded, but the subsequent pull failed due to timeout
  run cat "$output_file"
  assert_output --partial "Running git commit command:" "Commit should succeed before pull attempt."
  assert_output --partial "*** DUMMY HANG: git called, will sleep 600s ***" "Hanging dummy git binary was not called for pull."
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

  # 1. Setup: Create a hanging dummy 'git' binary
  # This dummy binary will be called via 'timeout 10 /path/to/git-hanging commit...'
  local dummy_git_path
  dummy_git_path=$(create_hanging_bin "git-commit-hang")

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
  verbose_echo "# DEBUG: Starting gitwatch with hanging commit binary and -t ${TEST_TIMEOUT}"

  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -s "$test_sleep_time" "$target_dir" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger commit timeout" >> commit_timeout_file.txt

  # 5. Wait for the script's internal timeout (10s) to be triggered.
  local total_wait_time=12
  verbose_echo "# DEBUG: Waiting ${total_wait_time}s for commit attempt and expected timeout failure..."
  sleep "$total_wait_time"

  # 6. Assert: Commit did NOT happen, and timeout error was logged
  run git log -1 --format=%H
  assert_equal "$initial_hash" "$output" "Commit hash should NOT change"

  run cat "$output_file"
  assert_output --partial "*** DUMMY HANG: git-commit-hang called, will sleep 600s ***" "Hanging dummy git binary was not called for commit."
  assert_output --partial "ERROR: 'git commit' timed out after ${TEST_TIMEOUT} seconds." "Commit timeout error was not logged."

  # 7. Cleanup
  unset GW_GIT_BIN
  rm -f "$dummy_git_path"
  cd /tmp
}

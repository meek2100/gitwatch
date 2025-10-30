#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers (includes create_hanging_bin)
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# Use the default timeout of 60 seconds in assertions
DEFAULT_TIMEOUT=60

@test "timeout_git_push: Ensures hung git push command is terminated and logged" {
  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup: Create a hanging dummy 'git' binary
  # We rename the hanging binary to be what GW_GIT_BIN expects.
  local dummy_git_path
  dummy_git_path=$(create_hanging_bin "git")

  # 2. Set environment variable to force gitwatch to use the hanging binary
  export GW_GIT_BIN="$dummy_git_path"

  # 3. Start gitwatch with a remote, short sleep time, and explicit default timeout
  local test_sleep_time=1
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"

  echo "# DEBUG: Starting gitwatch with hanging git binary and sleep=${test_sleep_time}s and -t ${DEFAULT_TIMEOUT}" >&3


  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s "$test_sleep_time" -t "$DEFAULT_TIMEOUT" -r origin "$target_dir" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  cd "$target_dir"
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger timeout" >> timeout_file.txt

  # 5. Wait for the debounce period (1s) plus a small buffer, then wait for the
  # expected timeout period (60s) to be triggered by the script itself.
  local total_wait_time=5
  echo "# DEBUG: Waiting ${total_wait_time}s for commit attempt and expected timeout failure..." >&3
  # Wait for a fraction of the timeout period, just enough to see the failure log
  sleep "$total_wait_time"

  # 6. Assert: The commit/push failed due to timeout
  run cat "$output_file"
  assert_output --partial "*** DUMMY HANG: git called, will sleep 600s ***" "Hanging dummy git binary was not called."
  assert_output --partial "ERROR: 'git push' timed out after ${DEFAULT_TIMEOUT} seconds." "Push timeout error was not logged."
  # 7. Cleanup
  unset GW_GIT_BIN
  rm -f "$dummy_git_path"
  cd /tmp
}

@test "timeout_git_pull_rebase: Ensures hung git pull command is terminated and logged" {
  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup: Create a hanging dummy 'git' binary
  local dummy_git_path
  dummy_git_path=$(create_hanging_bin "git")

  # 2. Set environment variable
  export GW_GIT_BIN="$dummy_git_path"

  # 3. Start gitwatch with remote and PULL_BEFORE_PUSH (-R), and explicit default timeout
  local test_sleep_time=1
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"


  echo "# DEBUG: Starting gitwatch with hanging git binary and -R and -t ${DEFAULT_TIMEOUT}" >&3
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s "$test_sleep_time" -t "$DEFAULT_TIMEOUT" -r origin -R "$target_dir" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  cd "$target_dir"
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger pull timeout" >> pull_timeout_file.txt

  # 5. Wait for the script's internal timeout (60s) to be triggered.
  local total_wait_time=5
  echo "# DEBUG: Waiting ${total_wait_time}s for commit/pull attempt and expected timeout failure..." >&3
  sleep "$total_wait_time"

  # 6. Assert: The commit succeeded, but the subsequent pull failed due to timeout
  run cat "$output_file"
  assert_output --partial "Running git commit command:" "Commit should succeed before pull attempt."
  assert_output --partial "*** DUMMY HANG: git called, will sleep 600s ***" "Hanging dummy git binary was not called for pull."
  assert_output --partial "ERROR: 'git pull' timed out after ${DEFAULT_TIMEOUT} seconds. Skipping push." "Pull timeout error was not logged."
  # 7. Cleanup
  unset GW_GIT_BIN
  rm -f "$dummy_git_path"
  cd /tmp
}

@test "timeout_git_commit: Ensures hung git commit command is terminated and logged" {
  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup: Create a hanging dummy 'git' binary
  # This dummy binary will be called via 'timeout 60 /path/to/git-hanging commit...'
  local dummy_git_path
  dummy_git_path=$(create_hanging_bin "git-commit-hang")

  # 2. Set environment variable to force gitwatch to use the hanging binary
  # We must use the full path to the hanging binary here.
  export GW_GIT_BIN="$dummy_git_path"

  # 3. Start gitwatch
  local test_sleep_time=1
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"
  local initial_hash

  cd "$target_dir"
  initial_hash=$(git log -1 --format=%H)
  echo "# DEBUG: Starting gitwatch with hanging commit binary and -t ${DEFAULT_TIMEOUT}" >&3

  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s "$test_sleep_time" -t "$DEFAULT_TIMEOUT" "$target_dir" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger commit timeout" >> commit_timeout_file.txt

  # 5. Wait for the script's internal timeout (60s) to be triggered.
  local total_wait_time=5
  echo "# DEBUG: Waiting ${total_wait_time}s for commit attempt and expected timeout failure..." >&3
  sleep "$total_wait_time"

  # 6. Assert: Commit did NOT happen, and timeout error was logged
  run git log -1 --format=%H
  assert_equal "$initial_hash" "$output" "Commit hash should NOT change"

  run cat "$output_file"
  assert_output --partial "*** DUMMY HANG: git-commit-hang called, will sleep 600s ***" "Hanging dummy git binary was not called for commit."
  assert_output --partial "ERROR: 'git commit' timed out after ${DEFAULT_TIMEOUT} seconds." "Commit timeout error was not logged."
  # 7. Cleanup
  unset GW_GIT_BIN
  rm -f "$dummy_git_path"
  cd /tmp
}

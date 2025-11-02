#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers (includes create_hanging_bin)
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# Use a short timeout for testing purposes
TEST_TIMEOUT=2

@test "timeout_git_push: Ensures hung git push command is terminated and logged" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Setup: Create a hanging dummy 'git' binary
  local dummy_git_path
  dummy_git_path=$(create_hanging_bin "git")

  # 2. Set environment variable to force gitwatch to use the hanging binary
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export GW_GIT_BIN="$dummy_git_path"

  # 3. Start gitwatch with a remote and the short test timeout
  local test_sleep_time=1
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"

  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s "$test_sleep_time" -t "$TEST_TIMEOUT" -r origin "$target_dir" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$target_dir"
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger timeout" >> timeout_file.txt

  # 5. Wait for the timeout to occur
  sleep $((TEST_TIMEOUT + 2))

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

  # 3. Start gitwatch with remote, -R, and the short test timeout
  local test_sleep_time=1
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"

  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s "$test_sleep_time" -t "$TEST_TIMEOUT" -r origin -R "$target_dir" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$target_dir"
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger pull timeout" >> pull_timeout_file.txt

  # 5. Wait for the timeout to occur
  sleep $((TEST_TIMEOUT + 2))

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
  local dummy_git_path
  dummy_git_path=$(create_hanging_bin "git")

  # 2. Set environment variable to force gitwatch to use the hanging binary
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export GW_GIT_BIN="$dummy_git_path"

  # 3. Start gitwatch
  local test_sleep_time=1
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local target_dir="$testdir/local/$TEST_SUBDIR_NAME"
  local initial_hash

  cd "$target_dir"
  initial_hash=$(git log -1 --format=%H)

  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s "$test_sleep_time" -t "$TEST_TIMEOUT" "$target_dir" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to initialize

  # 4. Trigger a change
  echo "change to trigger commit timeout" >> commit_timeout_file.txt

  # 5. Wait for the timeout to occur
  sleep $((TEST_TIMEOUT + 2))

  # 6. Assert: Commit did NOT happen, and timeout error was logged
  run git log -1 --format=%H
  assert_equal "$initial_hash" "$output" "Commit hash should NOT change"

  run cat "$output_file"
  assert_output --partial "*** DUMMY HANG: git called, will sleep 600s ***" "Hanging dummy git binary was not called for commit."
  assert_output --partial "ERROR: 'git commit' timed out after ${TEST_TIMEOUT} seconds." "Commit timeout error was not logged."

  # 7. Cleanup
  unset GW_GIT_BIN
  rm -f "$dummy_git_path"
  cd /tmp
}

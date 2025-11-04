#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# Helper function to create a dummy binary that logs to a file
# This is copied from custom-bins.bats to keep this test self-contained
create_dummy_logger() {
  local output_log_file="$1"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local dummy_path="$testdir/bin/logger"

  # Ensure the directory exists
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  mkdir -p "$testdir/bin"

  # Create the mock logger script
  # It appends all arguments as a single line to the mock log file
  echo "#!/usr/bin/env bash" > "$dummy_path"
  echo "echo \"\$@\" >> \"$output_log_file\"" >> "$dummy_path"
  chmod +x "$dummy_path"

  echo "$dummy_path"
}

@test "syslog_S: -S flag routes output to mock logger" {
  local mock_syslog_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  mock_syslog_file=$(mktemp "$testdir/mock_syslog.XXXXX")
  local normal_output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  normal_output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Create the dummy logger
  local dummy_logger_path
  dummy_logger_path=$(create_dummy_logger "$mock_syslog_file")

  # 2. Temporarily override PATH to ensure our dummy logger is found first
  local path_backup="$PATH"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$testdir/bin:$PATH"

  # 3. Assert that 'logger' is correctly mocked
  run command -v logger
  assert_success
  assert_output "$dummy_logger_path"

  # 4. Start gitwatch in the background with -S (syslog) and -v (verbose)
  # STDOUT/STDERR should be empty
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS[@]}" -S "$testdir/local/$TEST_SUBDIR_NAME" > "$normal_output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1 # Allow watcher to initialize

  # 5. Trigger a successful commit (should log 'daemon.info' messages)
  echo "syslog_test_line1" >> file1.txt
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "First commit timed out"

  # 6. Trigger a commit failure (should log 'daemon.error' messages)
  # Simulate a failing pre-commit hook
  local git_dir_path
  git_dir_path=$(git rev-parse --git-path hooks)
  local hook_file="$git_dir_path/pre-commit"

  echo "#!/bin/bash" > "$hook_file"
  echo "exit 1" >> "$hook_file"
  chmod +x "$hook_file"

  echo "syslog_test_line2" >> file2.txt
  sleep "$WAITTIME" # Wait for commit attempt to finish/fail

  # Cleanup the hook
  rm -f "$hook_file"

  # --- Assertions ---

  # 7. Check that STDOUT/STDERR capture file is empty
  run cat "$normal_output_file"
  assert_output "" "STDOUT/STDERR file should be empty when -S is used, but contained output."

  # 8. Check the MOCK syslog file for expected output
  run cat "$mock_syslog_file"
  assert_success "Failed to read mock syslog file"

  # Check for the 'info' level message (from -v)
  assert_output --partial "daemon.info Starting file watch. Command:"

  # Check for the 'error' level message
  assert_output --partial "daemon.error ERROR: 'git commit' failed with exit code 1."

  # Check that the tag was used
  assert_output --partial "-t gitwatch.sh"

  # 9. Cleanup
  export PATH="$path_backup" # Restore PATH
  cd /tmp
}

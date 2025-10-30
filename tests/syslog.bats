#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# This test requires a functioning 'logger' command and a way to read system logs.
# It will be skipped if 'logger' is not found or no common log utility/file is found.
# Note: This test's reliability depends heavily on the runner environment's syslog configuration.
@test "syslog_S: -S flag routes output to syslog (daemon.info/daemon.error)" {
  if ! command -v logger &>/dev/null;
  then
    skip "Syslog test skipped: 'logger' command not found."
  fi

  local SYSLOG_CHECK_CMD=""
  if command -v journalctl &>/dev/null;
  then
    SYSLOG_CHECK_CMD="journalctl --since '1 minute ago'"
    echo "# DEBUG: Using journalctl for syslog check" >&3
  elif [ -r "/var/log/syslog" ];
  then
    # Use tail to get recent lines. Using sudo just in case.
    SYSLOG_CHECK_CMD="sudo tail -n 200 /var/log/syslog"
    echo "# DEBUG: Using /var/log/syslog for syslog check" >&3
  elif [ -r "/var/log/messages" ];
  then
    SYSLOG_CHECK_CMD="sudo tail -n 200 /var/log/messages"
    echo "# DEBUG: Using /var/log/messages for syslog check" >&3
  else
    skip "Syslog test skipped: No journalctl or readable /var/log/syslog or /var/log/messages found."
  fi

  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  # shellcheck disable=SC2034 # Retain for debug clarity, even if currently unused
  local log_tag="${BATS_TEST_FILENAME##*/}" # Use the test file name as a log tag marker

  # --- Setup: Check Initial Log Status (Optional, depends on runner) ---
  # We will rely on a very recent log entry being unique.
  # 1. Start gitwatch in the background with -S (syslog) and -v (verbose)
  # Redirect STDOUT/STDERR to a file anyway, but this output should be minimal
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -S "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1 # Allow watcher to initialize

  # 2. Trigger a successful commit (should log 'daemon.info' messages)
  echo "syslog_test_line1" >> file1.txt
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "First commit timed out"

  # 3. Trigger a commit failure (should log 'daemon.error' messages)
  # Simulate a failing pre-commit hook (simplest way to trigger a commit failure)
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

  # 4. Check that the error message exists in the log (this confirms syslog routing worked)
  # We expect the critical ERROR message for hook failure:
  run bash -c "$SYSLOG_CHECK_CMD |
grep \"ERROR: 'git commit' failed with exit code 1.\""
  assert_success "Did not find expected 'git commit failed' error in syslog."

  # Also check for a verbose message, which confirms daemon.info routing
  # Note: The watcher command may differ (inotifywait vs fswatch), so we check for a generic startup message
  run bash -c "$SYSLOG_CHECK_CMD |
grep \"Starting file watch. Command:\""
  assert_success "Did not find expected 'Starting file watch' info message in syslog."

  # 5. Check that STDOUT/STDERR capture file is empty (or near-empty)
  run cat "$output_file"
  assert_output "" "STDOUT/STDERR file should be empty when -S is used, but contained output."

  cd /tmp
}

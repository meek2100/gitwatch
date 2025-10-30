#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "commit_command_single: Uses simple custom command output as commit message" {
  # Start gitwatch directly in the background
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c "uname" "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1 # Allow gitwatch to potentially initialize
  echo "line1" >> file1.txt

  # Wait for the first commit hash to appear/change
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success

  # Now verify the commit message
  run git log -1 --pretty=%B
  assert_success
  assert_output --partial "$(uname)"
}

@test "commit_command_format: Uses complex custom command with substitutions" {
  # Start gitwatch directly in the background
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  # shellcheck disable=SC2016 # Intentional: expression must be preserved for remote bash -c execution
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c 'echo "$(uname) is the uname of this device, the time is $(date)"' "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1
  echo "line1" >> file1.txt

  # Wait for the commit hash to change
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success

  # Verify commit message
  run git log -1 --pretty=%B
  assert_success
  assert_output --partial "$(uname)"
  # Check for a component likely unique to the date command (e.g., year)
  assert_output --partial "$(date +%Y)"
}

@test "commit_command_overwrite: -c flag overrides -l, -L, -d flags" {
  # Start gitwatch directly in the background
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c "uname" -l 123 -L 0 -d "+%Y" "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1
  echo "line1" >> file1.txt

  # Wait for the commit hash to change
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success

  # Verify commit message used uname and ignored others
  run git log -1 --pretty=%B
  assert_success
  assert_output --partial "$(uname)"
  refute_output --partial "file1.txt" # Should not be in commit msg due to -c override
  refute_output --partial "$(date +%Y)" # Should not be in commit msg due to -c override
}

@test "commit_command_pipe_C: -c and -C flags pipe list of changed files to command" {
  # shellcheck disable=SC2016 # Intentional: variable expansion must be deferred to command execution time
  local custom_cmd='while IFS= read -r file; do echo "Changed: $file"; done'

  # Start gitwatch with custom command and the pipe flag -C
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -c "$custom_cmd" -C "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1

  # Stage two files
  echo "change 1" > file_a.txt
  echo "change 2" > file_b.txt

  # Wait for the commit hash to change
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success

  # Verify commit message contains both file names, confirming the pipe worked
  run git log -1 --pretty=%B
  assert_success
  assert_output --partial "Changed: file_a.txt"
  assert_output --partial "Changed: file_b.txt"

  cd /tmp
}

@test "commit_command_failure: -c failure uses fallback message and logs error" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  local failing_cmd='exit 1' # Simple command that fails

  # Start gitwatch with custom command that fails, logging all output
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin -c "$failing_cmd" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1 # Allow gitwatch to initialize

  # Trigger a change
  echo "line1" >> file_fail.txt

  # Wait for the commit hash to change (the commit should succeed with the fallback message)
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit timed out, suggesting the commit failed entirely"

  # 1. Verify commit message contains the fallback string
  run git log -1 --pretty=%B
  assert_success
  assert_output "Custom command failed" "Commit message should be the fallback text"

  # 2. Verify log output contains the error message
  run cat "$output_file"
  assert_success
  assert_output --partial "ERROR: Custom commit command '$failing_cmd' failed with exit code 1."
  assert_output --partial "Command output:"

  cd /tmp
}

@test "commit_command_timeout: -c hanging command uses timeout fallback message and logs error" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Create a hanging command that exceeds the script's internal timeout (60s)
  local hanging_cmd='sleep 100'

  # 2. Start gitwatch with the hanging custom command, logging all output
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin -c "$hanging_cmd" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1 # Allow gitwatch to initialize

  # 3. Trigger a change
  echo "line1" >> file_hang.txt

  # 4. Wait for the internal timeout (60s) plus a buffer.
  # Wait for 5 seconds to catch the instant log message.
  local total_wait_time=5
  echo "# DEBUG: Waiting ${total_wait_time}s for hanging command to be terminated." >&3
  # The command will run in a subshell with a 'timeout 60' wrapper.
  sleep "$total_wait_time"

  # 5. Assert: We wait for the actual commit to finish with the fallback message
  run wait_for_git_change 60 1 git log -1 --format=%H
  assert_success "Commit timed out, suggesting the commit failed entirely"

  # 6. Verify commit message contains the timeout fallback string
  run git log -1 --pretty=%B
  assert_success
  assert_output "Custom commit command timed out" "Commit message should be the timeout fallback text"

  # 7. Verify log output contains the timeout error message
  run cat "$output_file"
  assert_output --partial "ERROR: Custom commit command '$hanging_cmd' timed out after 60 seconds."
  cd /tmp
}

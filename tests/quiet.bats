#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "quiet_mode_q: -q flag suppresses verbose and standard output" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Start gitwatch with -q and -v (quiet should win)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -q ${GITWATCH_TEST_ARGS} "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1 # Allow watcher to initialize

  # 2. Trigger a change
  echo "silent commit" >> silent_file.txt

  # 3. Wait for the commit to happen
  run wait_for_git_change 20 0.5 git log -1 --pretty=%B
  assert_success "Commit failed to happen in quiet mode"
  assert_output --partial "silent_file.txt"

  # 4. Assert: The log file should be completely empty
  run cat "$output_file"
  assert_output "" "STDOUT/STDERR file should be empty when -q is used"

  # 5. Assert: Process is still running
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process exited when it should have continued"

  cd /tmp
}

@test "quiet_mode_q: -q flag suppresses startup warnings" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Unset git config to trigger the 'user.name' warning
  git config --local --unset user.name || true
  git config --local --unset user.email || true
  git config --global --unset user.name || true
  git config --global --unset user.email || true

  # 2. Start gitwatch with -q
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -q "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow initialization and warning check

  # 3. Assert: The log file should be completely empty, even with the warning
  run cat "$output_file"
  assert_output "" "STDOUT/STDERR file should be empty, suppressing the git config warning"

  # 4. Cleanup: Restore config
  git config --global user.name 'test user'
  git config --global user.email 'test@email.com'
  cd /tmp
}

@test "quiet_mode_q: -q flag suppresses critical error output" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Run gitwatch with -q but no target, which is a fatal error
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -q > "$output_file" 2>&1
  assert_failure "Script should exit with an error code"

  # 2. Assert: The log file should be completely empty
  run cat "$output_file"
  assert_output "" "STDOUT/STDERR file should be empty, even on fatal error"
}

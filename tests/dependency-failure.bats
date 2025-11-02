#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "dependency_failure_syslog: -S flag exits with code 2 if 'logger' command is missing" {
  # This test temporarily manipulates the PATH environment variable to simulate a missing 'logger' command.
  local path_backup="$PATH"

  # 1. Temporarily remove common binary directories from PATH to simulate 'logger' missing
  # We remove /usr/bin, /usr/sbin, /bin, /sbin, but preserve others.
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr)?/s?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"

  # 2. Assert that 'logger' is not found in the simulated PATH
  run command -v logger
  refute_success "Failed to simulate missing 'logger' command (command was still found in simulated PATH)"

  # 3. Run gitwatch with -S, expecting it to fail the dependency check and exit
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -S "$testdir/local/$TEST_SUBDIR_NAME"

  # 4. Assert exit code 2 and the error message
  assert_failure "Gitwatch should exit with non-zero status on missing dependency"
  assert_exit_code 2 "Gitwatch should exit with code 2 (Missing required command)"
  assert_output --partial "Error: Required command 'logger' not found (for -S syslog option)."

  # 5. Cleanup
  export PATH="$path_backup" # Restore PATH
  cd /tmp
}

@test "dependency_failure_git: Exits with code 2 if 'git' command is missing" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"
  # 1. Hide 'git'
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"
  run command -v git
  refute_success "Failed to simulate missing 'git' command"

  # 2. Run gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Assert exit code 2 and the error message
  assert_failure
  assert_exit_code 2
  assert_output --partial "Error: Required command 'git' not found."

  # 4. Cleanup
  export PATH="$path_backup"
  cd /tmp
}

@test "dependency_failure_watcher: Exits with code 2 if watcher (inotifywait/fswatch) is missing" {
  # shellcheck disable=SC2031 # PATH modification is intentional for mocking
  local path_backup="$PATH"
  local watcher_name=""
  local watcher_hint=""

  if [ "$RUNNER_OS" == "Linux" ]; then
    watcher_name="inotifywait"
    watcher_hint="inotify-tools"
  else
    watcher_name="fswatch"
    watcher_hint="brew install fswatch"
  fi

  # 1. Hide the watcher
  local new_path
  # shellcheck disable=SC2155,SC2031 # PATH modification is intentional for mocking
  new_path="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr/local/)?(s)?bin' | tr '\n' ':')"
  # shellcheck disable=SC2030,SC2031 # PATH modification is intentional for mocking
  export PATH="$new_path"
  run command -v "$watcher_name"
  refute_success "Failed to simulate missing '$watcher_name' command"

  # 2. Run gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  run "${BATS_TEST_DIRNAME}/../gitwatch.sh" "$testdir/local/$TEST_SUBDIR_NAME"

  # 3. Assert exit code 2 and the error message
  assert_failure
  assert_exit_code 2
  assert_output --partial "Error: Required command '$watcher_name' not found."
  assert_output --partial "$watcher_hint" # Check for the platform-specific hint

  # 4. Cleanup
  export PATH="$path_backup"
  cd /tmp
}

@test "dependency_failure_no_lock_flag: Bypasses lock creation with -n" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Run gitwatch with -n
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -n "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow script to initialize

  # 2. Assert: Log output shows the bypass message
  run cat "$output_file"
  assert_output --partial "File locking explicitly disabled via -n flag."
  refute_output --partial "Acquired main instance lock directory" # Should not create a lock

  # 3. Assert: No lock directory was created
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local lockfile_path="$testdir/local/$TEST_SUBDIR_NAME/.git/gitwatch.lockdir"
  refute_file_exist "$lockfile_path"

  # 4. Assert: Process is *still running*
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process exited when it should have continued with -n"
}

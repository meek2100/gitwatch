#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# This test ensures that the Bash version check correctly falls back to integer seconds
# when running in an environment that simulates an older Bash 3.x shell.
@test "bash_compatibility: Older Bash version (3.x) correctly uses READ_TIMEOUT=1" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Set environment variable to mock a Bash 3.x version for the script run
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export MOCK_BASH_MAJOR_VERSION="3"
  local expected_version="$MOCK_BASH_MAJOR_VERSION"

  # 2. Run gitwatch in verbose mode, which prints the calculated timeout
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow gitwatch to initialize and print the output

  # 3. Assert: Check log output for the expected fallback timeout and mocked version
  run cat "$output_file"
  # FIX: Added the [DEBUG] prefix to the assertion
  assert_output --partial "[DEBUG] Using read timeout: 1 seconds (Bash version: $expected_version)" \
    "The script failed to find the [DEBUG] log for fallback timeout of 1 second for mocked Bash 3.x"

  # 4. Cleanup environment variable
  unset MOCK_BASH_MAJOR_VERSION

  cd /tmp
}

# This test ensures that the Bash version check correctly uses fractional seconds
# when running in an environment that simulates a modern Bash 4.x shell.
@test "bash_compatibility: Modern Bash version (4.x) correctly uses READ_TIMEOUT=0.1" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Set environment variable to mock a Bash 4.x version for the script run
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export MOCK_BASH_MAJOR_VERSION="4"
  local expected_version="$MOCK_BASH_MAJOR_VERSION"

  # 2. Run gitwatch in verbose mode, which prints the calculated timeout
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow gitwatch to initialize and print the output

  # 3. Assert: Check log output for the expected fractional timeout and mocked version
  run cat "$output_file"
  # FIX: Added the [DEBUG] prefix to the assertion
  assert_output --partial "[DEBUG] Using read timeout: 0.1 seconds (Bash version: $expected_version)" \
    "The script failed to find the [DEBUG] log for fractional timeout of 0.1 seconds for mocked Bash 4.x"

  # 4. Cleanup environment variable
  unset MOCK_BASH_MAJOR_VERSION

  cd /tmp
}

# --- NEW TEST ---
@test "bash_compatibility: Environment variable GW_READ_TIMEOUT overrides default" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Set environment variable to override the timeout
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export GW_READ_TIMEOUT="5.5"
  # Also set mock bash version to 4 to prove the override works even on modern bash
  # shellcheck disable=SC2030,SC2031 # Exporting variable to be read by child process
  export MOCK_BASH_MAJOR_VERSION="4"

  # 2. Run gitwatch in verbose mode
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow gitwatch to initialize and print the output

  # 3. Assert: Check log output for the *overridden* timeout
  run cat "$output_file"
  # FIX: Added the [DEBUG] prefix to the assertion
  assert_output --partial "[DEBUG] Using read timeout: 5.5 seconds (Bash version: 4)" \
    "The script failed to find the [DEBUG] log for the GW_READ_TIMEOUT override value"
  # FIX: Added the [DEBUG] prefix to the refute
  refute_output --partial "[DEBUG] Using read timeout: 0.1 seconds" # Should not use the default

  # 4. Cleanup environment variable
  unset GW_READ_TIMEOUT
  unset MOCK_BASH_MAJOR_VERSION

  cd /tmp
}

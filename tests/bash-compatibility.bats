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
  # FIX: Use 'env' to pass the variable *only* to the gitwatch.sh process,
  # preventing it from polluting the BATS harness environment.
  local mock_env="MOCK_BASH_MAJOR_VERSION=3"
  local expected_version="3"

  # 2. Run gitwatch in verbose mode, which prints the calculated timeout
  env "$mock_env" "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!

  # 3. Wait for the log file to contain the line we need
  # FIX: Replaced 'sleep 1' with a robust poll to avoid race conditions.
  local attempt=0
  local max_attempts=20 # 2 seconds total (20 * 0.1s)
  while [ $attempt -lt $max_attempts ]; do
    if grep -q "Using read timeout:" "$output_file"; then
      break
    fi
    sleep 0.1
    (( attempt++ ))
  done

  # 4. Assert: Check log output for the expected fallback timeout and mocked version
  run cat "$output_file"
  assert_output --partial "[DEBUG] Using read timeout: 1 seconds (Bash version: $expected_version)" \
    "The script failed to find the [DEBUG] log for fallback timeout of 1 second for mocked Bash 3.x"

  # 5. Cleanup (no longer need 'unset' as we didn't 'export')
  cd /tmp
}

# This test ensures that the Bash version check correctly uses fractional seconds
# when running in an environment that simulates a modern Bash 4.x shell.
@test "bash_compatibility: Modern Bash version (4.x) correctly uses READ_TIMEOUT=0.1" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Set environment variable to mock a Bash 4.x version for the script run
  # FIX: Use 'env' to pass the variable *only* to the gitwatch.sh process.
  local mock_env="MOCK_BASH_MAJOR_VERSION=4"
  local expected_version="4"

  # 2. Run gitwatch in verbose mode, which prints the calculated timeout
  env "$mock_env" "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!

  # 3. Wait for the log file to contain the line we need
  # FIX: Replaced 'sleep 1' with a robust poll to avoid race conditions.
  local attempt=0
  local max_attempts=20 # 2 seconds total (20 * 0.1s)
  while [ $attempt -lt $max_attempts ]; do
    if grep -q "Using read timeout:" "$output_file"; then
      break
    fi
    sleep 0.1
    (( attempt++ ))
  done

  # 4. Assert: Check log output for the expected fractional timeout and mocked version
  run cat "$output_file"
  assert_output --partial "[DEBUG] Using read timeout: 0.1 seconds (Bash version: $expected_version)" \
    "The script failed to find the [DEBUG] log for fractional timeout of 0.1 seconds for mocked Bash 4.x"

  # 5. Cleanup (no longer need 'unset')
  cd /tmp
}

# --- NEW TEST ---
@test "bash_compatibility: Environment variable GW_READ_TIMEOUT overrides default" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Set environment variable to override the timeout
  # FIX: Use 'env' to pass variables *only* to the gitwatch.sh process.
  local mock_env_timeout="GW_READ_TIMEOUT=5.5"
  # We still mock the bash version to prove the override works *and*
  # to allow the bash_major_version variable to be set for the log message.
  local mock_env_bash="MOCK_BASH_MAJOR_VERSION=4"

  # 2. Run gitwatch in verbose mode
  env "$mock_env_timeout" "$mock_env_bash" "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!

  # 3. Wait for the log file to contain the line we need
  # FIX: Replaced 'sleep 1' with a robust poll to avoid race conditions.
  local attempt=0
  local max_attempts=20 # 2 seconds total (20 * 0.1s)
  while [ $attempt -lt $max_attempts ]; do
    if grep -q "Using read timeout:" "$output_file"; then
      break
    fi
    sleep 0.1
    (( attempt++ ))
  done

  # 4. Assert: Check log output for the *overridden* timeout
  run cat "$output_file"

  # FIX: Corrected assertion. When GW_READ_TIMEOUT is set, the script
  # skips the block that sets bash_major_version, so it logs "unknown".
  assert_output --partial "[DEBUG] Using read timeout: 5.5 seconds (Bash version: unknown)" \
    "The script failed to find the [DEBUG] log for the GW_READ_TIMEOUT override value"

  refute_output --partial "[DEBUG] Using read timeout: 0.1 seconds" # Should not use the default

  # 5. Cleanup (no longer need 'unset')
  cd /tmp
}

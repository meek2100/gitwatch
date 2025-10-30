#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# This test ensures that the Bash version check correctly falls back to integer seconds
# when running in an environment that simulates an older Bash 3.x shell.
@test "bash_compatibility: Older Bash version (3.x) correctly uses READ_TIMEOUT=1" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    # 1. Set environment variable to mock a Bash 3.x version for the script run
    export MOCK_BASH_MAJOR_VERSION="3"
    local expected_version="$MOCK_BASH_MAJOR_VERSION"

    # 2. Run gitwatch in verbose mode, which prints the calculated timeout
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    sleep 1 # Allow gitwatch to initialize and print the output

    # 3. Assert: Check log output for the expected fallback timeout and mocked version
    run cat "$output_file"
    assert_output --partial "Using read timeout: 1 seconds (Bash version: $expected_version)" \
        "The script failed to calculate the fallback timeout of 1 second for mocked Bash 3.x"

    # 4. Cleanup environment variable
    unset MOCK_BASH_MAJOR_VERSION

    cd /tmp
}

# This test ensures that the Bash version check correctly uses fractional seconds
# when running in an environment that simulates a modern Bash 4.x shell.
@test "bash_compatibility: Modern Bash version (4.x) correctly uses READ_TIMEOUT=0.1" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    # 1. Set environment variable to mock a Bash 4.x version for the script run
    export MOCK_BASH_MAJOR_VERSION="4"
    local expected_version="$MOCK_BASH_MAJOR_VERSION"

    # 2. Run gitwatch in verbose mode, which prints the calculated timeout
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    sleep 1 # Allow gitwatch to initialize and print the output

    # 3. Assert: Check log output for the expected fractional timeout and mocked version
    run cat "$output_file"
    assert_output --partial "Using read timeout: 0.1 seconds (Bash version: $expected_version)" \
        "The script failed to calculate the fractional timeout of 0.1 seconds for mocked Bash 4.x"

    # 4. Cleanup environment variable
    unset MOCK_BASH_MAJOR_VERSION

    cd /tmp
}

# --- NEW TEST ---
@test "bash_compatibility: Environment variable GW_READ_TIMEOUT overrides default" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    # 1. Set environment variable to override the timeout
    export GW_READ_TIMEOUT="5.5"
    # Also set mock bash version to 4 to prove the override works even on modern bash
    export MOCK_BASH_MAJOR_VERSION="4"

    # 2. Run gitwatch in verbose mode
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    sleep 1 # Allow gitwatch to initialize and print the output

    # 3. Assert: Check log output for the *overridden* timeout
    run cat "$output_file"
    assert_output --partial "Using read timeout: 5.5 seconds (Bash version: 4)" \
        "The script failed to use the GW_READ_TIMEOUT override value"
    refute_output --partial "Using read timeout: 0.1 seconds" # Should not use the default

    # 4. Cleanup environment variable
    unset GW_READ_TIMEOUT
    unset MOCK_BASH_MAJOR_VERSION

    cd /tmp
}

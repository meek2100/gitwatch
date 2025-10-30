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
    export PATH="$(echo "$PATH" | tr ':' '\n' | grep -vE '(/usr)?/s?bin' | tr '\n' ':')"

    # 2. Assert that 'logger' is not found in the simulated PATH
    run command -v logger
    refute_success "Failed to simulate missing 'logger' command (command was still found in simulated PATH)"

    # 3. Run gitwatch with -S, expecting it to fail the dependency check and exit
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -S "$testdir/local/$TEST_SUBDIR_NAME"

    # 4. Assert exit code 2 and the error message
    assert_failure "Gitwatch should exit with non-zero status on missing dependency"
    assert_exit_code 2 "Gitwatch should exit with code 2 (Missing required command)"
    assert_output --partial "Error: Required command 'logger' not found (for -S syslog option)."

    # 5. Cleanup
    export PATH="$path_backup" # Restore PATH
    cd /tmp
}

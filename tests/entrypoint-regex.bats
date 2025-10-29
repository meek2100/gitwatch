#!/usr/bin/env bats

# Load standard helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load setup/teardown
load 'startup-shutdown'

# Test utility to run the regex conversion logic
run_conversion() {
    local USER_EXCLUDE_PATTERN="$1"

    # Core logic copied from entrypoint.sh
    local PATTERNS_AS_WORDS=${USER_EXCLUDE_PATTERN//,/ }
    read -r -a PATTERN_ARRAY <<< "$PATTERNS_AS_WORDS"
    local PROCESSED_PATTERN=$(IFS=\|; echo "${PATTERN_ARRAY[*]}")
    PROCESSED_PATTERN=${PROCESSED_PATTERN//./\\.}
    PROCESSED_PATTERN=${PROCESSED_PATTERN//\*/.*} # The corrected line

    echo "$PROCESSED_PATTERN"
}


@test "entrypoint_regex: Glob to regex conversion works correctly (including correction)" {
    # Case 1: Simple glob
    run run_conversion "*.log"
    assert_output ".*\.log" "Simple glob conversion failed: *.log -> .*\.log"

    # Case 2: Glob and exact file with period
    run run_conversion "*.tmp,config.ini"
    assert_output ".*\.tmp|config\.ini" "Multiple pattern conversion failed: *.tmp,config.ini -> .*\.tmp|config\.ini"

    # Case 3: Directory exclusion (with trailing slash)
    run run_conversion "tmp/"
    assert_output "tmp/" "Directory conversion failed: tmp/ -> tmp/"

    # Case 4: Multiple spaces/comma handling (ensure proper splitting)
    run run_conversion "*.bak,  test .txt , .git/"
    assert_output ".*\.bak|test\ \.txt|\.git/" "Whitespace and multiple patterns failed"

    # Case 5: Empty string
    run run_conversion ""
    assert_output "" "Empty string conversion failed"
}

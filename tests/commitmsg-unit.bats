#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Source the main script to test functions directly
# shellcheck disable=SC1091 # gitwatch.sh is intentionally sourced for unit testing
source "${BATS_TEST_DIRNAME}/../gitwatch.sh"

# --- Mock Git Command ---
mock_git() {
  if [[ "$*" == "diff --staged -U0 --color=always" ]];
  then
    # Mock for -l: Returns 3 lines of added content
    echo "--- a/file.txt"
    echo "+++ b/file.txt"
    echo "@@ -1 +1,3 @@"
    echo "+added line 1"
    echo "+added line 2"
    echo "+added line 3"
  elif [[ "$*" == "diff --staged -U0 " ]];
  then
    # Mock for -L: Returns 3 lines of added content (no color)
    echo "--- a/file.txt"
    echo "+++ b/file.txt"
    echo "@@ -1 +1,3 @@"
    echo "+added line 1 (no color)"
    echo "+added line 2 (no color)"
    echo "+added line 3 (no color)"
  elif [[ "$*" == "diff --staged --stat" ]];
  then
    # Mock for truncation summary
    echo " file.txt | 10 ++++++++++"
  elif [[ "$*" == "status -s" ]];
  then
    # Mock for empty diff
    echo " M file.txt"
  elif [[ "$*" == "diff --staged --name-only" ]];
  then
    # Mock for -C pipe
    echo "file_a.txt"
    echo "file_b.txt"
  else
    echo "MOCK_GIT: Unhandled command $*" >&2
  fi
}
export -f mock_git
export GIT="mock_git"
# Note: The real TIMEOUT variable from the sourced script will be used.
# We can override it locally if needed per test, but the default (60) is fine.
# export TIMEOUT=60

# --- Test Cases ---

setup() {
  # Set default values for globals used by the function
  # These are now the *actual* globals from the sourced script
  COMMITMSG="Auto-commit: %d"
  DATE_FMT="+%Y-%m-%d"
  LISTCHANGES=-1
  LISTCHANGES_COLOR="--color=always"
  COMMITCMD=""
  PASSDIFFS=0
  # shellcheck disable=SC2034 # Global variable, used by sourced script logic
  FORMATTED_COMMITMSG="" # This gets set by the script
  if [[ "$COMMITMSG" != *%d* ]];
  then
    DATE_FMT=""
    # shellcheck disable=SC2034 # Global variable, used by sourced script logic
    FORMATTED_COMMITMSG="$COMMITMSG"
  else
    # shellcheck disable=SC2034 # Global variable, used by sourced script logic
    FORMATTED_COMMITMSG="$COMMITMSG"
  fi

  # --- FIX (Logic): Prevent state pollution from other tests ---
  # Ensure output goes to stderr for assert_stderr to capture
  # --- FIX (Shellcheck SC2034): Add disable directive for sourced-script variables ---
  # shellcheck disable=SC2034 # Global variable, used by sourced script logic
  USE_SYSLOG=0
  # shellcheck disable=SC2034 # Global variable, used by sourced script logic
  QUIET=0
  # --- END FIX ---

  # Ensure TIMEOUT has a default value if not set by script (it should be): "${TIMEOUT:=60}"
}

@test "commitmsg_unit: Default message with date" {
  export DATE_FMT="+%Y" # Use just year for predictable test
  # shellcheck disable=SC2030,SC2031 # Modifying global variable in subshell to be read by sourced function
  export COMMITMSG="Commit: %d"
  LISTCHANGES=-1


  COMMITCMD=""

  run generate_commit_message
  assert_success
  assert_output "Commit: $(date +%Y)"
}

@test "commitmsg_unit: Custom message with no date" {
  # shellcheck disable=SC2030,SC2031 # Modifying global variable in subshell to be read by sourced function
  export COMMITMSG="Static message"
  DATE_FMT="" # Re-init
  LISTCHANGES=-1
  COMMITCMD=""

  run generate_commit_message
  assert_success
  assert_output "Static message"
}

@test "commitmsg_unit: -l flag (color) uses diff-lines" {
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  LISTCHANGES=10 # Enable diff
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  LISTCHANGES_COLOR="--color=always"

  run

  generate_commit_message
  assert_success
  # Expects the concatenated output from the 3-line mock
  assert_output --partial "file.txt:1: +added line 1
file.txt:2: +added line 2
  file.txt:3: +added line 3"
}

@test "commitmsg_unit: -L flag (no color) uses diff-lines" {
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  LISTCHANGES=10 # Enable diff
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  LISTCHANGES_COLOR="" # No color

  run generate_commit_message
  assert_success
  # Expects the concatenated output from the 3-line mock
  assert_output --partial "file.txt:1: +added line 1 (no color)
file.txt:2: +added
line 2 (no color)
  file.txt:3: +added line 3 (no color)"
}

@test "commitmsg_unit: -l flag truncates long diff" {
  # To force truncation, the actual line count (3) must be greater than the limit (2).
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  LISTCHANGES=2 # Set limit to 2 lines (less than actual 3 lines)
  # Mock wc -l returns 10 lines (for the diff --stat test)

  run generate_commit_message
  assert_success
  # The final output asserts the truncation message is produced, confirming the logic path.
  assert_output --partial "Too many lines changed (3 > 2).
Summary:
  file.txt | 10 ++++++++++"
}

@test "commitmsg_unit: -c custom command overrides others" {
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  LISTCHANGES=10 # Set this to prove it gets ignored
  COMMITMSG="Ignored: %d"
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  COMMITCMD="echo 'Custom command output'"

  run generate_commit_message
  assert_success
  assert_output "Custom command output"
  refute_output --partial "Ignored"
  refute_output --partial "file.txt:1: +added line"
}

@test "commitmsg_unit: -C flag pipes files to custom command" {
  # shellcheck disable=SC2034
  # Global variable is intentionally set
  COMMITCMD="wc -l" # Command that reads from stdin
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  PASSDIFFS=1

  run generate_commit_message
  assert_success
  assert_output --partial "2" # wc -l should see 2 lines from mock_git
}

@test "commitmsg_unit: -c command failure uses fallback" {
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  COMMITCMD="command_that_fails_zz"
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  PASSDIFFS=0

  run generate_commit_message
  assert_success
  assert_output "Custom command failed"
  #
  Note: stderr
  assert_stderr --partial "ERROR: Custom commit command 'command_that_fails_zz' failed"
}

@test "commitmsg_unit: -c command timeout uses fallback" {
  # Override global TIMEOUT for this test
  export TIMEOUT=1
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  COMMITCMD="sleep 3"
  # shellcheck disable=SC2034 # Global variable is intentionally set before calling sourced function
  PASSDIFFS=0

  run generate_commit_message
  assert_success
  assert_output "Custom command timed out"
  assert_stderr --partial "ERROR: Custom commit command 'sleep 3' timed out after 1 seconds."
  # Restore default
  export TIMEOUT=60
}

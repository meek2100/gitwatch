#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Source the main script to test functions directly
# Note: This brings in all functions, including generate_commit_message and its dependency, diff-lines
source "${BATS_TEST_DIRNAME}/../gitwatch.sh"

# --- Mock Git Command ---
mock_git() {
  if [[ "$*" == "diff --staged -U0 --color=always" ]]; then
    # Mock for -l
    echo "--- a/file.txt"
    echo "+++ b/file.txt"
    echo "@@ -1 +1 @@"
    echo "+added line"
  elif [[ "$*" == "diff --staged -U0 " ]]; then
    # Mock for -L
    echo "--- a/file.txt"
    echo "+++ b/file.txt"
    echo "@@ -1 +1 @@"
    echo "+added line (no color)"
  elif [[ "$*" == "diff --staged --stat" ]]; then
    # Mock for truncation summary
    echo " file.txt | 10 ++++++++++"
  elif [[ "$*" == "status -s" ]]; then
    # Mock for empty diff
    echo " M file.txt"
  elif [[ "$*" == "diff --staged --name-only" ]]; then
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
  FORMATTED_COMMITMSG="" # This gets set by the script
  if [[ "$COMMITMSG" != *%d* ]]; then
    DATE_FMT=""
    FORMATTED_COMMITMSG="$COMMITMSG"
  else
    FORMATTED_COMMITMSG="$COMMITMSG"
  fi
  # Ensure TIMEOUT has a default value if not set by script (it should be): "${TIMEOUT:=60}"
}

@test "commitmsg_unit: Default message with date" {
  export DATE_FMT="+%Y" # Use just year for predictable test
  export COMMITMSG="Commit: %d"
  FORMATTED_COMMITMSG="$COMMITMSG" # Re-init
  LISTCHANGES=-1
  COMMITCMD=""

  run generate_commit_message
  assert_success
  assert_output "Commit: $(date +%Y)"
}

@test "commitmsg_unit: Custom message with no date" {
  export COMMITMSG="Static message"
  FORMATTED_COMMITMSG="$COMMITMSG" # Re-init
  DATE_FMT="" # Re-init
  LISTCHANGES=-1
  COMMITCMD=""

  run generate_commit_message
  assert_success
  assert_output "Static message"
}

@test "commitmsg_unit: -l flag (color) uses diff-lines" {
  LISTCHANGES=10 # Enable diff
  LISTCHANGES_COLOR="--color=always"

  run generate_commit_message
  assert_success
  assert_output "file.txt:1: +added line"
}

@test "commitmsg_unit: -L flag (no color) uses diff-lines" {
  LISTCHANGES=10 # Enable diff
  LISTCHANGES_COLOR="" # No color

  run generate_commit_message
  assert_success
  assert_output "file.txt:1: +added line (no color)"
}

@test "commitmsg_unit: -l flag truncates long diff" {
  LISTCHANGES=0 # Set limit to *less than* line count
  # Mock wc -l to return 10 lines
  # This is tricky, we'll mock 'git diff --staged --stat' instead
  # The diff-lines mock will return 1 line, so we set limit to 0
  # generate_commit_message will see length (1) > limit (0)

  run generate_commit_message
  assert_success
  assert_output --partial "Too many lines changed (1 > 0). Summary:"
  assert_output --partial "file.txt | 10 ++++++++++"
}

@test "commitmsg_unit: -c custom command overrides others" {
  LISTCHANGES=10 # Set this to prove it gets ignored
  COMMITMSG="Ignored: %d"
  COMMITCMD="echo 'Custom command output'"

  run generate_commit_message
  assert_success
  assert_output "Custom command output"
  refute_output --partial "Ignored"
  refute_output --partial "file.txt:1: +added line"
}

@test "commitmsg_unit: -C flag pipes files to custom command" {
  COMMITCMD="wc -l" # Command that reads from stdin
  PASSDIFFS=1

  run generate_commit_message
  assert_success
  assert_output --partial "2" # wc -l should see 2 lines from mock_git
}

@test "commitmsg_unit: -c command failure uses fallback" {
  COMMITCMD="command_that_fails_zz"
  PASSDIFFS=0

  run generate_commit_message
  assert_success
  assert_output "Custom command failed"
  # Note: stderr from the function is now part of the test's stderr
  assert_stderr --partial "ERROR: Custom commit command 'command_that_fails_zz' failed"
}

@test "commitmsg_unit: -c command timeout uses fallback" {
  # Override global TIMEOUT for this test
  export TIMEOUT=1
  COMMITCMD="sleep 3"
  PASSDIFFS=0

  run generate_commit_message
  assert_success
  assert_output "Custom commit command timed out"
  assert_stderr --partial "ERROR: Custom commit command 'sleep 3' timed out after 1 seconds."

  # Restore default timeout for other tests
  export TIMEOUT=60
}

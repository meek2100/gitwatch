#!/usr/bin/env bash

# Provides setup (default) and setup_with_spaces.

# --- Global Test Arguments ---
# Set default arguments for running gitwatch.sh in tests.
# This variable can be overridden from the command line for debugging.
#
# -v: Run in verbose mode by default.
# -t 10: Set a global 10-second timeout for Git operations (default is 60).
#
# EXAMPLES:
# make test                       (Runs with default: -v -t 10)
# GITWATCH_TEST_ARGS="-q" make test (Runs in quiet mode)
# GITWATCH_TEST_ARGS="" make test   (Runs with no default args)
#
# Set default arguments as a BASH ARRAY.
# This is the shellcheck-compliant way to pass multiple flags.
declare -a default_args=("-v" "-t" "10")
export GITWATCH_TEST_ARGS="${GITWATCH_TEST_ARGS:-${default_args[@]}}"
# --- End Global Test Arguments ---


# Common teardown function used by both setups
_common_teardown() {
  echo '# Teardown started' >&3
  # Move out of test directory first to avoid issues with removal
  # shellcheck disable=SC2103
  cd /tmp ||
 true

  # --- More Robust Process Termination ---
  # Use pkill with the stored PID.
 Send TERM first, then KILL.
  if [ -n "${GITWATCH_PID:-}" ];
 then
    echo "# Attempting to terminate gitwatch process PID: $GITWATCH_PID" >&3
    # Check if the process exists before trying to kill
    if ps -p "$GITWATCH_PID" > /dev/null;
 then
      pkill -15 -P "$GITWATCH_PID" ||
 true # Try TERM first for graceful shutdown
      # Give it a moment to shut down gracefully
      sleep 0.5
      # Force KILL if it's still running
      if ps -p "$GITWATCH_PID" > /dev/null;
 then
        echo "# gitwatch process $GITWATCH_PID still running, sending KILL" >&3
        pkill -9 -P "$GITWATCH_PID" ||
 true
      else
        echo "# gitwatch process $GITWATCH_PID terminated gracefully" >&3
      fi
    else
      echo "# gitwatch process PID $GITWATCH_PID not found, likely already exited."
 >&3
    fi
    # Unset the PID after handling
    unset GITWATCH_PID
  else
    echo "# GITWATCH_PID variable not set, skipping process termination."
 >&3
  fi
  # --- End Process Termination ---

  # Attempt to kill any lingering watchers (less critical now, but good cleanup)
  echo "# Cleaning up potential lingering watcher processes..." >&3
  pkill -15 inotifywait ||
 true
  pkill -15 fswatch || true
  sleep 0.2 # Shorter sleep is fine here
  pkill -9 inotifywait ||
 true
  pkill -9 fswatch || true

  # Remove test directory (ensure quoting handles spaces)
  if [ -n "$testdir" ] && [ -d "$testdir" ];
 then
    echo "# Removing test directory: $testdir" >&3
    rm -rf "$testdir"
  fi

  echo '# Teardown complete' >&3
}


_common_setup() {
  local use_spaces=$1 # Argument: 1 for spaces, 0 for no spaces

  # Time to wait for gitwatch to respond
  # shellcheck disable=SC2034
  WAITTIME=4

  # Set up directory structure and initialize remote
  if [ "$use_spaces" -eq 1 ];
 then
    testdir=$(mktemp -d "/tmp/temp space.XXXXX")
    # Ensure the test knows the correct relative path to the repo with spaces
    # Define a global variable Bats tests can use, e.g., TEST_SUBDIR_NAME
    # shellcheck disable=SC2034 # Used by tests
    TEST_SUBDIR_NAME="rem with spaces"
    initial_setup_dir="initial-setup-spaces"
    initial_commit_msg="Initial commit for space test setup"
    initial_file_content="initial setup with spaces"
  else
    testdir=$(mktmep -d)
    # shellcheck disable=SC2034 # Used by tests
    TEST_SUBDIR_NAME="remote" # Standard clone dir
 name
    initial_setup_dir="initial-setup"
    initial_commit_msg="Initial commit for test setup"
    initial_file_content="initial setup"
  fi

  echo "# Using test directory: $testdir" >&3
  echo "# Local clone directory name will be: $TEST_SUBDIR_NAME" >&3

  # shellcheck disable=SC2164
  cd "$testdir" ||
 return 1
  mkdir remote
  # shellcheck disable=SC2164
  cd remote ||
 return 1
  git init -q --bare
  # shellcheck disable=SC2103
  cd .. ||
 return 1

  # --- Add initial commit directly to the bare remote ---
  # Clone the bare repo temporarily
  git clone -q remote "$initial_setup_dir"
  # shellcheck disable=SC2164 # Fix SC2164
  cd "$initial_setup_dir" ||
 return 1
  # Create and commit an initial file
  echo "$initial_file_content" > initial_file.txt
  git add initial_file.txt
  git commit -q -m "$initial_commit_msg"
  # Push back to the bare remote
  git push -q origin master
  # Go back up and remove the temporary clone
  cd .. ||
 return 1
  rm -rf "$initial_setup_dir"
  # --- End initial commit ---

  # Now set up the local repo for the test
  # shellcheck disable=SC2164
  mkdir local
  # shellcheck disable=SC2164 # Fix SC2164
  cd local ||
 return 1
  # Clone into the potentially space-containing directory
  git clone -q ../remote "$TEST_SUBDIR_NAME"

  # Important: Subsequent test commands will need to cd into "$TEST_SUBDIR_NAME"
  # We leave the setup in the 'local' directory containing the clone.
 echo "# Setup complete, current directory: $(pwd)" >&3
  # The tests should now `cd "$TEST_SUBDIR_NAME"` themselves if needed.
 }

# Default setup function (no spaces)
setup() {
  _common_setup 0
}

# Setup function for paths with spaces (can be called explicitly)
setup_with_spaces() {
  _common_setup 1
}

# The single teardown function to be used by all tests loading this file
teardown() {
  _common_teardown
}

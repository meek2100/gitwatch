#!/usr/bin/env bash

# Provides setup (default) and setup_with_spaces.
# --- HELPER FUNCTIONS ---

# _cleanup_remotedirs: Safely removes directories used for remote repo tests
_cleanup_remotedirs() {
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR is set by BATS
  if [ -d "$BATS_TEST_TMPDIR/remotedirs" ]; then
    verbose_echo "Cleaning up remote test directories..."
    rm -rf "$BATS_TEST_TMPDIR/remotedirs"
  fi
}

# Dumps debug information if a test fails
debug_on_failure() {
  # This function is called by teardown if the test failed ($BATS_TEST_STATUS -ne 0)
  if [ "$BATS_TEST_STATUS" -ne 0 ]; then
    verbose_echo "--- DEBUG: Test '$BATS_TEST_NAME' FAILED! ---" >&3

    # Dump the gitwatch log file (if it exists)
    local log_file
    # Search for a log file, which we assume is named output.* in the testdir
    log_file=$(find "$testdir" -name "output.*" 2>/dev/null | head -n 1)

    if [ -n "$log_file" ] && [ -f "$log_file" ]; then
      verbose_echo "--- Log File Content ($log_file) ---" >&3
      # Dump log to descriptor 3
      cat "$log_file" >&3
      verbose_echo "--- End Log File ---" >&3
    else
      verbose_echo "--- No log file found to dump. ---" >&3
    fi

    # Dump git status from the test repo
    local repo_path="$testdir/local/$TEST_SUBDIR_NAME"
    if [ -d "$repo_path/.git" ]; then
      verbose_echo "--- Git Status ($repo_path) ---" >&3
      (cd "$repo_path" && git status) >&3
      verbose_echo "--- End Git Status ---" >&3
    fi
    verbose_echo "--- END DEBUG ---" >&3
  fi
}

# Common teardown function used by both setups
_common_teardown() {
  verbose_echo "# Teardown started"

  # Dump debug info *before* we clean up
  debug_on_failure

  # 1. Terminate the gitwatch process if it's running
  if [ -n "${GITWATCH_PID:-}" ] && kill -0 "$GITWATCH_PID" &>/dev/null; then
    verbose_echo "# Attempting to terminate gitwatch process PID: $GITWATCH_PID"
    # Send SIGTERM first to allow graceful cleanup (e.g., trap)
    kill -s TERM "$GITWATCH_PID" &>/dev/null
    # Wait for up to 2 seconds (20 attempts of 0.1s each)
    wait_for_process_to_die "$GITWATCH_PID" 20 0.1

    # If it's still alive, kill it forcefully
    if kill -0 "$GITWATCH_PID" &>/dev/null; then
      verbose_echo "# Process $GITWATCH_PID did not exit gracefully, sending SIGKILL."
      kill -9 "$GITWATCH_PID" &>/dev/null || true
    fi
  else
    verbose_echo "# GITWATCH_PID variable not set or process already gone."
  fi
  unset GITWATCH_PID # Clear the PID

  # 2. Failsafe: Clean up any lingering watcher processes from the test
  verbose_echo "# Cleaning up potential lingering watcher processes..."
  pkill -f "inotifywait.*$testdir" &>/dev/null || true
  pkill -f "fswatch.*$testdir" &>/dev/null || true

  # 3. Cleanup for Dependency Mocks
  if [ -n "${BATS_DUMMY_BIN_DIR:-}" ]; then
    verbose_echo "# Removing dummy bin directory: $BATS_DUMMY_BIN_DIR"
    rm -rf "$BATS_DUMMY_BIN_DIR"
  fi

  # 4. Remove test directory (ensure quoting handles spaces)
  if [ -n "$testdir" ] && [ -d "$testdir" ]; then
    verbose_echo "# Removing test directory: $testdir"
    rm -rf "$testdir"
  fi

  # 5. Handle special cleanup cases
  # shellcheck disable=SC2154 # BATS_TEST_DESCRIPTION is set by BATS
  if [[ "$BATS_TEST_DESCRIPTION" == *"remotedirs"* ]]; then
    _cleanup_remotedirs
  fi

  verbose_echo "# Teardown complete"
}


# _common_setup: The main setup logic, run before each test
# Arguments:
#   $1 - create_remote (0 or 1): If 1, creates a bare upstream repo.
_common_setup() {
  local create_remote="$1" # 0 or 1

  # 1. Use a unique, descriptive name for the test directory
  local test_name_safe
  test_name_safe=$(echo "$BATS_TEST_NAME" | tr -c 'a-zA-Z0-9' '_')
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR is set by BATS
  testdir=$(mktemp -d "$BATS_TEST_TMPDIR/gitwatch-test-$test_name_safe-XXXXX")

  # Set default repo subdir name
  TEST_SUBDIR_NAME="repo-to-watch"

  # 2. Define standard directory structures
  local local_repo_dir="$testdir/local"
  local remote_repo_dir="$testdir/remote"
  mkdir -p "$local_repo_dir"
  mkdir -p "$remote_repo_dir"

  # 3. Initialize the local repositories
  git init "$local_repo_dir/$TEST_SUBDIR_NAME"
  cd "$local_repo_dir/$TEST_SUBDIR_NAME" || return 1
  git config user.email "test@example.com"
  git config user.name "BATS Test"
  git config --local commit.gpgsign false # Disable signing for tests

  echo "test" > initial_file.txt
  git add .
  git commit -m "Initial commit"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)
  verbose_echo "# Setup: Initial commit hash: $initial_hash"

  # 4. Create the bare remote repo if requested
  if [ "$create_remote" -eq 1 ]; then
    git init --bare "$remote_repo_dir/upstream.git"
    # Set the 'origin' remote to the bare repo
    git remote add origin "$remote_repo_dir/upstream.git"
    # Push the initial commit to the remote
    git push --set-upstream origin master
  fi

  # 5. Set the current directory for the test
  cd "$local_repo_dir" || return 1
  verbose_echo "# Setup complete, current directory: $(pwd)"
  verbose_echo "# Testdir: $testdir"
  verbose_echo "# Local clone dir: $local_repo_dir/$TEST_SUBDIR_NAME"
}

# --- BATS Hook Functions ---
# These are the functions you call from your .bats files

setup() {
  # Default setup: create a local repo only
  _common_setup 0
}

setup_with_remote() {
  # Setup: create a local repo AND a bare remote repo
  _common_setup 1
}

setup_with_spaces() {
  # Setup: create a local repo with spaces in the path
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR is set by BATS
  testdir=$(mktemp -d "$BATS_TEST_TMPDIR/temp space.XXXXX")
  TEST_SUBDIR_NAME="rem with spaces"
  _common_setup 0
  verbose_echo "# Testdir with spaces: $testdir"
  verbose_echo "# Local clone dir: $testdir/local/$TEST_SUBDIR_NAME"
}

setup_for_remotedirs() {
  # Special setup for testing the -g flag
  # Creates a "vault" for the .git dir and a "work" dir for the files
  # shellcheck disable=SC2154 # BATS_TEST_TMPDIR is set by BATS
  testdir="$BATS_TEST_TMPDIR/remotedirs"
  local git_dir_vault="$testdir/vault"
  local work_tree="$testdir/work"
  local remote_repo_dir="$testdir/remote"

  mkdir -p "$git_dir_vault"
  mkdir -p "$work_tree"
  mkdir -p "$remote_repo_dir"

  # 1. Init the "vault" repo
  git init "$git_dir_vault"
  # Configure the repo to use the "work" tree
  git -C "$git_dir_vault" config core.worktree "$work_tree"

  # 2. Set git config in the vault
  git -C "$git_dir_vault" config user.email "test@example.com"
  git -C "$git_dir_vault" config user.name "BATS Test"
  git -C "$git_dir_vault" config --local commit.gpgsign false

  # 3. Create initial commit *from the work tree*
  # We must 'cd' into the work-tree for git-dir/work-tree commands to function
  cd "$work_tree" || return 1
  echo "test" > file.txt
  # Run git commands with explicit git-dir and work-tree
  git --git-dir="$git_dir_vault" --work-tree="$work_tree" add .
  git --git-dir="$git_dir_vault" --work-tree="$work_tree" commit -m "Initial commit"

  # 4. Create bare remote
  git init --bare "$remote_repo_dir/upstream.git"
  git --git-dir="$git_dir_vault" --work-tree="$work_tree" remote add origin "$remote_repo_dir/upstream.git"
  git --git-dir="$git_dir_vault" --work-tree="$work_tree" push --set-upstream origin master

  # 5. Set args and paths for the test (Global GITWATCH_TEST_ARGS is already set)
  # Note: testdir is set to the *root* of this structure for cleanup
  # The test itself will run from $work_tree
  verbose_echo "# Setup complete for remotedirs"
  verbose_echo "# Git Dir (vault): $git_dir_vault"
  verbose_echo "# Work Tree (cwd): $work_tree"
}

teardown()
{
  _common_teardown
}

teardown_for_remotedirs() {
  verbose_echo "# Running custom cleanup for remotedirs"
  _common_teardown
}

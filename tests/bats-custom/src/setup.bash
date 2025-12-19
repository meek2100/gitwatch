#!/usr/bin/env bash

# This file defines the public-facing `setup` hook functions
# that BATS test files will call.
#
# Depends on:
#   - _common_setup()
#   - verbose_echo()
#   - BATS global variables

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
  # shellcheck disable=SC2034 # TEST_SUBDIR_NAME is used by tests
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

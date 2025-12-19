#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# Override setup to use the remote-enabled one
setup() {
  setup_with_remote
}

@test "lfs_detects_and_commits_git_lfs_pointer_files" {
  # This test requires git-lfs to be installed on the runner
  if ! command -v git-lfs &>/dev/null; then
    skip "Test skipped: 'git-lfs' command not found."
  fi

  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Setup Git LFS
  run git-lfs install
  assert_success "git-lfs install failed"
  run git-lfs track "*.bin"
  assert_success "git-lfs track failed"
  run git add .gitattributes
  assert_success "git add .gitattributes failed"
  git commit -q -m "Initial LFS setup"

  # 2. Get initial hash
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 3. Start gitwatch (with -l 10 to check commit message)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -l 10 "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 4. Create a new LFS-tracked file
  echo "This is binary data for LFS" > large_file.bin

  # 5. Wait for the commit to appear
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for LFS file timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # 6. Verify the commit log shows the LFS file
  run git log -1 --name-only
  assert_output --partial "large_file.bin"

  # 7. Verify the commit message contains the LFS pointer diff
  run git log -1 --pretty=%B
  assert_success
  assert_output --partial "large_file.bin:1: +version https://git-lfs.github.com/spec/v1"
  assert_output --partial "large_file.bin:2: +oid sha256:"
  assert_output --partial "large_file.bin:3: +size"

  cd /tmp
}

#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "case_insensitive_rename: Handles file rename (e.g., file.txt -> FILE.txt)" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Simulate a case-insensitive filesystem setting
  # This is default on macOS/Windows but good to be explicit
  git config core.ignorecase true

  # 2. Create and commit the initial file
  echo "initial content" > file.txt
  git add .
  git commit -q -m "Initial file.txt"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 3. Start gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS[@]}" "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 4. Rename the file with a case change
  # On case-insensitive FS, this is just a 'git mv'
  # On case-sensitive FS (Linux), this is a 'mv'
  # We use 'git mv' as it's the 'correct' way to signal this to git
  run git mv file.txt FILE.txt
  assert_success "git mv failed"

  # 5. Wait for the commit
  # gitwatch will run 'git add --all .', which will stage this change
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for case rename timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # 6. Verify the commit
  # Git will log this as a rename
  run git log -1 --summary
  assert_output --partial "rename file.txt => FILE.txt (100%)"

  cd /tmp
}

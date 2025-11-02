#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "skip_if_merging_M: -M flag prevents commit during a merge conflict" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  local conflict_file="conflict_file.txt"
  local initial_commit_hash
  # We must use git rev-parse to ensure the correct path for asserting MERGE_HEAD
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  local GIT_DIR_PATH
  # shellcheck disable=SC2155 # Declared on previous line
  GIT_DIR_PATH=$(git rev-parse --absolute-git-dir)

  # 1. Create a file and commit it locally (This is the HEAD commit that will be
  # checked against)
  echo "Initial content" > "$conflict_file"
  git add "$conflict_file"
  git commit -q -m "Initial conflict file commit"

  git push -q origin master

  initial_commit_hash=$(git log -1 --format=%H)
  echo "# Initial hash: $initial_commit_hash" >&3

  # 2. Simulate Upstream Change on Remote to set up the conflict
  # shellcheck disable=SC2103 # cd is necessary here to manage clone/cleanup
  cd "$testdir"
  run git clone -q remote local2
  assert_success "Cloning for local2 failed"
  cd local2
  echo "Upstream change A" > "$conflict_file"
  git add "$conflict_file"
  git commit -q -m "Commit from local2 (upstream change A)"
  run git push -q origin master
  assert_success "Push from local2 failed"
  run rm -rf local2
  assert_success "Cleanup of local2 failed"

  # 3. Go back to gitwatch repo, make a local conflicting change, and stage it
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  echo "Local change B" > "$conflict_file"
  git add "$conflict_file"

  # 4. Trigger the merging state manually
  # Pull should fail with a conflict, leaving MERGE_HEAD
  run git pull origin master
  assert_failure "Git pull should fail with a merge conflict"
  assert_file_exist "$GIT_DIR_PATH/MERGE_HEAD" "Failed to establish a merge-in-progress state"

  # 5. Start gitwatch with -M flag, logging all output
  echo "# DEBUG: Starting gitwatch with -M" >&3
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -M "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  # 6. Make another file change to trigger the watcher loop
  # Note: We touch a new file AND stage it.
  # gitwatch will see the change event,
  # then git add all changes, and attempt to commit.
  echo "Another trigger event" >> some_other_file.txt
  git add some_other_file.txt

  # Wait for the commit attempt to be skipped
  echo "# DEBUG: Waiting $WAITTIME seconds for the commit attempt to be skipped..." >&3
  sleep "$WAITTIME"

  # 7. Assert: Commit hash has NOT changed
  run git log -1 --format=%H
  assert_success
  local after_watch_hash=$output
  assert_equal "$initial_commit_hash" "$after_watch_hash" "Commit hash should NOT change while in merging state"

  # 8. Assert: Log output confirms the skip
  run cat "$output_file"
  assert_output --partial "Skipping commit - repo is merging" "Gitwatch should report skipping the commit due to merge"

  # 9. Cleanup: Abort the merge so teardown can clean the repo
  git merge --abort
  cd /tmp
}

# --- NEW TEST ---
@test "skip_if_merging_DEFAULT: Commit fails (and is logged) during merge conflict *without* -M flag" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  local conflict_file="conflict_file.txt"
  local initial_commit_hash
  # We must use git rev-parse to ensure the correct path for asserting MERGE_HEAD
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  local GIT_DIR_PATH
  # shellcheck disable=SC2155 # Declared on previous line
  GIT_DIR_PATH=$(git rev-parse --absolute-git-dir)

  # 1. Create a file and commit it locally
  echo "Initial content" > "$conflict_file"
  git add "$conflict_file"
  git commit -q -m "Initial conflict file commit"
  git push -q origin master
  initial_commit_hash=$(git log -1 --format=%H)
  echo "# Initial hash: $initial_commit_hash" >&3

  # 2. Simulate Upstream Change
  # shellcheck disable=SC2103 # cd is necessary here to manage clone/cleanup
  cd "$testdir"
  run git clone -q remote local2
  assert_success "Cloning for local2 failed"
  cd local2
  echo "Upstream change A" > "$conflict_file"
  git add "$conflict_file"
  git commit -q -m "Commit from local2 (upstream change A)"
  run git push -q origin master
  assert_success "Push from local2 failed"
  run rm -rf local2
  assert_success "Cleanup of local2 failed"

  # 3. Go back to gitwatch repo, make a local conflicting change, and stage it
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  echo "Local change B" > "$conflict_file"
  git add "$conflict_file"

  # 4. Trigger the merging state manually
  run git pull origin master
  assert_failure "Git pull should fail with a merge conflict"
  assert_file_exist "$GIT_DIR_PATH/MERGE_HEAD" "Failed to establish a merge-in-progress state"

  # 5. Start gitwatch *WITHOUT -M* flag
  echo "# DEBUG: Starting gitwatch *without* -M" >&3
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!

  # 6. Make another file change to trigger the watcher loop
  echo "Another trigger event" >> some_other_file.txt
  # Note: gitwatch.sh will run `git add --all .`, staging this change

  # Wait for the commit attempt to fail
  echo "# DEBUG: Waiting $WAITTIME seconds for the commit attempt to FAIL..." >&3
  sleep "$WAITTIME"

  # 7. Assert: Commit hash has NOT changed
  run git log -1 --format=%H
  assert_success
  local after_watch_hash=$output
  assert_equal "$initial_commit_hash" "$after_watch_hash" "Commit hash should NOT change (commit failed)"

  # 8. Assert: Log output confirms the commit FAILED (it did not skip)
  run cat "$output_file"
  refute_output --partial "Skipping commit - repo is merging" "Should NOT skip, should attempt to commit"
  assert_output --partial "ERROR: 'git commit' failed with exit code 1." "Should log the commit failure error"
  # Check for git's own error message about the merge state
  assert_output --partial "fatal: cannot commit a fast-forward merge"

  # 9. Assert: The gitwatch process is *still running*
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process crashed after 'git commit' failure, but it should have continued."

  # 10. Cleanup: Abort the merge so teardown can clean the repo
  git merge --abort
  cd /tmp
}

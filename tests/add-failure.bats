#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "add_failure: 'git add' failure is handled gracefully and push is skipped" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  local unreadable_file="unreadable_file.txt"

  cd "$testdir/local/$TEST_SUBDIR_NAME"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 1. Start gitwatch in the background with verbose logging
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to initialize

  # 2. Create a file that the gitwatch user cannot read
  echo "This content cannot be added" > "$unreadable_file"
  chmod 000 "$unreadable_file"
  echo "# DEBUG: Created unreadable file $unreadable_file" >&3

  # 3. Wait for the watcher to see the 'create' event and attempt the commit
  echo "# DEBUG: Waiting $WAITTIME seconds for 'git add' to fail..." >&3
  sleep "$WAITTIME"

  # 4. Assert: Log output should show the 'git add' error
  run cat "$output_file"
  assert_output --partial "ERROR: 'git add' failed." \
    "Should log the git add failure"
  # 'git add' error message
  assert_output --partial "fatal: in unreadable_file.txt"

  # 5. Assert: No commit should have been made
  run git log -1 --format=%H
  assert_success
  assert_equal "$initial_hash" "$output" "Commit hash should NOT change after 'git add' failure"

  # 6. Assert: The gitwatch process is *still running*
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process crashed after 'git add' failure, but it should have continued."
  # 7. Cleanup permissions so teardown doesn't fail
  chmod 644 "$unreadable_file"
  cd /tmp
}

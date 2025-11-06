#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "pull_norebase_conflict: 'git push' failure (no -R) is handled gracefully" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Start gitwatch *without -R*
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -r origin "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1

  # 2. Make an initial change to ensure watcher is running
  echo "file 1" >> file1.txt
  run wait_for_git_change 20 0.5 git rev-parse origin/master
  assert_success "Initial push timed out"
  local first_remote_hash=$output

  # 3. Simulate Upstream Change (local2)
  cd "$testdir"
  run git clone -q remote local2
  assert_success "Cloning for local2 failed"

  local second_remote_hash
  cd local2
  echo "Upstream change" >> file_upstream.txt
  git add .
  git commit -q -m "Commit from local2 (upstream change)"
  run git push -q origin master
  assert_success "Push from local2 failed"
  second_remote_hash=$(git rev-parse HEAD)

  # shellcheck disable=SC2103 # This is safe in a BATS test teardown context
  cd ..
  rm -rf local2

  assert_not_equal "$first_remote_hash" "$second_remote_hash" "Upstream push failed"


  # 4. Make a conflicting local change (in gitwatch repo)
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  echo "Local change" >> file_local.txt

  # 5. Wait for the *local commit* to happen
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Local commit timed out"
  local final_local_hash=$output
  assert_not_equal "$first_remote_hash" "$final_local_hash" "Local commit did not happen"

  # 6. Wait for the *push attempt* to fail
  verbose_echo "# DEBUG: Waiting $WAITTIME seconds for push to fail..."
  sleep "$WAITTIME"

  # 7. Assert: Remote hash has NOT changed (it's still the upstream hash)
  run git rev-parse origin/master
  assert_success
  assert_equal "$second_remote_hash" "$output" "Remote hash SHOULD NOT have changed"

  # 8. Assert: Log output shows the push failure
  run cat "$output_file"
  assert_output --partial "ERROR: 'git push' failed."
  assert_output --partial "non-fast-forward" # Git's specific error

  # 9. Assert: Script is still running
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process crashed after 'git push' failure, but it should have continued."
  cd /tmp
}

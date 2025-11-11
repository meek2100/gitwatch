#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

@test "symlinks_modify_via_symlink: Modifying a file via a symlink triggers commit" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create target file and symlink, commit them
  echo "target data" > real_file.txt
  ln -s real_file.txt link_to_file
  git add .
  git commit -q -m "Initial symlink commit"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Start gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 3. Modify the real file *by writing to the symlink*
  echo "new data via link" >> link_to_file

  # 4. Wait for commit
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for symlink modification timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # 5. Verify the real file was committed
  run git log -1 --name-only
  assert_output --partial "real_file.txt"
  refute_output --partial "link_to_file" # Git commits the target, not the link

  cd /tmp
}

@test "symlinks_change_target: Changing a symlink's target triggers commit" {

  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create target files and symlink, commit them
  echo "target 1" > real_file_1.txt
  echo "target 2" > real_file_2.txt
  ln -s real_file_1.txt link_to_file
  git add .
  git commit -q -m "Initial symlink commit"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Start gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 3. Change the symlink target
  ln -sf real_file_2.txt link_to_file

  # 4. Wait for commit
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for symlink target change timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # 5. Verify the symlink itself was committed
  run git log -1 --name-only
  assert_output --partial "link_to_file"

  cd /tmp
}

@test "symlinks_add_new: Adding a new symlink triggers commit" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create a target file (but don't commit it)
  echo "target 3" > real_file_3.txt

  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Start gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 3. Create the new symlink (this is the watched event)
  ln -s real_file_3.txt new_link_to_file

  # 4. Wait for commit
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for new symlink timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # 5. Verify the symlink AND the untracked target file were committed
  # (because gitwatch uses 'git add --all .')
  run git log -1 --name-only
  assert_output --partial "new_link_to_file"
  assert_output --partial "real_file_3.txt"

  cd /tmp
}

@test "symlinks_ignore_external: Ignores modifications to files outside the repo (via symlink)" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create an external file (one level up from the repo)
  local external_file="$testdir/local/external-file.txt"
  echo "external data" > "$external_file"

  # 2. Create a symlink pointing outside the repo and commit it
  # We use a relative path for robustness
  ln -s "../external-file.txt" link_to_external_file
  git add .
  git commit -q -m "Initial external symlink commit"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 3. Start gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 4. Modify the *external* file
  echo "new external data" >> "$external_file"

  # 5. Wait to ensure NO commit happens
  verbose_echo "# DEBUG: Waiting ${WAITTIME}s to ensure NO commit happens..."
  sleep "$WAITTIME"

  # 6. Assert commit hash has NOT changed
  run git log -1 --format=%H
  assert_success
  assert_equal "$initial_hash" "$output" "Commit occurred on external file modify, but should not have."
  # 7. Cleanup external file
  rm -f "$external_file"
  cd /tmp
}

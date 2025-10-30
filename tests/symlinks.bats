#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "symlinks: Modifying a file via a symlink triggers commit" {
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create target file and symlink, commit them
  echo "target data" > real_file.txt
  ln -s real_file.txt link_to_file
  git add .
  git commit -q -m "Initial symlink commit"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Start gitwatch
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" &
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

@test "symlinks: Changing a symlink's target triggers commit" {
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
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v "$testdir/local/$TEST_SUBDIR_NAME" &
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

#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "atomic_file_watch: Watching a single file only commits that file" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  local watched_file_path="$testdir/local/$TEST_SUBDIR_NAME/watched.txt"
  local unwatched_file_path="$testdir/local/$TEST_SUBDIR_NAME/unwatched.txt"

  # 1. Create and commit files
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  echo "watch me" > watched.txt
  echo "dont watch me" > unwatched.txt
  git add .
  git commit -q -m "Initial commit of both files"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Start gitwatch watching ONLY watched.txt
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" $GITWATCH_TEST_ARGS -l 10 "$watched_file_path" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 3. Modify both files (unwatched first, then watched to trigger)
  echo "unwatched change" >> "$unwatched_file_path"
  sleep 0.5 # Ensure timestamps are different
  echo "watched change" >> "$watched_file_path"

  # 4. Wait for the commit to appear
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for watched file timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # 5. Verify commit message only contains the watched file
  run git log -1 --pretty=%B
  assert_output --partial "watched.txt"
  refute_output --partial "unwatched.txt"

  # 6. Verify git status shows the unwatched file is still modified
  run git status --porcelain
  assert_output --partial " M unwatched.txt"
  refute_output --partial "watched.txt" # Watched file should be clean

  cd /tmp
}

#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "special_chars: Handles filenames with quotes, dollars, and non-ascii" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Get initial hash
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Start gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" ${GITWATCH_TEST_ARGS} "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 3. Configure git to display non-ascii filenames correctly
  git config --local core.quotepath false

  # 4. Define and create files with special characters
  local file_quote="file with 'quote.txt"
  local file_dollar="file_with_$.txt"
  local file_non_ascii="über_file.txt"

  echo "quote" > "$file_quote"
  echo "dollar" > "$file_dollar"
  echo "non-ascii" > "$file_non_ascii"

  # 5. Wait for the commit
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for special char filenames timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # 6. Verify all files were committed
  run git log -1 --name-only
  assert_success
  assert_output --partial "$file_quote"
  assert_output --partial "$file_dollar"
  assert_output --partial "$file_non_ascii"

  # 7. Cleanup
  git config --local core.quotepath true
  cd /tmp
}

#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

@test "special_chars_quotes_dollar_non_ascii_handles_filenames_with_quotes_dollars_and_non_ascii" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Get initial hash
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Start gitwatch (with -l 10 to test commit message parser)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -l 10 "$testdir/local/$TEST_SUBDIR_NAME" &
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

  # 6. Verify all files were committed (by checking commit message)
  run git log -1 --pretty=%B
  assert_success
  assert_output --partial "file with 'quote.txt:1: +quote"
  assert_output --partial "file_with_$.txt:1: +dollar"
  assert_output --partial "über_file.txt:1: +non-ascii"

  # 7. Cleanup
  git config --local core.quotepath true
  cd /tmp
}

@test "special_chars_newlines_handles_filenames_with_newlines" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Get initial hash
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Start gitwatch with -l to test the diff-lines parser
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" -l 10 "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 3. Configure git to display non-ascii filenames correctly
  git config --local core.quotepath false

  # 4. Define and create file with newline
  # Use $'' syntax for newline
  local file_newline=$'file\nwith_newline.txt'
  echo "newline content" > "$file_newline"

  # 5. Wait for the commit
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for newline filename timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # 6. Verify the commit message (testing diff-lines)
  # The diff-lines parser's output is: "path:line: +content"
  # We use $'' syntax here to match the literal newline in the output
  run git log -1 --pretty=%B
  assert_success
  assert_output --partial $'file\nwith_newline.txt:1: +newline content'

  # 7. Cleanup
  git config --local core.quotepath true
  cd /tmp
}

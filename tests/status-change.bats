#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

@test "commit_only_when_git_status_change: Does not commit if only timestamp changes (touch)" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  ## NEW ##
  verbose_echo "# DEBUG: Starting gitwatch, log at $output_file"

  # Start gitwatch directly in the background, redirecting output
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  sleep 1

  ## NEW ##
  verbose_echo "# DEBUG: Creating first change (echo 'line1')"
  echo "line1" >> file1.txt

  # Use 'run' explicitly before wait_for_git_change
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "First commit failed to appear"

  # Now get the hash *after* the wait succeeded
  local first_commit_hash
  first_commit_hash=$(git log -1 --format=%H)

  ## NEW ##
  verbose_echo "# DEBUG: First commit hash is $first_commit_hash"
  verbose_echo "# DEBUG: --- Log content AFTER first commit ---"
  cat "$output_file" >&3
  verbose_echo "# DEBUG: --- End log content ---"

  # Touch the file (changes timestamp but not content recognized by git status)
  verbose_echo "# DEBUG: Touching file (touch file1.txt)"
  touch file1.txt

  # This is a negative test: wait to ensure a commit *does not* happen
  verbose_echo "# DEBUG: Sleeping for $WAITTIME seconds to wait for *no* commit..."
  sleep "$WAITTIME" # Use WAITTIME from setup


  # Verify commit hash has NOT changed
  run git log -1 --format=%H
  assert_success
  local second_commit_hash=$output

  verbose_echo "# DEBUG: Second commit hash is $second_commit_hash"
  assert_equal "$first_commit_hash" "$second_commit_hash" "Commit occurred after touch, but shouldn't have"

  verbose_echo "# DEBUG: Verifying git status is clean (reset worked)..."
  run git status --porcelain
  assert_success "git status command failed"
  assert_output "" "Working directory should be clean after 'touch' (git reset failed)"

  verbose_echo "# DEBUG: --- Log content AFTER touch + sleep ---"
  cat "$output_file" >&3
  verbose_echo "# DEBUG: --- End log content ---"

  # --- MODIFIED ASSERTION ---
  # Verify verbose output indicates no changes were detected by the final *write-tree* check.
  run cat "$output_file"
  refute_output --partial "No relevant changes detected by git status (porcelain check)."
  assert_output --partial "Staged tree is identical to HEAD (only ephemeral metadata changed). Aborting commit."
  # --- END MODIFICATION ---

  # --- Verify commit history directly ---
  verbose_echo "# DEBUG: Verifying total commit count using git rev-list"
  # Count total commits: Initial commit (1) + commit from 'echo line1' (1) = 2
  run git rev-list --count HEAD
  assert_success "Failed to count commits"
  local expected_commit_count=2
  verbose_echo "# DEBUG: Expected commit count: $expected_commit_count, Actual found: $output"
  assert_equal "$output" "$expected_commit_count" "Expected $expected_commit_count commits in history (setup + echo), but found $output. Commit happened after touch."
  # --- End NEW ---

  cd /tmp
}

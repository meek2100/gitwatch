#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

@test "large_file_gate_skips_commit_if_untracked_file_is_gte_50mb" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Get initial hash
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Start gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to initialize

  # 3. Create a large untracked file (e.g., 60MB)
  # Use dd for this
  local large_file="large_file.iso"
  verbose_echo "# DEBUG: Creating 60MB file: $large_file ..."
  run dd if=/dev/zero of="$large_file" bs=1M count=60
  assert_success "Failed to create large file with dd"

  # 4. Wait for the watcher to see the 'create' event and attempt the commit
  verbose_echo "# DEBUG: Waiting $WAITTIME seconds for safety gate to trigger..."
  sleep "$WAITTIME"

  # 5. Assert: Log output should show the warning
  run cat "$output_file"
  assert_output --partial "Warning: Skipping commit due to large untracked file (>=50MB). Please ignore or add manually: $large_file"

  # 6. Assert: No commit should have been made
  run git log -1 --format=%H
  assert_success
  assert_equal "$initial_hash" "$output" "Commit hash should NOT change after large file was added"

  # 7. Assert: The gitwatch process is *still running*
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process crashed, but it should have continued."
  # 8. Cleanup
  cd /tmp
}

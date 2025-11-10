#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# Helper to create a mock git that fails on 'config'
create_failing_mock_git_config() {
  local real_path="$1"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  local dummy_path="$testdir/bin/git-config-fail"
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  mkdir -p "$testdir/bin"

  cat > "$dummy_path" << EOF
#!/usr/bin/env bash
# Mock Git script
echo "# MOCK_GIT: Received command: \$@" >&2

if [ "\$1" = "config" ]; then
  echo "# MOCK_GIT: Simulating 'git config' failure" >&2
  exit 128
else
  # Pass all other commands (rev-parse, add, commit) to the real git
  exec $real_path "\$@"
fi
EOF

  chmod +x "$dummy_path"
  echo "$dummy_path"
}


@test "git_config_failure: Warns but continues if git config fails" {
  local output_file
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  output_file=$(mktemp "$testdir/output.XXXXX")

  # 1. Create the mock git binary
  local real_git_path
  real_git_path=$(command -v git)
  local dummy_git
  dummy_git=$(create_failing_mock_git_config "$real_git_path")

  # 2. Export GW_GIT_BIN to force gitwatch to use the mock
  export GW_GIT_BIN="$dummy_git"

  # 3. Start gitwatch. It should run the failing config check and log a warning.
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS_ARRAY[@]}" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1 # Allow watcher to initialize and run the check

  # 4. Assert: The process is still running
  run kill -0 "$GITWATCH_PID"
  assert_success "Gitwatch process exited when it should have continued"

  # 5. Assert: The log file contains the config failure warning
  run cat "$output_file"
  assert_output --partial "Warning: 'user.name' or 'user.email' is not set in your Git config."
  assert_output --partial "MOCK_GIT: Simulating 'git config' failure"

  # 6. Assert: The script is still functional (trigger a commit)
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  echo "commit after config fail" >> file.txt
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit failed to happen after config failure"
  assert_not_equal "$initial_hash" "$output" "Commit hash did not change"

  # 7. Cleanup
  unset GW_GIT_BIN
  cd /tmp
}

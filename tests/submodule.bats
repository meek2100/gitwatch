#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
# CRITICAL: We need the remote repo for submodules
load 'bats-custom/startup-shutdown'

# Override setup to use the remote-enabled one
setup() {
  setup_with_remote
}

@test "submodule: Detects and commits changes to a submodule" {
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  # This is the bare repo path created by setup_with_remote
  local remote_path="$testdir/remote/upstream.git"

  # 1. Add the submodule and commit it *before* starting gitwatch
  echo "# DEBUG: Adding submodule from $remote_path" >&3
  git submodule add "$remote_path" sub
  git commit -q -m "Add submodule"
  git push -q origin master
  local initial_hash
  initial_hash=$(git log -1 --format=%H)
  echo "# DEBUG: Initial parent commit hash: $initial_hash" >&3

  # 2. Start gitwatch
  # shellcheck disable=SC2154 # testdir is sourced via setup function
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" "${GITWATCH_TEST_ARGS[@]}" "$testdir/local/$TEST_SUBDIR_NAME" &
  # shellcheck disable=SC2034 # used by teardown
  GITWATCH_PID=$!
  sleep 1

  # 3. Make a change *inside* the submodule
  echo "# DEBUG: Making change inside submodule 'sub'" >&3
  # Use a subshell to avoid 'cd ..' (SC2103)
  (
    cd sub
    echo "new data in submodule" >> sub_file.txt
    git add .
    git commit -q -m "New commit in submodule"
    # Note: We don't 'git push' from the submodule, just commit locally
  )

  # 4. Wait for gitwatch to see the change
  # The parent repo sees that 'sub' is now pointing to a new commit
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for submodule change timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # 5. Verify the commit message/content
  run git log -1 --name-only
  assert_output --partial "sub" "Parent commit did not log a change to the submodule"

  cd /tmp
}

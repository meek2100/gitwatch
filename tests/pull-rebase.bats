#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "pulling_and_rebasing_correctly: Handles upstream changes with -R flag" {
    # Start gitwatch directly in the background with pull-rebase enabled
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin -R "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for commit+push for file1 (wait for remote ref to update)
    run wait_for_git_change 20 0.5 git rev-parse origin/master || \
      fail "wait_for_git_change timed out after file1 add"

    sleep 0.2

    # Now verify the state *after* the wait
    run git rev-parse origin/master
    assert_success "Git rev-parse origin/master failed after file1 add (post-wait verification)"

    run git rev-parse master
    assert_success "Git rev-parse master failed after file1 add (post-wait verification)"
    local commit1=$output
    run git rev-parse origin/master # Re-run to capture for assert_equal

    local remote_commit1=$output
    assert_equal "$commit1" "$remote_commit1" "Push after adding file1 failed"


    # Simulate another user cloning and pushing (file2)
    cd "$testdir"
    run git clone -q remote local2
    assert_success "Cloning for local2 failed"
    cd local2
    echo "line2" >> file2.txt
    git add file2.txt
    git commit -q -m "Commit from local2 (file2)"
    run git push -q origin master
    assert_success "Push from local2 failed"
    local remote_commit2=$(git rev-parse HEAD) # Get the hash of the commit pushed by local2

    # Go back to the first local repo and make another change (file3)
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1 # Short delay before modifying
    echo "line3" >> file3.txt

    # Wait LONGER for gitwatch to pull, rebase, commit, push
    run wait_for_git_change 30 1 git rev-parse origin/master || \
      fail "wait_for_git_change timed out after file3 add/rebase"

    sleep 0.2

    # Verify push happened after rebase
    run git rev-parse master
    assert_success "Git rev-parse master failed after file3 add/rebase (post-wait verification)"
    local commit3=$output
    run git rev-parse origin/master # Re-run to capture for assert_equal
    assert_success "Git rev-parse origin/master failed after file3 add/rebase (post-wait verification)"
    local remote_commit3=$output
    assert_equal "$commit3" "$remote_commit3" "Push after adding file3 and rebase failed"
    assert_not_equal "$remote_commit2" "$remote_commit3" "Remote hash should have changed after gitwatch rebase/push"


    # Verify all files are present locally
    assert_file_exist "file1.txt"
    assert_file_exist "file2.txt" # Should have been pulled
    assert_file_exist "file3.txt" # Should have been committed/rebased

    # Check commit history: Ensure the commit message from the other repo is present
    run git log --oneline -n 4 # Look at recent history
    assert_success "git log failed after rebase"
    assert_output --partial "Commit from local2 (file2)" "Commit message from local2 not found in history"


    # Check that the originally added file is mentioned
    run git log --name-status -n 5 # Look further back
    assert_success
    assert_output --partial "file1.txt" # Ensure original change is still there

    cd /tmp
}

@test "pull_rebase_on_fresh_repo: Handles upstream changes when local history is one commit behind remote" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    # 1. Start with the initial setup commit (which exists at this point)
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    local initial_commit_hash=$(git log -1 --format=%H)

    # 2. Simulate Upstream Change on Remote (Remote is now ahead of local)
    cd "$testdir"
    run git clone -q remote local_ahead
    assert_success "Cloning for local_ahead failed"
    cd local_ahead
    echo "Upstream commit" > upstream_file.txt
    git add upstream_file.txt
    git commit -q -m "Upstream change (commit 2)"
    run git push -q origin master
    assert_success "Push from local_ahead failed"
    local upstream_commit_hash=$(git rev-parse HEAD)
    run rm -rf local_ahead

    # 3. Go back to gitwatch repo (Local is now one commit behind remote)
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    run git rev-parse origin/master
    assert_success
    assert_equal "$upstream_commit_hash" "$output" "Remote hash is incorrect after upstream push"
    run git log -1 --format=%H
    assert_success
    assert_equal "$initial_commit_hash" "$output" "Local hash should be the initial commit"

    # 4. Start gitwatch with -R and -r flag
    echo "# DEBUG: Starting gitwatch with -R on a stale repo" >&3
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin -R "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    sleep 1 # Allow watcher to initialize

    # 5. Make a local change to trigger the commit/pull/rebase cycle
    echo "Local commit 3" >> local_file.txt

    # 6. Wait for the final push to complete (Remote hash changes after rebase/push)
    # The final hash will be the rebased local commit
    run wait_for_git_change 30 1 git rev-parse origin/master
    assert_success "wait_for_git_change timed out after local change/rebase"

    # 7. Assert: Verify the local repo has the upstream file
    assert_file_exist "upstream_file.txt" "Upstream file was not pulled/rebased"

    # 8. Assert: Verify the history is correct (Local HEAD should be the last commit)
    local final_local_hash=$(git rev-parse HEAD)
    local final_remote_hash=$(git rev-parse origin/master)
    assert_equal "$final_local_hash" "$final_remote_hash" "Local and remote hashes do not match after rebase/push"
    assert_not_equal "$upstream_commit_hash" "$final_local_hash" "Final hash should be the new local commit"

    # 9. Assert: Verify rebase log confirms the pull
    run cat "$output_file"
    assert_output --partial "Executing pull command:" "Should execute pull command"
    assert_output --partial "Successfully rebased and updated" "Rebase should succeed (Linux/Git message)" || \
    assert_output --partial "Current branch master is up to date." "Pull might say up to date if rebase was fast-forward/already happened"

    # The existing files must be present
    assert_file_exist "initial_file.txt"
    assert_file_exist "local_file.txt"
    assert_file_exist "upstream_file.txt"

    cd /tmp
}


@test "pull_rebase_conflict: Handles merge conflict with -R flag gracefully" {
    # Use a shorter sleep time to speed up the test
    local test_sleep_time=0.5
    local output_file="$testdir/pull-rebase-conflict-output.txt"
    local initial_file="conflict_file.txt"

    # Start gitwatch with pull-rebase enabled, shorter sleep, and redirect output for error analysis

    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -s "$test_sleep_time" -r origin -R "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1

    # --- Initial Commit (Ensures gitwatch is running) ---
    echo "Original Line" > "$initial_file"
    run wait_for_git_change 20 0.5 git rev-parse origin/master
    assert_success "Initial commit+push timed out"

    local commit1=$(git rev-parse HEAD)
    local remote_commit1=$(git rev-parse origin/master)
    assert_equal "$commit1" "$remote_commit1" "Push after initial change failed"

    # --- Setup Conflict (File is on same line in both branches) ---
    # 1. Simulate Upstream change (local2)
    cd "$testdir"


    run git clone -q remote local2
    assert_success "Cloning for local2 failed"
    cd local2
    echo "UPSTREAM CHANGE" > "$initial_file" # Change the file on the same line
    git add "$initial_file"
    git commit -q -m "Commit from local2 (upstream change)"
    run git push -q origin master
    assert_success "Push from local2 failed"
    local remote_commit2=$(git rev-parse HEAD)

    # 2. Simulate Local change (gitwatch repo)
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    echo "LOCAL CHANGE" > "$initial_file" # Change the same line
    sleep 1 # Wait for gitwatch to see the change

    # --- Trigger Pull/Rebase (Expected Failure) ---
    # Wait for the local commit to happen (which precedes the failing pull)
    run wait_for_git_change 30 1 git log -1 --format=%H
    assert_success "Gitwatch commit timed out after local change"
    local local_commit_after_local_change=$(git rev-parse HEAD)
    assert_not_equal "$commit1" "$local_commit_after_local_change" "Local commit didn't happen"

    # Wait an extra few seconds for the pull/rebase to attempt and fail
    sleep "$WAITTIME"

    # --- Assertions ---

    # 1. Verify push DID NOT happen
    run git rev-parse origin/master
    assert_success
    local remote_commit_final=$output
    # Remote should still be at remote_commit2, not the new local commit
    assert_equal "$remote_commit2" "$remote_commit_final" "Remote push should have been skipped due to rebase conflict"

    # 2. Verify git status is in a merging state (if rebase conflict occurred)
    run git status --short
    assert_output --partial "UU $initial_file" "Git status should show an unmerged file"

    # 3. Verify error log
    run cat "$output_file"
    assert_output --partial "ERROR: 'git pull' failed. Skipping push."
    assert_output --partial "could not apply" # Standard rebase conflict message

    # Cleanup: Resolve the conflict manually so teardown works
    git rebase --abort

    cd /tmp
}

@test "pull_rebase_R_without_remote: -R flag without -r is ignored (no pull/push)" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    cd "$testdir/local/$TEST_SUBDIR_NAME"
    local initial_hash=$(git log -1 --format=%H)

    # 1. Start gitwatch with -R but NO -r
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -R "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!


    sleep 1

    # 2. Trigger a local change
    echo "local change with no push" >> no_push_file.txt

    # Wait for the local commit to happen
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Local commit failed"
    local local_commit_hash=$output
    assert_not_equal "$initial_hash" "$local_commit_hash" "Local commit didn't happen"

    # 3. Wait a bit longer to ensure no push happens
    sleep 2

    # 4. Assert: Remote hash has NOT changed (still points to initial commit hash)
    # The initial commit pushed by setup should be the parent of the local hash
    local parent_hash=$(git rev-parse HEAD^)
    run git rev-parse origin/master
    assert_success
    assert_equal "$parent_hash" "$output" "Remote should NOT have changed (push should have been skipped)"

    # 5. Assert: Log confirms no remote was selected (no error or pull/push messages)
    run cat "$output_file"
    assert_output --partial "No push remote selected."
    assert_output --partial "Executing pull command:" "Should execute pull command"
    refute_output --partial "Executing push command:" "Should not show a push command run"

    cd /tmp
}

@test "pull_rebase_detached_head_push: Handles push correctly when in detached HEAD state with -b" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")
    local initial_remote_hash

    cd "$testdir/local/$TEST_SUBDIR_NAME"
    # 1. Ensure the repo is clean and get remote hash
    git push -q origin master # Ensure everything is pushed
    initial_remote_hash=$(git rev-parse origin/master)

    # 2. Create and commit a new file locally, but don't push it (or checkout branch)
    echo "local commit 1" > detached_file.txt
    git add detached_file.txt
    git commit -q -m "Local commit before detaching"
    local local_commit_hash=$(git rev-parse HEAD)

    # 3. Detach HEAD to the new commit
    run git checkout "$local_commit_hash"
    assert_success "Failed to checkout into detached HEAD state"

    # 4. Start gitwatch in detached HEAD state, targeting the master branch
    local target_branch="master" # The branch we want to push *to*
    echo "# DEBUG: Starting gitwatch in detached HEAD state, pushing to $target_branch" >&3
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin -b "$target_branch" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    sleep 1 # Allow watcher to initialize and detect state

    # 5. Trigger a new change (this will be committed on the detached commit, creating a new local commit)
    echo "second local commit" >> detached_file_2.txt

    # 6. Wait for the change to be pushed to the remote (by checking remote hash)
    # The push should use 'git push origin HEAD:master'
    run wait_for_git_change 30 1 git rev-parse origin/master
    assert_success "Push with detached HEAD timed out"

    # 7. Assert: Remote hash is the new local commit hash
    local final_local_hash=$(git rev-parse HEAD)
    local final_remote_hash=$(git rev-parse origin/master)
    assert_equal "$final_local_hash" "$final_remote_hash" "Local and remote hashes must match after detached push"
    assert_not_equal "$initial_remote_hash" "$final_remote_hash" "Remote hash should have changed"

    # 8. Assert: Log output confirms the detached HEAD push logic was used
    run cat "$output_file"
    assert_output --partial "HEAD is detached" "Should detect detached HEAD state"
    assert_output --partial "Executing push command: git push 'origin' HEAD:'master'" "Push command should use HEAD:branch format"

    # 9. Cleanup: Go back to master before teardown
    git checkout master &> /dev/null
    cd /tmp
}

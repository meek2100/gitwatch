#!/usr/bin/env bats

# Load helpers FIRST
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'

# Define the custom cleanup logic specific to this file
# Use standard echo to output debug info to avoid relying on bats-support inside teardown
_remotedirs_cleanup() {
  echo "# Running custom cleanup for remotedirs" >&3
  if [ -n "${dotgittestdir:-}" ] && [ -d "$dotgittestdir" ];
  then
    echo "# Removing external git dir: $dotgittestdir" >&3
    rm -rf "$dotgittestdir"
  fi
}

# Load the base setup/teardown AFTER defining the custom helper
# This file now contains _common_teardown() and a default teardown() wrapper
load 'bats-custom/startup-shutdown'

# Define the final teardown override that calls both the custom
# cleanup for this file and the common teardown logic.
teardown() {
  _remotedirs_cleanup # Call custom part first
  _common_teardown    # Then call the common part directly from the loaded file
}


@test "remote_git_dirs_working_with_commit_logging: -g flag works with external .git dir" {
    dotgittestdir=$(mktemp -d)
    # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
    run mv "$testdir/local/$TEST_SUBDIR_NAME/.git" "$dotgittestdir/"
    assert_success

    # Start gitwatch directly in the background
    # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 -g "$dotgittestdir/.git" "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1
    echo "line1" >> file1.txt

    # Wait for first commit using the external git dir
    wait_for_git_change 20 0.5 git --git-dir="$dotgittestdir/.git" log -1 --format=%H
    assert_success "First commit timed out"
    local lastcommit=$(git --git-dir="$dotgittestdir/.git" log -1 --format=%H)


    echo "line2" >> file1.txt

    # Wait for second commit event (by checking that the hash changes) using the external git dir
    wait_for_git_change 20 0.5 git --git-dir="$dotgittestdir/.git" log -1 --format=%H
    assert_success "Second commit timed out"

    # Verify that new commit hash is different
    local currentcommit=$(git --git-dir="$dotgittestdir/.git" log -1 --format=%H)
    assert_not_equal "$lastcommit" "$currentcommit" "Commit hash should be different after second change"

    # Verify commit message content
    run git --git-dir="$dotgittestdir/.git" log -1 --pretty=%B
    assert_success
    assert_output --partial "file1.txt"
    assert_output --partial "line2" # Depends on diff-lines output

    cd /tmp # Move out before teardown
}

@test "remote_git_dirs_working_with_commit_and_push: -g flag works with external .git dir and -r push" {
    dotgittestdir=$(mktemp -d)
    # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
    run mv "$testdir/local/$TEST_SUBDIR_NAME/.git" "$dotgittestdir/"
    assert_success

    # Start gitwatch directly in the background with -r and -g
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -r origin -g "$dotgittestdir/.git" "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!

    # Use the TEST_SUBDIR_NAME variable defined in bats-custom/startup-shutdown.bash
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    sleep 1
    echo "line1" >> file_for_remote.txt

    # Wait for the change to be pushed to the remote (by checking remote hash)
    wait_for_git_change 30 1 git rev-parse origin/master
    assert_success "Commit and push with -g timed out"

    # Verify that the local and remote hashes match (indicating successful push)
    # Use the external .git dir for the local check
    local local_commit_hash=$(git --git-dir="$dotgittestdir/.git" rev-parse master)
    local remote_commit_hash=$(git rev-parse origin/master)
    assert_equal "$local_commit_hash" "$remote_commit_hash" "Local and remote hashes do not match after -g push"

    # Verify commit message content
    run git --git-dir="$dotgittestdir/.git" log -1 --pretty=%B
    assert_success
    assert_output --partial "file_for_remote.txt"

    cd /tmp # Move out before teardown
}

@test "remote_git_dirs_file_target: -g flag works with external .git dir and single file target" {
    local target_file="single_watched_file.txt"
    local watched_file_path="$testdir/local/$TEST_SUBDIR_NAME/$target_file"
    dotgittestdir=$(mktemp -d)

    # 1. Create the target file and commit it locally (needed for setup)
    cd "$testdir/local/$TEST_SUBDIR_NAME"
    echo "Initial content for single file watch" > "$target_file"
    git add "$target_file"
    git commit -q -m "Initial commit for single file test"

    # 2. Move the .git directory externally
    run mv "$testdir/local/$TEST_SUBDIR_NAME/.git" "$dotgittestdir/"
    assert_success

    # 3. Get the initial commit hash using the external git dir
    local initial_hash
    initial_hash=$(git --git-dir="$dotgittestdir/.git" log -1 --format=%H)

    # 4. Start gitwatch targeting the file AND specifying the external git dir
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -g "$dotgittestdir/.git" "$watched_file_path" &
    GITWATCH_PID=$!
    sleep 1

    # 5. Modify the file to trigger the commit
    echo "Change to the single file" >> "$target_file"

    # 6. Wait for the commit to happen using the external git dir
    run wait_for_git_change 20 0.5 git --git-dir="$dotgittestdir/.git" log -1 --format=%H
    assert_success "Commit timed out, suggesting -g with file target failed"

    # 7. Verify the hash changed
    local final_hash=$(git --git-dir="$dotgittestdir/.git" log -1 --format=%H)
    assert_not_equal "$initial_hash" "$final_hash" "Commit hash should change after modifying single file"

    # 8. Verify the file content is in the index (proving the 'git add' used the correct work-tree)
    run git --git-dir="$dotgittestdir/.git" show HEAD:"$target_file"
    assert_output --partial "Change to the single file"

    cd /tmp # Move out before teardown
}

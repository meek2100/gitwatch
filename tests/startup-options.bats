#!/usr/bin/env bats

# Load standard helpers
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'
# Load custom helpers
load 'test_helper/custom-helpers'
# Load setup/teardown
load 'startup-shutdown'

# Test 1: Commit on start successfully commits staged changes
@test "startup_commit_f: -f flag commits staged changes on startup" {
    cd "$testdir/local/$TEST_SUBDIR_NAME"

    # 1. Create a file and stage it, but DO NOT commit it
    echo "staged on start" > file_to_commit.txt
    git add file_to_commit.txt

    # Get the initial commit hash from the setup
    local initial_commit_hash
    initial_commit_hash=$(git log -1 --format=%H)
    echo "# Initial hash: $initial_commit_hash" >&3

    # 2. Start gitwatch with -f
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -f "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!
    # 3. Wait for the new commit to appear (it should be immediate)
    run wait_for_git_change 20 0.5 git log -1 --format=%H
    assert_success "Initial commit on start timed out"

    # 4. Verify the hash has changed
    local startup_commit_hash=$output
    assert_not_equal "$initial_commit_hash" "$startup_commit_hash" "Commit hash should change after startup commit"

    # 5. Verify the content of the commit message (should be default)
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "Scripted auto-commit on change"


    cd /tmp
}

@test "startup_commit_f_with_push: -f flag also pushes the initial commit to remote" {
    cd "$testdir/local/$TEST_SUBDIR_NAME"

    # 1. Create a file and stage it, but DO NOT commit it
    echo "staged and pushed" > file_to_push.txt
    git add file_to_push.txt

    # Get the initial remote hash
    local initial_remote_hash
    initial_remote_hash=$(git rev-parse origin/master)
    echo "# Initial remote hash: $initial_remote_hash" >&3

    # 2. Start gitwatch with -f and -r origin
    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -f -r origin "$testdir/local/$TEST_SUBDIR_NAME" &
    GITWATCH_PID=$!

    # 3. Wait for the remote hash to change (push success)
    run wait_for_git_change 20 0.5 git rev-parse origin/master
    assert_success "Initial commit push timed out"

    # 4. Verify the remote hash has changed
    local final_remote_hash=$output
    assert_not_equal "$initial_remote_hash" "$final_remote_hash" "Remote hash should change after startup commit and push"

    # 5. Verify the local commit message
    run git log -1 --pretty=%B
    assert_success
    assert_output --partial "Scripted auto-commit on change"

    cd /tmp
}

# Test 2: Commit on start does nothing if no changes are pending
@test "startup_commit_no_change: -f flag does nothing if no changes are pending" {
    local output_file
    output_file=$(mktemp "$testdir/output.XXXXX")

    cd "$testdir/local/$TEST_SUBDIR_NAME"

    # Get the initial commit hash from the setup
    local initial_commit_hash
    initial_commit_hash=$(git log -1 --format=%H)
    echo "# Initial hash: $initial_commit_hash" >&3

    # 1. Start gitwatch with -f, logging all output
    # Note: Using WAITTIME from startup-shutdown.bash for the sleep duration

    "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -f "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
    GITWATCH_PID=$!
    # 2. Wait longer than the script's default commit/debounce time
    sleep "$WAITTIME"

    # 3. Verify the hash has NOT changed
    run git log -1 --format=%H
    assert_success
    local after_startup_hash=$output
    assert_equal "$initial_commit_hash" "$after_startup_hash" "Commit hash should NOT change if no changes are pending"

    # 4. Verify log output confirms no commit was made
    run cat "$output_file"
    assert_output --partial "No relevant changes detected by git status (porcelain check)."
    "Gitwatch should report no changes detected"
    refute_output --partial "Running git commit command:" "Should not show a commit command run"

    cd /tmp
}

# Test 3: Version flag
@test "startup_version_V: -V flag prints version and exits" {
    # 1. Get the expected version number dynamically from the VERSION file
    local version_file="${BATS_TEST_DIRNAME}/../VERSION"
    local expected_version_number=$(cat "$version_file")

    # 2. Run gitwatch with -V and verify output/exit status
    run "${BATS_TEST_DIRNAME}/../gitwatch.sh" -V
    assert_success "Running gitwatch -V should exit successfully"
    assert_output "gitwatch.sh version $expected_version_number" "Output should be the version string"
}

#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

@test "notify_ignore_raw_regex_x: -x ignores changes using raw regex" {
  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")
  # Start gitwatch directly in the background, ignoring test_subdir/ (raw regex pattern)
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -x "(test_subdir/|\.bak$)" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  mkdir test_subdir
  sleep 1

  # Allowed change (file in root)
  echo "line1" >> file1.txt
  # Wait for the first (allowed) commit to appear
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success
  run git log -1 --format=%H # Get the first commit hash
  local first_commit_hash=$output

  # Ignored changes (due to regex)
  echo "line2" >> test_subdir/file2.txt
  echo "backup" >> file.bak
  # This is a negative test: wait to ensure a commit *does not* happen
  sleep "$WAITTIME" # Use WAITTIME from setup

  run git log -1 --format=%H
  local second_commit_hash=$output
  assert_equal "$first_commit_hash" "$second_commit_hash" "Commit hash should NOT change for ignored files/directory"

  # Verify commit history
  run git log --name-status --oneline
  assert_success
  assert_output --partial "file1.txt"
  refute_output --partial "file2.txt"
  refute_output --partial "file.bak"

  run cat "$output_file"
  assert_output --partial "Change detected" # Should detect changes to file2 and file.bak
  refute_output --partial "test_subdir/file2.txt" # Should not contain log lines specific to file2.txt commit process
}

@test "notify_ignore_glob_X_combined: -X ignores files matching glob patterns and combines correctly with -x" {
  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")

  # Raw Regex (-x): Ignore anything starting with 'old_'
  local raw_regex='^old_'
  # Glob List (-X): Ignore *.log AND the temp/ directory
  local glob_list="*.log,temp/"
  local initial_hash

  # 1. Start gitwatch, combining exclusion patterns
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -x "$raw_regex" -X "$glob_list" "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  cd "$testdir/local/$TEST_SUBDIR_NAME"
  mkdir temp # The directory to be ignored
  sleep 1

  # Get initial hash
  initial_hash=$(git log -1 --format=%H)

  # Ignored changes (should not trigger a commit, proving exclusion works)
  echo "log entry" >> app.log        # -X (glob) ignore
  echo "backup" > old_config.txt     # -x (regex) ignore
  echo "temp data" >> temp/file.txt  # -X (glob directory) ignore

  # Allowed change (should force a single commit)
  echo "change" >> important.txt

  # Wait for the commit to finish
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success
  run git log -1 --format=%H
  local final_commit_hash=$output

  # 2. Assert hash changed (commit happened due to allowed file)
  assert_not_equal "$initial_hash" "$final_commit_hash" "Commit failed on allowed file."
  # 3. Assert: Log confirms all events were processed but one commit occurred.
  run cat "$output_file"
  # Should see the conversion happening
  assert_output --partial "Converting glob exclude pattern '.*\.log|temp/' from glob/comma-separated list to regex."
  # Should see change detection for ignored files
  assert_output --partial "temp/file.txt"
  assert_output --partial "old_config.txt"
  assert_output --partial "app.log"
  # Should see the allowed file getting committed
  assert_output --partial "important.txt"

  # 4. Assert: Final commit message only reflects the allowed file
  run git log -1 --pretty=%B
  assert_output --partial "important.txt"
  refute_output --partial "old_config.txt"
  refute_output --partial "app.log"
  refute_output --partial "temp/file.txt"
}

@test "notify_ignore_gitignore: Ignores files matching .gitignore" {
  local output_file
  output_file=$(mktemp "$testdir/output.XXXXX")

  cd "$testdir/local/$TEST_SUBDIR_NAME"

  # 1. Create and commit .gitignore
  echo "*.log" > .gitignore
  echo "build/" >> .gitignore
  git add .gitignore
  git commit -q -m "Add .gitignore"
  local initial_hash
  initial_hash=$(git log -1 --format=%H)

  # 2. Start gitwatch
  "${BATS_TEST_DIRNAME}/../gitwatch.sh" -v -l 10 "$testdir/local/$TEST_SUBDIR_NAME" > "$output_file" 2>&1 &
  GITWATCH_PID=$!
  sleep 1

  # 3. Create ignored and allowed files
  mkdir -p build
  echo "log data" > app.log
  echo "build artifact" > build/output.bin
  echo "allowed data" > allowed.txt

  # 4. Wait for the (allowed) commit to appear
  run wait_for_git_change 20 0.5 git log -1 --format=%H
  assert_success "Commit for allowed file timed out"
  local final_hash=$output
  assert_not_equal "$initial_hash" "$final_hash" "Commit hash did not change"

  # 5. Verify commit message only contains the allowed file
  run git log -1 --pretty=%B
  assert_output --partial "allowed.txt"
  refute_output --partial "app.log"
  refute_output --partial "build/output.bin"

  # 6. Verify git status shows ignored files are still untracked/ignored
  run git status --porcelain --ignored
  assert_output --partial "!! app.log"
  assert_output --partial "!! build/"

  cd /tmp
}

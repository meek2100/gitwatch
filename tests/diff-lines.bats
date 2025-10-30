#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# Source the main script to test functions directly
# This brings in diff-lines and its dependencies (_strip_color, _trim_spaces, stderr)
# shellcheck disable=SC1091 # gitwatch.sh is intentionally sourced for unit testing
source "${BATS_TEST_DIRNAME}/../gitwatch.sh"

# --- Test Cases ---
# These tests will now call the *actual* functions loaded from gitwatch.sh

@test "diff_lines_1_addition: Handles a simple file addition" {
  local DIFF_INPUT="
  --- /dev/null
  +++ b/new_file.txt
  @@ -0,0 +1,3 @@
  +line 1
  +line 2
  +line 3
  "
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  assert_output --regexp "new_file.txt:1: \+line 1"
  assert_output --regexp "new_file.txt:2: \+line 2"
  assert_output --regexp "new_file.txt:3: \+line 3"
}

@test "diff_lines_2_deletion: Handles a simple file deletion" {
  local DIFF_INPUT="
  --- a/old_file.txt
  +++ /dev/null
  @@ -1,3 +0,0 @@
  -line 1
  -line 2
  -line 3
  "
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  # For a full file deletion, the original logic tags the line as 'File deleted.'
  assert_output "old_file.txt:?: File deleted."
}

@test "diff_lines_3_modification: Handles modification with context lines" {
  local DIFF_INPUT="
  --- a/config.yaml
  +++ b/config.yaml
  @@ -10,6 +10,7 @@
  context line 1
  -old line to remove
  +new line 1 to add
  +new line 2 to add
  context line 2
  context line 3
  "
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  # Context lines
  assert_output --regexp "config.yaml:10:  context line 1"
  # Deletion (line number should not increment)
  assert_output --regexp "config.yaml:?: -old line to remove"
  # Addition (line number should continue from the hunk start 11)
  assert_output --regexp "config.yaml:11: \+new line 1 to add"
  assert_output --regexp "config.yaml:12: \+new line 2 to add"
  # Context line 2 (line number should have incremented correctly)
  assert_output --regexp "config.yaml:13:  context line 2"
}

@test "diff_lines_4_color_codes: Preserves color in content but strips from paths" {
  local ESC=$'\033'
  # Mock Git diff output with ANSI colors
  local DIFF_INPUT="
  --- a/file_with_color.txt
  +++ b/file_with_color.txt
  @@ -1,2 +1,2 @@
  -${ESC}[31mdeleted line${ESC}[0m
  +${ESC}[32madded line${ESC}[0m
  "
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  # The output should contain the ANSI codes exactly as printed in the input
  assert_output --regexp "file_with_color.txt:?: -${ESC}\[31mdeleted line${ESC}\[0m"
  assert_output --regexp "file_with_color.txt:1: \+${ESC}\[32madded line${ESC}\[0m"
}

@test "diff_lines_5_renamed: Handles file rename (with content change)" {
  # Note: A rename with content change is parsed as a delete + add
  local DIFF_INPUT="
  diff --git a/old_name.txt b/new_name.txt
  --- a/old_name.txt
  +++ b/new_name.txt
  @@ -1,2 +1,2 @@
  -Initial content
  +Updated content
  "
  run diff-lines <<< "$DIFF_INPUT"

  assert_success
  # Deletion uses previous_path
  assert_output --regexp "old_name.txt:?: -Initial content"
  # Addition uses new path
  assert_output --regexp "new_name.txt:1: \+Updated content"
}

@test "diff_lines_6_trim_spaces: Handles paths with leading/trailing spaces correctly (if diff allows it)" {
  # Although diff usually normalizes this, testing robustness
  local DIFF_INPUT="
  --- a/  path with spaces.txt
  +++ b/  path with spaces.txt
  @@ -1,1 +1,1 @@
  +content
  "
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  # Path names should be trimmed by _trim_spaces
  assert_output --regexp "path with spaces.txt:1: \+content"
}

@test "diff_lines_7_mode_change: Handles a file mode change" {
  local DIFF_INPUT="
  diff --git a/script.sh b/script.sh
  old mode 100644
  new mode 100755
  "
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  assert_output "script.sh:?: Mode changed to 100755"
}

@test "diff_lines_8_mode_and_content_change: Handles mode and content change" {
  local DIFF_INPUT="
  diff --git a/script.sh b/script.sh
  old mode 100644
  new mode 100755
  --- a/script.sh
  +++ b/script.sh
  @@ -1,1 +1,1 @@
  -old content
  +new content
  "
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  assert_output "script.sh:?: Mode changed to 100755"
  assert_output --regexp "script.sh:?: -old content"
  assert_output --regexp "script.sh:1: \+new content"
}

#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# Load ALL custom config, helpers, and setup/teardown hooks
load 'bats-custom/load'

# Source the main script to test functions directly
# This brings in diff-lines and its dependencies (_strip_color, _trim_spaces, stderr)
# shellcheck disable=SC1091 # gitwatch.sh is intentionally sourced for unit testing
source "${BATS_TEST_DIRNAME}/../gitwatch.sh"

# --- Test Cases ---
# These tests will now call the *actual* functions loaded from gitwatch.sh

@test "diff_lines_1_addition_handles_a_simple_file_addition" {
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

@test "diff_lines_2_deletion_handles_a_simple_file_deletion" {
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

@test "diff_lines_3_modification_handles_modification_with_context_lines" {
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

@test "diff_lines_4_color_codes_preserves_color_in_content_but_strips_from_paths" {
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

@test "diff_lines_5_renamed_handles_file_rename_with_content_change" {
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

@test "diff_lines_6_trim_spaces_handles_paths_with_leading_trailing_spaces_correctly" {
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

@test "diff_lines_7_mode_change_handles_a_file_mode_change" {
  local DIFF_INPUT="
diff --git a/script.sh b/script.sh
old mode 100644
new mode 100755
"
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  assert_output "script.sh:?: Mode changed to 100755"
}

@test "diff_lines_8_mode_and_content_change_handles_mode_and_content_change" {
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

@test "diff_lines_9_path_with_color_strips_color_codes_from_paths" {
  local ESC=$'\033'
  # Mock Git diff output with ANSI colors in the path
  local DIFF_INPUT="
  --- a/${ESC}[31mcolored_path.txt${ESC}[0m
  +++ b/${ESC}[32mcolored_path.txt${ESC}[0m
  @@ -1,1 +1,1 @@
  +new line
  "
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  # The output path should be clean, but content color would be preserved (if present)
  assert_output --regexp "colored_path.txt:1: \+new line"
  refute_output --regexp "${ESC}" "Path should not contain color codes"
}

@test "diff_lines_10_binary_file_handles_binary_file_diff" {
  local DIFF_INPUT="
diff --git a/logo.png b/logo.png
Binary files a/logo.png and b/logo.png differ
"
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  assert_output "logo.png:?: Binary file changed."
}

@test "diff_lines_11_rename_and_mode_change_handles_rename_and_mode_change" {
  local DIFF_INPUT="
diff --git a/old_script.sh b/new_script.sh
similarity index 100%
rename from old_script.sh
rename to new_script.sh
old mode 100644
new mode 100755
"
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  # The parser should output the mode change, associated with the new path
  assert_output "new_script.sh:?: Mode changed to 100755"
}

@test "diff_lines_12_rename_and_binary_handles_rename_of_a_binary_file" {
  local DIFF_INPUT="
diff --git a/old_logo.png b/new_logo.png
similarity index 90%
rename from old_logo.png
rename to new_logo.png
Binary files a/old_logo.png and b/new_logo.png differ
"
  run diff-lines <<< "$DIFF_INPUT"
  assert_success
  # The parser should output the binary change, associated with the new path
  assert_output "new_logo.png:?: Binary file changed."
}

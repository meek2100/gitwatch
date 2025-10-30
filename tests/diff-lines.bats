#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'
# Load custom helpers
load 'bats-custom/custom-helpers'
# Load setup/teardown
load 'bats-custom/startup-shutdown'

# --- Mock Dependencies for Isolation ---
# The actual logic for these functions lives inside gitwatch.sh,
# but we mock them here to unit-test diff-lines() in isolation.
stderr() {
  # Mock stderr output for debugging or warning messages
  echo "MOCK_STDERR: $*" >&3
}

_strip_color() {
  # Mock the core logic from gitwatch.sh to remove ANSI codes
  local input="${1:-$(cat)}"
  local esc=$'\033'
  # Remove all ANSI color codes (from $esc[...m to end)
  echo "${input//$esc\[[0-9;]*m/}"
}

_trim_spaces() {
  # Mock the core logic from gitwatch.sh to remove leading/trailing spaces
  local var="$1"
  var="${var#"${var%%[! ]*}"}"
  var="${var%"${var##*[! ]*}"}"
  echo "$var"
}

# --- diff-lines function (copied from gitwatch.sh for explicit unit testing) ---
# Note: This version relies on the mocked functions above.
diff-lines() {
  local path=""           # Current file path (for additions/modifications)
  local line=""           # Current line number in the new file (for additions)
  local previous_path=""  # Previous file path (used for deletions/renames)
  local esc=$'\033'       # Local variable for escape character
  local color_regex="^($esc\[[0-9;]*m)*" # Regex to match optional leading color codes
  local current_file_path # Path used for the final output line

  # NEW: Use $LOG_LINE_LENGTH from env, default to 150
  local LOG_LINE_LENGTH=${GW_LOG_LINE_LENGTH:-150}

  # Loop over diff lines, preserving leading/trailing whitespace (IFS= read -r)
  while IFS= read -r REPLY; do
    # 1. Strip leading color codes from the line for reliable regex matching
    # FIX: Quoting $color_regex to fix SC2295
    local stripped_reply="${REPLY##"$color_regex"}"

    # 2. Determine the raw line content (after removing the leading color codes)
    local raw_content_match
    local prefix=""

    # Check if this line is a content line (+, -, or ' ')
    if [[ "$stripped_reply" =~ ^([\ +-])(.*) ]]; then
      prefix=${BASH_REMATCH[1]}
      raw_content_match=${BASH_REMATCH[2]}
    fi

    # --- Match Headers and Update State ---

    # NEW: Match `diff --git a/PATH b/PATH` for mode changes or renames
    if [[ "$stripped_reply" =~ ^diff\ --git\ a/(.*)\ b/(.*) ]]; then
      previous_path=$(_trim_spaces "$(_strip_color "${BASH_REMATCH[1]}")")
      path=$(_trim_spaces "$(_strip_color "${BASH_REMATCH[2]}")")
      current_file_path="$path" # Set current path immediately
      line=""                   # Reset line number state
      continue

    # Match '--- a/path' or '--- /dev/null' - Capture everything after 'a/' or '/dev/null'
    elif [[ "$stripped_reply" =~ ^---\ (a/)?(.*) ]]; then
      # Capture the raw path (Group 2). Strip any potential trailing color codes.
      # FIX: Use explicit argument passing to fix SC2119/SC2120 and use pure Bash trim
      previous_path=$(_trim_spaces "$(_strip_color "${BASH_REMATCH[2]}")")
      path="" # Reset new path
      line="" # Reset line number
      # Handle /dev/null case for clarity
      if [[ "$previous_path" == "/dev/null" ]]; then previous_path=""; fi
      continue

      # Match '+++ b/path' - Capture everything after 'b/'
    elif [[ "$stripped_reply" =~ ^\+\+\+\ (b/)?(.*) ]]; then
      # Capture the raw path (Group 2). Strip any potential trailing color codes.
      # FIX: Use explicit argument passing to fix SC2119/SC2120 and use pure Bash trim
      path=$(_trim_spaces "$(_strip_color "${BASH_REMATCH[2]}")")
      current_file_path="$path" # Set current path
      # Ensure path is not /dev/null, which is technically possible but not relevant here
      if [[ "$path" == "/dev/null" ]]; then path=""; fi
      continue

      # Match hunk header: @@ -<old_start>[,<old_count>] +<new_start>[,<new_count>] @@
    elif [[ "$stripped_reply" =~ ^@@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,[0-9]+)?\ @@ ]]; then
      # Capture line number from BASH_REMATCH[2] (new_start group)
      line=${BASH_REMATCH[2]:-1} # Set starting line number for additions, default to 1
      continue

    # NEW: Match file mode changes
    elif [[ "$stripped_reply" =~ ^new\ mode\ ([0-9]+) ]]; then
      echo "$current_file_path:?: Mode changed to ${BASH_REMATCH[1]}"
      continue
    elif [[ "$stripped_reply" =~ ^old\ mode\ ([0-9]+) ]]; then
      continue # Ignore old mode line, wait for new mode line
    fi

    # --- Match Content Lines and Output ---

    # Only process if we matched a content line (prefix is +, -, or ' ')
    if [[ -n "$prefix" ]]; then

      # 3. Determine the final file path for output
      if [ "$prefix" = "-" ] && [ -n "$previous_path" ]; then
        # For deletions, use the previous path
        current_file_path="$previous_path"
      elif [ -n "$path" ]; then
        # For additions, context, or modifications, use the current path
        current_file_path="$path"
      else
        # Still inside a previous file block (e.g., mode change context line)
        current_file_path="$previous_path"
      fi

      if [ -z "$current_file_path" ]; then
        # Fail-safe: If path is empty, log warning and skip line
        stderr "Warning: Could not determine file path for diff line: $REPLY"
        continue
      fi

      # 4. Handle Deletions (Special Case for entire file deletion where line number is irrelevant)
      if [ "$prefix" = "-" ] && [ -z "$path" ] && [ -n "$previous_path" ] && [ "$line" = "" ]; then
        echo "$previous_path:?: File deleted."
        # 5. Handle all other lines (Addition, Modification, Context)
      elif [[ -n "$line" ]]; then
        # Apply width limit *after* capturing full content
        # MODIFIED: Use $LOG_LINE_LENGTH variable instead of 150
        local display_content=${raw_content_match:0:$LOG_LINE_LENGTH}

        # Output: path:line: [COLOR_CODES]+/-content
        # FIX: Quoting $stripped_reply to fix SC2295
        local color_codes=${REPLY%%"$stripped_reply"} # Re-capture original leading color codes

        # Ensure '?' is output for line number if not yet set/relevant
        local output_line=${line:-?}

        echo "$current_file_path:$output_line: ${color_codes}${prefix}${display_content}"
      fi

      # 6. Increment line number only for added or context lines
      if [[ "$prefix" != "-" ]] && [[ -n "$line" ]]; then
        # Only increment if 'line' is a valid number (should be due to hunk match)
        [[ "$line" =~ ^[0-9]+$ ]] && ((line++))
      fi
    fi
  done
}
# --- Test Cases ---

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

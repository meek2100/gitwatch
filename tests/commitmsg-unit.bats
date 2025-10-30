#!/usr/bin/env bats

# Load standard helpers
load 'bats-support/load'
load 'bats-assert/load'
load 'bats-file/load'

# --- Mock Dependencies for Isolation ---
# Copy functions from gitwatch.sh to test them in isolation.

stderr() {
  echo "MOCK_STDERR: $*" >&3
}

_strip_color() {
  local input="${1:-$(cat)}"
  local esc=$'\033'
  echo "${input//$esc\[[0-9;]*m/}"
}

_trim_spaces() {
  local var="$1"
  var="${var#"${var%%[! ]*}"}"
  var="${var%"${var##*[! ]*}"}"
  echo "$var"
}

# We need diff-lines as a dependency for generate_commit_message -l/L
diff-lines() {
  local path=""
  local line=""
  local previous_path=""
  local esc=$'\033'
  local color_regex="^($esc\[[0-9;]*m)*"
  local current_file_path
  local LOG_LINE_LENGTH=${GW_LOG_LINE_LENGTH:-150}

  while IFS= read -r REPLY; do
    local stripped_reply="${REPLY##"$color_regex"}"
    local raw_content_match
    local prefix=""

    if [[ "$stripped_reply" =~ ^([\ +-])(.*) ]]; then
      prefix=${BASH_REMATCH[1]}
      raw_content_match=${BASH_REMATCH[2]}
    fi
    if [[ "$stripped_reply" =~ ^diff\ --git\ a/(.*)\ b/(.*) ]]; then
      previous_path=$(_trim_spaces "$(_strip_color "${BASH_REMATCH[1]}")")
      path=$(_trim_spaces "$(_strip_color "${BASH_REMATCH[2]}")")
      current_file_path="$path"
      line=""
      continue
    elif [[ "$stripped_reply" =~ ^---\ (a/)?(.*) ]]; then
      previous_path=$(_trim_spaces "$(_strip_color "${BASH_REMATCH[2]}")")
      path=""
      line=""
      if [[ "$previous_path" == "/dev/null" ]]; then previous_path=""; fi
      continue
    elif [[ "$stripped_reply" =~ ^\+\+\+\ (b/)?(.*) ]]; then
      path=$(_trim_spaces "$(_strip_color "${BASH_REMATCH[2]}")")
      current_file_path="$path"
      if [[ "$path" == "/dev/null" ]]; then path=""; fi
      continue
    elif [[ "$stripped_reply" =~ ^@@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,[0-9]+)?\ @@ ]]; then
      line=${BASH_REMATCH[2]:-1}
      continue
    elif [[ "$stripped_reply" =~ ^new\ mode\ ([0-9]+) ]]; then
      echo "$current_file_path:?: Mode changed to ${BASH_REMATCH[1]}"
      continue
    elif [[ "$stripped_reply" =~ ^old\ mode\ ([0-9]+) ]]; then
      continue
    fi
    if [[ -n "$prefix" ]]; then
      if [ "$prefix" = "-" ] && [ -n "$previous_path" ]; then
        current_file_path="$previous_path"
      elif [ -n "$path" ]; then
        current_file_path="$path"
      else
        current_file_path="$previous_path"
      fi
      if [ -z "$current_file_path" ]; then
        stderr "Warning: Could not determine file path for diff line: $REPLY"
        continue
      fi
      if [ "$prefix" = "-" ] && [ -z "$path" ] && [ -n "$previous_path" ] && [ "$line" = "" ]; then
        echo "$previous_path:?: File deleted."
      elif [[ -n "$line" ]]; then
        local display_content=${raw_content_match:0:$LOG_LINE_LENGTH}
        local color_codes=${REPLY%%"$stripped_reply"}
        local output_line=${line:-?}
        echo "$current_file_path:$output_line: ${color_codes}${prefix}${display_content}"
      fi
      if [[ "$prefix" != "-" ]] && [[ -n "$line" ]]; then
        [[ "$line" =~ ^[0-9]+$ ]] && ((line++))
      fi
    fi
  done
}

# The function under test, copied from gitwatch.sh
generate_commit_message() {
  local local_commit_msg=""

  if [ -n "$DATE_FMT" ] && [[ "$COMMITMSG" == *%d* ]]; then
    local formatted_date
    if ! formatted_date=$(date "$DATE_FMT"); then
      stderr "Warning: Invalid date format '$DATE_FMT'. Using default commit message."
      formatted_date="<date format error>"
    fi
    local_commit_msg="${COMMITMSG//%d/$formatted_date}"
  else
    local_commit_msg="$FORMATTED_COMMITMSG"
  fi

  if [[ $LISTCHANGES -ge 0 ]]; then
    local DIFF_COMMITMSG
    set +e
    DIFF_COMMITMSG=$(bash -c "$GIT diff --staged -U0 '$LISTCHANGES_COLOR'" | diff-lines)
    local diff_lines_status=$?
    if [ $diff_lines_status -ne 0 ]; then
      stderr 'Warning: diff-lines pipeline failed. Commit message may be incomplete.'
      DIFF_COMMITMSG=""
    fi
    local LENGTH_DIFF_COMMITMSG=0
    if [ -n "$DIFF_COMMITMSG" ]; then
      LENGTH_DIFF_COMMITMSG=$(echo "$DIFF_COMMITMSG" | wc -l | xargs)
    fi
    if [[ $LENGTH_DIFF_COMMITMSG -eq 0 ]]; then
      local_commit_msg="File changes detected: $(bash -c "$GIT status -s")"
    elif [[ $LISTCHANGES -eq 0 || $LENGTH_DIFF_COMMITMSG -le $LISTCHANGES ]]; then
      local_commit_msg="$DIFF_COMMITMSG"
    else
      local stat_summary=""
      while IFS= read -r line; do
        if [[ "$line" == *"|"* ]]; then
          if [ -z "$stat_summary" ]; then
            stat_summary="$line"
          else
            stat_summary+=$'\n'"$line"
          fi
        fi
      done <<< "$(bash -c "$GIT diff --staged --stat")"
      if [ -n "$stat_summary" ]; then
        local_commit_msg="Too many lines changed ($LENGTH_DIFF_COMMITMSG > $LISTCHANGES). Summary:\n$stat_summary"
      else
        local_commit_msg="Too many lines changed ($LENGTH_DIFF_COMMITMSG > $LISTCHANGES) (diff --stat failed or had no summary)"
      fi
    fi
  fi

  if [ -n "${COMMITCMD:-}" ]; then
    local final_cmd_string=""
    if [ "$PASSDIFFS" -eq 1 ]; then
      final_cmd_string=$(printf "timeout -s 9 %s %s diff --staged --name-only | %s" "$TIMEOUT" "$GIT" "$COMMITCMD")
    else
      final_cmd_string=$(printf "timeout -s 9 %s %s" "$TIMEOUT" "$COMMITCMD")
    fi
    commit_output=$(bash -c "$final_cmd_string" 2>&1)
    commit_exit_code=$?
    if [ "$commit_exit_code" -eq 0 ]; then
      local_commit_msg="$commit_output"
    elif [ "$commit_exit_code" -eq 124 ]; then
      stderr "ERROR: Custom commit command '$COMMITCMD' timed out after $TIMEOUT seconds."
      local_commit_msg="Custom commit command timed out"
    else
      stderr "ERROR: Custom commit command '$COMMITCMD' failed with exit code $commit_exit_code."
      stderr "Command output: $commit_output"
      local_commit_msg="Custom command failed"
    fi
  fi
  echo "$local_commit_msg"
}

# --- Mock Git Command ---
mock_git() {
  if [[ "$*" == "diff --staged -U0 --color=always" ]]; then
    # Mock for -l
    echo "--- a/file.txt"
    echo "+++ b/file.txt"
    echo "@@ -1 +1 @@"
    echo "+added line"
  elif [[ "$*" == "diff --staged -U0 " ]]; then
    # Mock for -L
    echo "--- a/file.txt"
    echo "+++ b/file.txt"
    echo "@@ -1 +1 @@"
    echo "+added line (no color)"
  elif [[ "$*" == "diff --staged --stat" ]]; then
    # Mock for truncation summary
    echo " file.txt | 10 ++++++++++"
  elif [[ "$*" == "status -s" ]]; then
    # Mock for empty diff
    echo " M file.txt"
  elif [[ "$*" == "diff --staged --name-only" ]]; then
    # Mock for -C pipe
    echo "file_a.txt"
    echo "file_b.txt"
  else
    echo "MOCK_GIT: Unhandled command $*" >&2
  fi
}
export -f mock_git
export GIT="mock_git"
export TIMEOUT=60

# --- Test Cases ---

setup() {
  # Set default values for globals used by the function
  COMMITMSG="Auto-commit: %d"
  DATE_FMT="+%Y-%m-%d"
  LISTCHANGES=-1
  LISTCHANGES_COLOR="--color=always"
  COMMITCMD=""
  PASSDIFFS=0
  FORMATTED_COMMITMSG="" # This gets set by the script
  if [[ "$COMMITMSG" != *%d* ]]; then
    DATE_FMT=""
    FORMATTED_COMMITMSG="$COMMITMSG"
  else
    FORMATTED_COMMITMSG="$COMMITMSG"
  fi
}

@test "commitmsg_unit: Default message with date" {
  export DATE_FMT="+%Y" # Use just year for predictable test
  export COMMITMSG="Commit: %d"
  FORMATTED_COMMITMSG="$COMMITMSG" # Re-init
  LISTCHANGES=-1
  COMMITCMD=""

  run generate_commit_message
  assert_success
  assert_output "Commit: $(date +%Y)"
}

@test "commitmsg_unit: Custom message with no date" {
  export COMMITMSG="Static message"
  FORMATTED_COMMITMSG="$COMMITMSG" # Re-init
  DATE_FMT="" # Re-init
  LISTCHANGES=-1
  COMMITCMD=""

  run generate_commit_message
  assert_success
  assert_output "Static message"
}

@test "commitmsg_unit: -l flag (color) uses diff-lines" {
  LISTCHANGES=10 # Enable diff
  LISTCHANGES_COLOR="--color=always"

  run generate_commit_message
  assert_success
  assert_output "file.txt:1: +added line"
}

@test "commitmsg_unit: -L flag (no color) uses diff-lines" {
  LISTCHANGES=10 # Enable diff
  LISTCHANGES_COLOR="" # No color

  run generate_commit_message
  assert_success
  assert_output "file.txt:1: +added line (no color)"
}

@test "commitmsg_unit: -l flag truncates long diff" {
  LISTCHANGES=0 # Set limit to *less than* line count
  # Mock wc -l to return 10 lines
  # This is tricky, we'll mock 'git diff --staged --stat' instead
  # The diff-lines mock will return 1 line, so we set limit to 0
  # generate_commit_message will see length (1) > limit (0)

  run generate_commit_message
  assert_success
  assert_output --partial "Too many lines changed (1 > 0). Summary:"
  assert_output --partial "file.txt | 10 ++++++++++"
}

@test "commitmsg_unit: -c custom command overrides others" {
  LISTCHANGES=10 # Set this to prove it gets ignored
  COMMITMSG="Ignored: %d"
  COMMITCMD="echo 'Custom command output'"

  run generate_commit_message
  assert_success
  assert_output "Custom command output"
  refute_output --partial "Ignored"
  refute_output --partial "file.txt:1: +added line"
}

@test "commitmsg_unit: -C flag pipes files to custom command" {
  COMMITCMD="wc -l" # Command that reads from stdin
  PASSDIFFS=1

  run generate_commit_message
  assert_success
  assert_output --partial "2" # wc -l should see 2 lines from mock_git
}

@test "commitmsg_unit: -c command failure uses fallback" {
  COMMITCMD="command_that_fails_zz"
  PASSDIFFS=0

  run generate_commit_message
  assert_success
  assert_output "Custom command failed"
  assert_stderr --partial "ERROR: Custom commit command 'command_that_fails_zz' failed"
}

@test "commitmsg_unit: -c command timeout uses fallback" {
  export TIMEOUT=1 # Use short timeout for test
  COMMITCMD="sleep 3"
  PASSDIFFS=0

  run generate_commit_message
  assert_success
  assert_output "Custom commit command timed out"
  assert_stderr --partial "ERROR: Custom commit command 'sleep 3' timed out after 1 seconds."
}

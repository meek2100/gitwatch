#!/usr/bin/env bash
#
# gitwatch - watch file or directory and git commit all changes as they happen
#
# Copyright (C) 2013-2025  Patrick Lehner
#   with modifications and contributions by:
#   - Matthew McGowan
#   - Dominik D. Geyer
#   - Phil Thompson
#   - Dave Musicant
#   - Darin Theurer
#
#############################################################################
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#############################################################################
#
#   Idea and original code taken from http://stackoverflow.com/a/965274
#       original work by Lester Buck
#       (but heavily modified by now)
#
#   Requires the command 'inotifywait' to be available, which is part of
#   the inotify-tools (See https://github.com/rvoicilas/inotify-tools ),
#   and (obviously) git.
#   Will check the availability of both commands using the `which` command
#   and will abort if either command (or `which`) is not found.
#

# --- Production Hardening ---
# set -e: Exit immediately if a command exits with a non-zero status.
# set -u: Treat unset variables as an error when substituting.
# set -o pipefail: The return value of a pipeline is the status of
#                  the last command to exit with a non-zero status,
#                  or zero if no command exited with a non-zero status.
set -euo pipefail
# --------------------------

REMOTE=""
PULL_BEFORE_PUSH=0
BRANCH=""
SLEEP_TIME=2
DATE_FMT="+%Y-%m-%d %H:%M:%S"
COMMITMSG="Scripted auto-commit on change (%d) by gitwatch.sh"
COMMITCMD=""
PASSDIFFS=0
LISTCHANGES=-1
LISTCHANGES_COLOR="--color=always"
GIT_DIR=""
SKIP_IF_MERGING=0
VERBOSE=0
COMMIT_ON_START=0
EVENTS="" # User-defined events
USE_SYSLOG=0
SLEEP_PID="" # Define SLEEP_PID early for set -u safety

# Print a message about how to use this script
shelp() {
  echo "gitwatch - watch file or directory and git commit all changes as they happen"
  echo ""
  echo "Usage:"
  echo "${0##*/} [-s <secs>] [-d <fmt>] [-r <remote> [-b <branch>]]"
  echo "          [-m <msg>] [-l|-L <lines>] [-x <pattern>] [-M] [-S] [-v] [-f] <target>"
  echo ""
  echo "Where <target> is the file or folder which should be watched. The target needs"
  echo "to be in a Git repository, or in the case of a folder, it may also be the top"
  echo "folder of the repo."
  echo ""
  echo " -s <secs>        After detecting a change to the watched file or directory,"
  echo "                  wait <secs> seconds until committing, to allow for more"
  echo "                  write actions of the same batch to finish; default is 2sec"
  echo " -d <fmt>         The format string used for the timestamp in the commit"
  echo "                  message; see 'man date' for details; default is "
  echo '                  "+%Y-%m-%d %H:%M:%S"'
  echo " -r <remote>      If given and non-empty, a 'git push' to the given <remote>"
  echo "                  is done after every commit; default is empty, i.e. no push"
  echo " -R               If given along with -r, a 'git pull --rebase <remote>' is done before any push"
  echo " -b <branch>      The branch which should be pushed automatically;"
  echo "                - if not given, the push command used is  'git push <remote>',"
  echo "                    thus doing a default push (see git man pages for details)"
  echo "                - if given and"
  echo "                  + repo is in a detached HEAD state (at launch)"
  echo "                    then the command used is  'git push <remote> <branch>'"
  echo "                  + repo is NOT in a detached HEAD state (at launch)"
  echo "                    then the command used is"
  echo "                    'git push <remote> <current branch>:<branch>'  where"
  echo "                    <current branch> is the target of HEAD (at launch)"
  echo "                  if no remote was defined with -r, this option has no effect"
  echo " -g <path>        Location of the .git directory, if stored elsewhere in"
  echo "                  a remote location. This specifies the --git-dir parameter"
  echo " -l <lines>       Log the actual changes made in this commit, up to a given"
  echo "                  number of lines, or all lines if 0 is given"
  echo " -L <lines>       Same as -l but without colored formatting"
  echo " -m <msg>         The commit message used for each commit; all occurrences of"
  echo "                  %d in the string will be replaced by the formatted date/time"
  echo "                  (unless the <fmt> specified by -d is empty, in which case %d"
  echo "                  is replaced by an empty string); the default message is:"
  echo '                  "Scripted auto-commit on change (%d) by gitwatch.sh"'
  echo " -c <command>     The command to be run to generate a commit message. If empty,"
  echo "                  defaults to the standard commit message. This option overrides -m,"
  echo "                  -d, and -l."
  echo " -C               Pass list of diffed files to <command> via pipe. Has no effect if"
  echo "                  -c is not given."
  echo " -e <events>      Events passed to inotifywait to watch (defaults to "
  echo "                  'close_write,move,move_self,delete,create,modify')"
  echo "                  (useful when using inotify-win, e.g. -e modify,delete,move)"
  echo "                  (for fswatch/macOS, see fswatch documentation for --event)"
  echo " -f               Commit any pending changes on startup before watching."
  echo " -M               Prevent commits when there is an ongoing merge in the repo"
  echo " -S               Log all messages to syslog (daemon mode)."
  echo " -v               Run in verbose mode for debugging. Enables informational messages and command tracing (set -x)."
  echo " -x <pattern>     Pattern to exclude from inotifywait"
  echo ""
  echo "As indicated, several conditions are only checked once at launch of the"
  echo "script. You can make changes to the repo state and configurations even while"
  echo "the script is running, but that may lead to undefined and unpredictable (even"
  echo "destructive) behavior!"
  echo "It is therefore recommended to terminate the script before changing the repo's"
  echo "config and restarting it afterwards."
  echo ""
  echo 'By default, gitwatch tries to use the binaries "git", "inotifywait" (or "fswatch" on macOS),'
  echo "and \"flock\", expecting to find them in the PATH (it uses 'which' to check this"
  echo "and will abort with an error if they cannot be found). If you want to use"
  echo "binaries that are named differently and/or located outside of your PATH, you can"
  echo "define replacements in the environment variables GW_GIT_BIN, GW_INW_BIN, and"
  echo "GW_FLOCK_BIN for git, inotifywait/fswatch, and flock, respectively."
}

# print all arguments to stderr
stderr() {
  if [ "$USE_SYSLOG" -eq 1 ]; then
    logger -t "${0##*/}" -p daemon.error "$@" # Use script name as tag
  else
    echo "$@" >&2
  fi
}

# print all arguments to stdout if in verbose mode
verbose_echo() {
  if [ "$VERBOSE" -eq 1 ]; then
    if [ "$USE_SYSLOG" -eq 1 ]; then
      logger -t "${0##*/}" -p daemon.info "$@" # Use script name as tag
    else
      echo "$@"
    fi
  fi
}

# shellcheck disable=SC2329
# clean up at end of program, killing the remaining sleep process if it still exists
cleanup() {
  # shellcheck disable=SC2317
  verbose_echo "Cleanup function called. Exiting."
  # Check if SLEEP_PID is non-empty before trying to kill
  # shellcheck disable=SC2317
  if [[ -n ${SLEEP_PID:-} ]] && kill -0 "$SLEEP_PID" &> /dev/null; then
    # shellcheck disable=SC2317
    verbose_echo "Killing sleep process $SLEEP_PID."
    # shellcheck disable=SC2317
    kill "$SLEEP_PID" &> /dev/null
  fi
  # The lockfile descriptors (8 and 9) will be auto-released on exit
  # shellcheck disable=SC2317
  exit 0
}

# shellcheck disable=SC2329
# New signal handler function
signal_handler() {
  # shellcheck disable=SC2317
  stderr "Signal $1 received, shutting down."
  # shellcheck disable=SC2317
  exit 0 # This will trigger the EXIT trap
}

# Tests for the availability of a command
is_command() {
  hash "$1" 2> /dev/null
}

# Test whether or not current git directory has ongoing merge
is_merging () {
  # Use $GIT command which respects --git-dir
  [ -f "$($GIT rev-parse --git-dir)"/MERGE_HEAD ]
}

###############################################################################

# --- Signal Trapping ---
trap "cleanup" EXIT # make sure the timeout is killed when exiting script
trap "signal_handler INT" INT
trap "signal_handler TERM" TERM
# ---------------------

while getopts b:d:h:g:L:l:m:c:C:p:r:s:e:x:MRvSf option; do # Process command line options
  case "${option}" in
    b) BRANCH=${OPTARG} ;;
    d) DATE_FMT=${OPTARG} ;;
    h)
      shelp
      exit
      ;;
    g) GIT_DIR=${OPTARG} ;;
    l) LISTCHANGES=${OPTARG} ;;
    L)
      LISTCHANGES=${OPTARG}
      LISTCHANGES_COLOR=""
      ;;
    m) COMMITMSG=${OPTARG} ;;
    c) COMMITCMD=${OPTARG} ;;
    C) PASSDIFFS=1 ;;
    f) COMMIT_ON_START=1 ;;
    M) SKIP_IF_MERGING=1 ;;
    p | r) REMOTE=${OPTARG} ;;
    R) PULL_BEFORE_PUSH=1 ;;
    s) SLEEP_TIME=${OPTARG} ;;
    S) USE_SYSLOG=1 ;;
    v)
      VERBOSE=1
      # set -x # We enable set -x only if verbose *and* not syslog
      ;;
    x) EXCLUDE_PATTERN=${OPTARG} ;;
    e) EVENTS=${OPTARG} ;;
    *)
      stderr "Error: Option '${option}' does not exist."
      shelp
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1)) # Shift the input arguments, so that the input file (last arg) is $1 in the code below

if [ $# -ne 1 ]; then # If no command line arguments are left (that's bad: no target was passed)
  shelp               # print usage help
  exit                # and exit
fi

# Enable command tracing only if verbose and not using syslog (to avoid flooding syslog)
if [ "$VERBOSE" -eq 1 ] && [ "$USE_SYSLOG" -eq 0 ]; then
  set -x
fi


# if custom bin names are given, use them; otherwise fall back to defaults
# Use ${VAR:-} expansion for safety with set -u
if [ -z "${GW_GIT_BIN:-}" ]; then GIT="git"; else GIT="$GW_GIT_BIN"; fi
if [ -z "${GW_FLOCK_BIN:-}" ]; then FLOCK="flock"; else FLOCK="$GW_FLOCK_BIN"; fi

OS_TYPE=$(uname)

if [ -z "${GW_INW_BIN:-}" ]; then
  # if Mac, use fswatch
  if [ "$OS_TYPE" != "Darwin" ]; then
    INW="inotifywait"
    if [ -z "${EVENTS:-}" ]; then
      EVENTS="close_write,move,move_self,delete,create,modify"
    fi
  else
    INW="fswatch"
    if [ -z "${EVENTS:-}" ]; then
      # default events specified via a mask, see
      # https://emcrisostomo.github.io/fswatch/doc/1.14.0/fswatch.html/Invoking-fswatch.html#Numeric-Event-Flags
      # default of 414 = MovedTo + MovedFrom + Renamed + Removed + Updated + Created
      #                = 256 + 128+ 16 + 8 + 4 + 2
      EVENTS="414"
    fi
  fi
else
  INW="$GW_INW_BIN"
fi

# Check availability of selected binaries and die if not met
for cmd in "$GIT" "$INW" "$FLOCK"; do
  is_command "$cmd" || {
    stderr "Error: Required command '$cmd' not found."

    # Platform-specific hints
    if [ "$OS_TYPE" = "Darwin" ]; then
      # macOS hints
      case "$cmd" in
        "$GIT")
          stderr "  Hint: Install the Apple Command Line Tools by running 'xcode-select --install' or install with Homebrew: 'brew install git'"
          ;;
        "$FLOCK")
          stderr "  Hint: Install with Homebrew: 'brew install flock'"
          ;;
        "$INW")
          stderr "  Hint: Install with Homebrew: 'brew install fswatch'"
          ;;
      esac
    else
      # Linux hints
      case "$cmd" in
        "$GIT")
          stderr "  Hint: Install 'git' using your package manager (e.g., 'apt install git' or 'yum install git')."
          ;;
        "$FLOCK")
          stderr "  Hint: '$FLOCK' is part of the 'util-linux' package (e.g., 'apt install util-linux')."
          ;;
        "$INW")
          stderr "  Hint: '$INW' is part of the 'inotify-tools' package (e.g., 'apt install inotify-tools')."
          ;;
      esac
    fi
    exit 2
  }
done
# 'logger' is a special case, we only check if syslog is requested
if [ "$USE_SYSLOG" -eq 1 ] && ! is_command "logger"; then
  stderr "Error: Required command 'logger' not found (for -S syslog option)."
  exit 2
fi
unset cmd

###############################################################################

# --- Determine Absolute Paths ---
USER_PATH="$1"
TARGETDIR_ABS=""
TARGETFILE_ABS=""
GIT_DIR_PATH="" # Initialize

if [ -d "$USER_PATH" ]; then # if the target is a directory
    verbose_echo "Target is a directory."
    TARGETDIR="$USER_PATH"
    # Resolve potential symlinks and get absolute path *before* changing directory
    # Use standard tools, handle potential errors
    TARGETDIR_ABS=$(cd "$TARGETDIR" && pwd -P) || { stderr "Error resolving path for '$TARGETDIR'"; exit 5; }

    # Get the absolute path to the .git directory using git itself
    GIT_DIR_PATH=$(cd "$TARGETDIR_ABS" && "$GIT" rev-parse --absolute-git-dir 2>/dev/null) || { stderr "Error: Not a git repository: ${TARGETDIR_ABS}"; exit 6; }

    # Build clean exclude regex
    EXCLUDE_REGEX='(\.git/|\.git$)'
    if [ -n "${EXCLUDE_PATTERN:-}" ]; then
      EXCLUDE_REGEX="(\.git/|\.git$|$EXCLUDE_PATTERN)"
    fi

    # construct inotifywait/fswatch command-line
    if [ "$INW" = "inotifywait" ]; then
      INW_ARGS=("-qmr" "-e" "$EVENTS" "--exclude" "$EXCLUDE_REGEX" "$TARGETDIR_ABS")
    else # fswatch
      INW_ARGS=("--recursive" "--event" "$EVENTS" "-E" "--exclude" "$EXCLUDE_REGEX" "$TARGETDIR_ABS")
    fi
    GIT_ADD_ARGS="--all ."
    GIT_COMMIT_ARGS=""

elif [ -f "$USER_PATH" ]; then # if the target is a single file
    verbose_echo "Target is a file."
    # Get directory from path using bash expansion
    TARGETDIR="${USER_PATH%/*}"
    TARGETFILE="${USER_PATH##*/}"
    if [ "$USER_PATH" = "$TARGETDIR" ]; then TARGETDIR="."; fi
    if [ -z "$TARGETDIR" ]; then TARGETDIR="/"; fi

    # Resolve potential symlinks and get absolute path *before* changing directory
    TARGETDIR_ABS=$(cd "$TARGETDIR" && pwd -P) || { stderr "Error resolving path for '$TARGETDIR'"; exit 5; }
    TARGETFILE_ABS="$TARGETDIR_ABS/$TARGETFILE"

    # Get the absolute path to the .git directory using git itself
    GIT_DIR_PATH=$(cd "$TARGETDIR_ABS" && "$GIT" rev-parse --absolute-git-dir 2>/dev/null) || { stderr "Error: Not a git repository: ${TARGETDIR_ABS}"; exit 6; }

    # construct inotifywait/fswatch command-line
    if [ "$INW" = "inotifywait" ]; then
      INW_ARGS=("-qm" "-e" "$EVENTS" "$TARGETFILE_ABS")
    else # fswatch
      INW_ARGS=("--event" "$EVENTS" "$TARGETFILE_ABS")
    fi
    GIT_ADD_ARGS="$TARGETFILE_ABS"
    GIT_COMMIT_ARGS=""

else
    stderr "Error: The target is neither a regular file nor a directory."; exit 3;
fi

# If $GIT_DIR is set by user, it overrides the auto-detected path and adds relevant flags
if [ -n "${GIT_DIR:-}" ]; then
  if [ ! -d "$GIT_DIR" ]; then
    stderr ".git location specified with -g is not a directory: $GIT_DIR"; exit 4;
  fi
  # Use the user-provided GIT_DIR for lockfiles
  GIT_DIR_PATH="$GIT_DIR"
  # Add flags for subsequent git commands
  GIT="$GIT --no-pager --work-tree $TARGETDIR_ABS --git-dir $GIT_DIR_PATH"
fi

# --- Lockfile Setup ---
# Set up lockfile to prevent multiple script instances running on the same repo.
LOCKFILE="$GIT_DIR_PATH/gitwatch.lock"
# Set up a separate lockfile to prevent concurrent commit operations within this instance.
COMMIT_LOCKFILE="$GIT_DIR_PATH/gitwatch.commit.lock"

# Open main lockfile on FD 9. Lock is held for the script's lifetime.
exec 9>"$LOCKFILE"
"$FLOCK" -n 9 || {
  stderr "Error: gitwatch is already running on this repository (lockfile: $LOCKFILE)."; exit 1;
}
# --- End Lockfile Setup ---

# --- Change Directory AFTER Lockfile Setup ---
# Now change to the target directory for file watching and relative git operations
cd "$TARGETDIR_ABS" || {
  stderr "Error: Can't change directory to '${TARGETDIR_ABS}' after lock setup."; exit 5; # Should not happen, but safety check
}
# --- End Change Directory ---


# Check if commit message needs any formatting (date splicing)
# Replace grep with bash string comparison
if [[ "$COMMITMSG" != *%d* ]]; then # if commitmsg didn't contain %d
  DATE_FMT=""                                     # empty date format (will disable splicing in the main loop)
  FORMATTED_COMMITMSG="$COMMITMSG"                # save (unchanging) commit message
else
  # We need to set this so -u doesn't fail if %d is the only format
  FORMATTED_COMMITMSG="$COMMITMSG"
fi

# We have already cd'd into the target directory
verbose_echo "Watching from directory: $TARGETDIR_ABS"

PULL_CMD_ARRAY=()
PUSH_CMD_ARRAY=()

if [ -n "${REMOTE:-}" ]; then        # are we pushing to a remote?
  verbose_echo "Push remote selected: $REMOTE"
  if [ -z "${BRANCH:-}" ]; then      # Do we have a branch set to push to ?
    verbose_echo "No push branch selected, using default."
    PUSH_CMD_ARRAY=("$GIT" "push" "$REMOTE") # Branch not set, push to remote without a branch
  else
    # check if we are on a detached HEAD
    if HEADREF=$($GIT symbolic-ref HEAD 2> /dev/null); then # HEAD is not detached
      verbose_echo "Push branch selected: $BRANCH, current branch: ${HEADREF#refs/heads/}"
      PUSH_CMD_ARRAY=("$GIT" "push" "$REMOTE" "${HEADREF#refs/heads/}:$BRANCH")
    else # HEAD is detached
      verbose_echo "Push branch selected: $BRANCH, HEAD is detached."
      PUSH_CMD_ARRAY=("$GIT" "push" "$REMOTE" "$BRANCH")
    fi
  fi
  if [[ $PULL_BEFORE_PUSH -eq 1 ]]; then
    verbose_echo "Pull before push is enabled."
    PULL_CMD_ARRAY=("$GIT" "pull" "--rebase" "$REMOTE") # Branch not set, pull to remote without a branch
  fi

else
  verbose_echo "No push remote selected."
fi

# A function to reduce git diff output to the actual changed content, and insert file line numbers.
# Based on "https://stackoverflow.com/a/12179492/199142" by John Mellor
diff-lines() {
  local path=""
  local line=""
  local previous_path=""
  while IFS= read -r; do # Use IFS= to preserve leading/trailing whitespace
    local esc=$'\033' # Local variable for escape character
    # --- Match diff headers ---
    if [[ $REPLY =~ ^---\ (a/)?([^[:blank:]$esc]+) ]]; then
      previous_path=${BASH_REMATCH[2]}
      path="" # Reset path for new file diff
      line="" # Reset line number
      continue
    elif [[ $REPLY =~ ^\+\+\+\ (b/)?([^[:blank:]$esc]+) ]]; then
      path=${BASH_REMATCH[2]}
      continue
      # --- Match hunk header ---
    elif [[ $REPLY =~ ^@@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,[0-9]+)?\ @@ ]]; then
      line=${BASH_REMATCH[2]} # Set starting line number for additions
      continue
      # --- Match diff content lines ---
    elif [[ $REPLY =~ ^($esc\[[0-9;]+m)*([\ +-])(.*) ]]; then # Capture +/- and content
      local prefix=${BASH_REMATCH[2]}
      local content=${BASH_REMATCH[3]}
      local display_content=${content:0:150} # limit the line width locally

      if [[ $path == "/dev/null" ]]; then # File deleted
        echo "File $previous_path deleted or moved."
      elif [[ -n "$path" ]] && [[ -n "$line" ]]; then # Ensure path and line are set
        # Reconstruct the line with color codes if present, using prefix and limited content
        local color_codes=${BASH_REMATCH[1]}
        echo "$path:$line: $color_codes$prefix$display_content"
      else
        # This case should ideally not happen if diff format is standard
        stderr "Warning: Could not parse line number or path in diff-lines for: $REPLY"
        echo "?:?: $REPLY" # Fallback output
      fi

      # Increment line number only for added or context lines shown in the diff
      if [[ $prefix != - ]] && [[ -n "$line" ]]; then
        ((line++))
      fi
    fi
  done
}


# Generates the commit message based on user flags
generate_commit_message() {
  local local_commit_msg="" # Initialize to prevent potential unset variable error

  # Check if DATE_FMT is set and COMMITMSG contains %d
  if [ -n "$DATE_FMT" ] && [[ "$COMMITMSG" == *%d* ]]; then
    local formatted_date
    formatted_date=$(date "$DATE_FMT")
    local_commit_msg="${COMMITMSG//%d/$formatted_date}" # Replace all occurrences
  else
    # Use the pre-formatted or original COMMITMSG if no date splicing needed
    # FORMATTED_COMMITMSG is set during initialization if %d wasn't found
    local_commit_msg="$FORMATTED_COMMITMSG"
  fi

  if [[ $LISTCHANGES -ge 0 ]]; then # allow listing diffs in the commit log message
    local DIFF_COMMITMSG
    # Handle potential errors from git diff or diff-lines gracefully
    DIFF_COMMITMSG="$($GIT diff -U0 "$LISTCHANGES_COLOR" | diff-lines || { stderr 'Warning: diff-lines failed'; echo ''; })"
    local LENGTH_DIFF_COMMITMSG=0

    # Count lines in DIFF_COMMITMSG using bash loop
    if [ -n "$DIFF_COMMITMSG" ]; then
      while IFS= read -r; do
        ((LENGTH_DIFF_COMMITMSG++))
      done <<< "$DIFF_COMMITMSG"
    fi

    if [[ $LENGTH_DIFF_COMMITMSG -eq 0 ]]; then
      # If diff is empty (e.g., only mode changes, or diff-lines failed), use status
      local_commit_msg="File changes detected: $($GIT status -s)"
    elif [[ $LENGTH_DIFF_COMMITMSG -le $LISTCHANGES ]]; then
      # Use git diff output as the commit msg
      local_commit_msg="$DIFF_COMMITMSG"
    else
      # --- Replacement for 'grep |' ---
      local stat_summary=""
      # Process 'git diff --stat' output line by line
      while IFS= read -r line; do
        # Check if the line contains '|' using bash pattern matching
        if [[ "$line" == *"|"* ]]; then
          # Append the line to the summary, adding a newline if needed
          if [ -z "$stat_summary" ]; then
            stat_summary="$line"
          else
            stat_summary+=$'\n'"$line"
          fi
        fi
      done <<< "$($GIT diff --stat)" # Feed 'git diff --stat' output to the loop
      # Use the summary if it's not empty, otherwise fallback
      if [ -n "$stat_summary" ]; then
        local_commit_msg="$stat_summary"
      else
        local_commit_msg="Many lines changed (diff --stat failed or had no summary)"
      fi
      # --- End Replacement ---
    fi
  fi

  if [ -n "${COMMITCMD:-}" ]; then
    if [ "$PASSDIFFS" -eq 1 ]; then
      # If -C is set, pass the list of diffed files to the commit command
      # Capture potential errors from the custom command
      local_commit_msg="$($COMMITCMD < <($GIT diff --name-only) || { stderr "ERROR: Custom commit command '$COMMITCMD' failed."; echo "Custom command failed"; } )"
    else
      local_commit_msg="$($COMMITCMD || { stderr "ERROR: Custom commit command '$COMMITCMD' failed."; echo "Custom command failed"; } )"
    fi
  fi

  echo "$local_commit_msg"
}


# The main commit and push logic
_perform_commit() {
  local STATUS
  STATUS=$($GIT status -s)

  if [ -z "$STATUS" ]; then # only commit if status shows tracked changes.
    verbose_echo "No tracked changes detected."
    return
  fi

  verbose_echo "Tracked changes detected."
  # We want GIT_ADD_ARGS and GIT_COMMIT_ARGS to be word split
  # shellcheck disable=SC2086

  if [ "$SKIP_IF_MERGING" -eq 1 ] && is_merging; then
    verbose_echo "Skipping commit - repo is merging"
    return
  fi

  local FINAL_COMMIT_MSG
  FINAL_COMMIT_MSG=$(generate_commit_message)

  # --- Prevent empty commit message ---
  if [ -z "$FINAL_COMMIT_MSG" ]; then
    stderr "Warning: Generated commit message was empty. Using default."
    FINAL_COMMIT_MSG="Auto-commit: Changes detected"
  fi
  # -----------------------------------

  # shellcheck disable=SC2086
  $GIT add $GIT_ADD_ARGS || { stderr "ERROR: 'git add' failed."; return 1; }
  verbose_echo "Running git add with arguments: $GIT_ADD_ARGS"

  # shellcheck disable=SC2086
  $GIT commit $GIT_COMMIT_ARGS -m"$FINAL_COMMIT_MSG" || { stderr "ERROR: 'git commit' failed."; return 1; }
  verbose_echo "Running git commit with arguments: $GIT_COMMIT_ARGS -m\"$FINAL_COMMIT_MSG\""

  if [ ${#PULL_CMD_ARRAY[@]} -gt 0 ]; then
    verbose_echo "Executing pull command: ${PULL_CMD_ARRAY[*]}"
    if ! "${PULL_CMD_ARRAY[@]}"; then
      stderr "ERROR: 'git pull' failed. Skipping push."
      return 1 # Abort this commit/push
    fi
  fi

  if [ ${#PUSH_CMD_ARRAY[@]} -gt 0 ]; then
    verbose_echo "Executing push command: ${PUSH_CMD_ARRAY[*]}"
    if ! "${PUSH_CMD_ARRAY[@]}"; then
      stderr "ERROR: 'git push' failed."
      return 1 # Report failure
    fi
  fi
}

# Wrapper for perform_commit that uses a lock to prevent concurrent runs
perform_commit() {
  # Try to acquire a non-blocking lock on file descriptor 8 using COMMIT_LOCKFILE.
  # This prevents a new commit from starting if one is already in progress.
  # The lock is released automatically when this subshell exits.
  (
    "$FLOCK" -n 8 || {
      verbose_echo "Commit already in progress, skipping this trigger."
      exit 0 # Exit subshell gracefully, not the whole script
    }
    verbose_echo "Acquired commit lock (FD 8), running commit logic."
    _perform_commit
    # Lock on FD 8 is released when this subshell exits
  ) 8>"$COMMIT_LOCKFILE" # Lock is tied to this file descriptor (FD 8)
  # Capture the exit status of the subshell if needed for error handling
  local commit_status=$?
  if [ $commit_status -ne 0 ]; then
    stderr "Commit logic failed with status $commit_status"
    # Decide if the main script should exit based on commit failure
    # For now, we just log and continue watching
    # Consider adding an option to exit on commit failure if desired.
  fi
}

###############################################################################

# If -f is specified, perform an initial commit before starting to watch
if [ "$COMMIT_ON_START" -eq 1 ]; then
  verbose_echo "Performing initial commit check..."
  perform_commit
fi

# main program loop: wait for changes and commit them
#   whenever inotifywait reports a change, we spawn a timer (sleep process) that gives the writing
#   process some time (in case there are a lot of changes or w/e); if there is already a timer
#   running when we receive an event, we kill it and start a new one; thus we only commit if there
#   have been no changes reported during a whole timeout period
verbose_echo "Starting file watch. Command: ${INW} ${INW_ARGS[*]}"
"${INW}" "${INW_ARGS[@]}" | while IFS= read -r line; do # Use IFS= to preserve leading spaces in lines
  # Check if line is empty (can happen with some fswatch modes or if the pipe closes)
  if [ -z "$line" ]; then
    verbose_echo "Received empty line from watcher, possibly pipe closed?"
    continue # Or maybe exit? Depends on desired behavior if watcher dies.
  fi
  verbose_echo "Change detected: $line"

  # Drain any other events that are already in the pipe buffer.
  # This prevents "event thrashing" from thousands of events at once.
  while IFS= read -t 0.1 -r drain_line; do
    verbose_echo "Draining event: $drain_line"
  done

  # is there already a timeout process running?
  # Check if SLEEP_PID is non-empty before trying to kill
  if [[ -n ${SLEEP_PID:-} ]] && kill -0 "$SLEEP_PID" &> /dev/null; then
    # kill it and wait for completion
    kill "$SLEEP_PID" &> /dev/null || true # Ignore error if already dead
    wait "$SLEEP_PID" &> /dev/null || true # Ignore error if already waited for
  fi

  # start timeout process
  (
    # Ensure SLEEP_TIME is a valid number; fallback if not?
    # For now, assume it's valid due to getopts or default.
    sleep "$SLEEP_TIME"
    perform_commit
  ) & # and send into background

  SLEEP_PID=$! # and remember its PID

done

# If the watcher command fails (e.g., inotifywait limit reached), the loop exits.
# Because of 'set -e' and 'set -o pipefail', the script should exit automatically.
# This message is useful for debugging or if those options are removed.
verbose_echo "File watcher process ended (or failed). Exiting via loop termination."
exit 0 # Explicit exit to ensure cleanup trap runs

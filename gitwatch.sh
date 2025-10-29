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
#   Requires the command 'inotifywait' (Linux) or 'fswatch' (macOS),
#   and 'git'. Checks for these and provides installation hints.
#   'flock' is highly recommended for robustness and is checked for.
#

# --- Production Hardening ---
# set -e: Exit immediately if a command exits with a non-zero status.
# set -u: Treat unset variables as an error when substituting.
# set -o pipefail: The return value of a pipeline is the status of
#                  the last command to exit with a non-zero status,
#                  or zero if no command exited with a non-zero status.
set -euo pipefail
# --------------------------

# --- Version Info ---
# This placeholder will be replaced by the release workflow
GITWATCH_VERSION="%%GITWATCH_VERSION%%"
# --- End Version Info ---

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
# SLEEP_PID="" # No longer used by PID file debounce
USE_FLOCK=1 # Default to on, check for command availability below

# Print a message about how to use this script
shelp() {
  echo "gitwatch - watch file or directory and git commit all changes as they happen"
  echo ""
  echo "Usage:"
  echo "${0##*/} [-s <secs>] [-d <fmt>] [-r <remote> [-b <branch>]]"
  echo "          [-m <msg>] [-l|-L <lines>] [-x <pattern>] [-M] [-S] [-v] [-f] [-V] <target>"
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
  echo "                  -d, and -l. Executed via bash -c."
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
  echo " -V               Print version information and exit."
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
  echo "and \"flock\" (highly recommended for robust locking), expecting to find them in the PATH (it uses 'command -v' to check this"
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

# _strip_color: Removes ANSI color codes from the input string.
# Input: String via stdin or argument 1.
# Output: Clean string to stdout.
_strip_color() {
  local input="${1:-$(cat)}"
  # Define escape character
  local esc=$'\033'
  # Remove all ANSI color codes (from $esc[...m to end)
  # Use ${VAR//PATTERN/REPLACEMENT} with the escape variable for safety.
  echo "${input//$esc\[[0-9;]*m/}"
}

# _trim_spaces: Removes leading/trailing spaces.
# Input: String via argument 1.
# Output: Trimmed string to stdout.
# Uses pure bash parameter expansion to replace ' | xargs'.
_trim_spaces() {
  local var="$1"
  # Trim leading spaces (removes longest match of [^ ] from front)
  var="${var#"${var%%[! ]*}"}"
  # Trim trailing spaces (removes longest match of [^ ] from back)
  var="${var%"${var##*[! ]*}"}"
  echo "$var"
}

# shellcheck disable=SC2329 # Function is used via trap
# clean up at end of program
cleanup() {
  # shellcheck disable=SC2317 # Code is reachable via trap
  verbose_echo "Cleanup function called. Exiting."
  # The lockfile descriptors (8 and 9) will be auto-released on exit
  # shellcheck disable=SC2317 # Code is reachable via trap
  exit 0
}

# shellcheck disable=SC2329 # Function is used via trap
# New signal handler function
signal_handler() {
  # shellcheck disable=SC2317 # Code is reachable via trap
  stderr "Signal $1 received, shutting down."
  # shellcheck disable=SC2317 # Code is reachable via trap
  exit 0 # This will trigger the EXIT trap
}

# Tests for the availability of a command
is_command() {
  # Use command -v for better POSIX compliance and alias handling than hash
  command -v "$1" &> /dev/null
}

# Test whether or not current git directory has ongoing merge
# Uses the globally defined $GIT command string which might include --git-dir/--work-tree
is_merging () {
  # Execute in subshell to handle potential errors from rev-parse if not a repo yet
  # Use bash -c to correctly interpret the $GIT string with its arguments
  ( bash -c "$GIT rev-parse --git-dir" &>/dev/null && [ -f "$(bash -c "$GIT rev-parse --git-dir")"/MERGE_HEAD ] ) || return 1
}

# Check for git user.name and user.email
# This runs *after* $GIT is finalized, but *before* the main loop
check_git_config() {
  # Check global config
  local user_name
  user_name=$(bash -c "$GIT config --global user.name" 2>/dev/null || echo "")
  local user_email
  user_email=$(bash -c "$GIT config --global user.email" 2>/dev/null || echo "")

  # If global is not set, check local (which overrides global)
  if [ -z "$user_name" ]; then
    user_name=$(bash -c "$GIT config --local user.name" 2>/dev/null || echo "")
  fi
  if [ -z "$user_email" ]; then
    user_email=$(bash -c "$GIT config --local user.email" 2>/dev/null || echo "")
  fi

  # If either is *still* not set, warn the user.
  if [ -z "$user_name" ] || [ -z "$user_email" ]; then
    stderr "Warning: 'user.name' or 'user.email' is not set in your Git config."
    stderr "  Commits made by gitwatch may fail. To set them globally, run:"
    stderr "  git config --global user.name \"Your Name\""
    stderr "  git config --global user.email \"you@example.com\""
    # Don't exit, just warn.
  fi
}

###############################################################################

# --- Signal Trapping ---
# Note: The trap for EXIT/INT/TERM is redefined later to include PID file cleanup
trap "cleanup" EXIT # Ensure cleanup runs on script exit, for any reason
trap "signal_handler INT" INT # Handle Ctrl+C
trap "signal_handler TERM" TERM # Handle kill/systemd stop
# ---------------------

# --- Initialize GIT command string ---
# Use GW_GIT_BIN if set, otherwise default to "git"
# Use ${VAR:-} expansion for safety with set -u
if [ -z "${GW_GIT_BIN:-}" ]; then GIT="git"; else GIT="$GW_GIT_BIN"; fi
# --- End Initialize GIT ---

# --- Determine Target Directory Path *preliminarily* for -g flag ---
# This is needed because -g flag processing modifies the $GIT command string,
# which requires knowing the work-tree path early.
# Get the last argument properly, ignoring options and "--"
PRELIM_USER_PATH=""
for arg in "$@"; do
  # Skip options starting with '-' unless it's just '-' (stdin) or './-'
  if [[ "$arg" == -* ]] && [[ "$arg" != "-" ]] && [[ "$arg" != -./* ]]; then
    continue
  fi
  PRELIM_USER_PATH="$arg" # Keep track of the last non-option argument
done

PRELIM_TARGETDIR_ABS=""
# Use subshell to avoid changing main script directory yet and capture output
# Also suppress errors here as path validity checked later
if [ -n "$PRELIM_USER_PATH" ]; then # Only attempt if we found a potential path
  PRELIM_TARGETDIR_ABS=$(
    cd_result=""
    if [ -d "$PRELIM_USER_PATH" ]; then
      # Try cd, capture output, check exit status
      if cd_result=$(cd "$PRELIM_USER_PATH" && pwd -P 2>/dev/null); then echo "$cd_result"; fi
    elif [ -f "$PRELIM_USER_PATH" ]; then
      PRELIM_TARGETDIR="${PRELIM_USER_PATH%/*}"
      # Handle case where file is in root directory (dirname is '/')
      if [ -z "$PRELIM_TARGETDIR" ] && [[ "$PRELIM_USER_PATH" == /* ]]; then PRELIM_TARGETDIR="/"; fi
      # Handle case where file is in current directory (dirname is '.')
      if [ "$PRELIM_USER_PATH" = "$PRELIM_TARGETDIR" ] || [ -z "$PRELIM_TARGETDIR" ]; then PRELIM_TARGETDIR="."; fi
      # Try cd, capture output, check exit status
      if cd_result=$(cd "$PRELIM_TARGETDIR" && pwd -P 2>/dev/null); then echo "$cd_result"; fi
    fi
  ) || PRELIM_TARGETDIR_ABS="" # If subshell fails or path invalid, ensure it's empty
fi
# --- End Preliminary Path ---


while getopts b:d:h:g:L:l:m:c:C:p:r:s:e:x:MRvSfV option; do # Process command line options
  case "${option}" in
    b) BRANCH=${OPTARG} ;;
    d) DATE_FMT=${OPTARG} ;;
    h)
      shelp
      exit
      ;;
    g)
      GIT_DIR=${OPTARG}
      # --- Apply -g modification to GIT command string EARLY ---
      if [ -n "$PRELIM_TARGETDIR_ABS" ]; then
        # Basic check if GIT_DIR looks like a directory path
        if [[ "$GIT_DIR" != */* ]] && [[ "$GIT_DIR" != "." ]] && [[ "$GIT_DIR" != ".." ]] && [[ "$GIT_DIR" != /* ]]; then
          stderr "Warning: GIT_DIR '$GIT_DIR' specified with -g looks like a relative name, not a full path. Proceeding..."
        elif [ ! -d "$GIT_DIR" ]; then
          stderr "Warning: GIT_DIR '$GIT_DIR' specified with -g does not seem to be a directory. Proceeding..."
        fi
        # Resolve the user-provided path for GIT_DIR robustly
        RESOLVED_GIT_DIR=$(cd "$GIT_DIR" && pwd -P) || { stderr "Error resolving path for GIT_DIR '$GIT_DIR'"; exit 4; }
        # Modify the *global* GIT variable string, quoting paths
        GIT_CMD_BASE=$(echo "$GIT" | awk '{print $1}') # Get base git command
        # Reconstruct the GIT command string safely using printf %q
        GIT=$(printf "%s --no-pager --work-tree %q --git-dir %q" "$GIT_CMD_BASE" "$PRELIM_TARGETDIR_ABS" "$RESOLVED_GIT_DIR")

        verbose_echo "Using specified git directory: $RESOLVED_GIT_DIR (applied early to GIT command string)"
      else
        # If PRELIM_TARGETDIR_ABS is empty, we couldn't resolve the work tree path early
        stderr "Error: Cannot determine target directory path ('$PRELIM_USER_PATH') needed to apply -g option."
        exit 5
      fi
      # --- End Early -g Handling ---
      ;;
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
      # set -x is enabled below, after option parsing
      ;;
    V)
      echo "gitwatch.sh version ${GITWATCH_VERSION:-unknown}"
      exit 0
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
USER_PATH="$1" # Final user path after shifting options

# Enable command tracing only if verbose and not using syslog (to avoid flooding syslog)
if [ "$VERBOSE" -eq 1 ] && [ "$USE_SYSLOG" -eq 0 ]; then
  set -x
fi


# Determine Watcher Command (INW) and default events (moved after getopts)
# Use ${VAR:-} expansion for safety with set -u
OS_TYPE=$(uname)
if [ -z "${GW_INW_BIN:-}" ]; then
  if [ "$OS_TYPE" != "Darwin" ]; then
    INW="inotifywait"
    if [ -z "${EVENTS:-}" ]; then EVENTS="close_write,move,move_self,delete,create,modify"; fi
  else
    INW="fswatch"
    if [ -z "${EVENTS:-}" ]; then
      # default events specified via a mask, see
      # https://emcrisostomo.github.io/fswatch/doc/1.14.0/fswatch.html/Invoking-fswatch.html#Numeric-Event-Flags
      # default of 414 = MovedTo + MovedFrom + Renamed + Removed + Updated + Created
      #                = 256 + 128+ 16 + 8 + 4 + 2
      EVENTS="414";
    fi
  fi
else
  INW="$GW_INW_BIN"
fi

# Check availability of selected binaries (uses final $GIT, $INW, $FLOCK values)
# Check the base git command before potential modification by -g
BASE_GIT_CMD=$(echo "$GIT" | awk '{print $1}')
for cmd in "$BASE_GIT_CMD" "$INW"; do
  is_command "$cmd" || {
    stderr "Error: Required command '$cmd' not found."
    # ... (Platform-specific hints remain the same) ...
    if [ "$OS_TYPE" = "Darwin" ]; then
      # macOS hints
      case "$cmd" in
        "$BASE_GIT_CMD") stderr "  Hint: Install Apple Command Line Tools ('xcode-select --install') or Homebrew ('brew install git')" ;;
        "$INW") stderr "  Hint: Install with Homebrew: 'brew install fswatch'" ;;
      esac
    else
      # Linux hints
      case "$cmd" in
        "$BASE_GIT_CMD") stderr "  Hint: Install 'git' (e.g., 'apt install git')." ;;
        "$INW") stderr "  Hint: '$INW' is part of 'inotify-tools' (e.g., 'apt install inotify-tools')." ;;
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
# Add check for hash command needed for tmpdir fallback
if ! is_command "sha256sum" && ! is_command "md5sum"; then
  # Only warn if flock *is* available, as the hash is only needed for the fallback logic
  if is_command "$FLOCK"; then
    stderr "Warning: Neither 'sha256sum' nor 'md5sum' found. Lockfile fallback to /tmp might use less unique names."
  fi
fi
unset cmd BASE_GIT_CMD # Clean up

# --- Check for optional 'flock' dependency ---
# Use GW_FLOCK_BIN if set, otherwise default to "flock"
if [ -z "${GW_FLOCK_BIN:-}" ]; then FLOCK="flock"; else FLOCK="$GW_FLOCK_BIN"; fi

if ! is_command "$FLOCK"; then
  USE_FLOCK=0

  # --- Platform-specific hint ---
  flock_hint=""
  if [ "$OS_TYPE" = "Darwin" ]; then
    flock_hint="  Hint: Install with Homebrew: 'brew install flock'"
  else
    # Assume Linux/other Unix-like
    flock_hint="  Hint: Install 'flock' (e.g., 'apt install util-linux' or 'dnf install util-linux')."
  fi
  # --- End platform-specific hint ---

  stderr "Warning: 'flock' command not found.
$flock_hint
Proceeding without file locking. This may lead to commit race conditions during rapid file changes
or allow multiple gitwatch instances to run on the same repository, potentially causing
  errors or duplicate commits."
fi
# --- End flock check ---


# Determine the appropriate read timeout based on bash version
READ_TIMEOUT="1" # Default for older bash
# Check if BASH_VERSINFO is declared and is an array before accessing index 0
# Use parameter expansion ${VAR[0]:-} to provide a default (e.g., '0') if not set/empty

# START Patch for Compatibility Testing
if [ -n "${MOCK_BASH_MAJOR_VERSION:-}" ]; then
  # Use mock value for testing Bash compatibility logic
  bash_major_version="${MOCK_BASH_MAJOR_VERSION}"
else
# END Patch for Compatibility Testing
  # Use native version array for production
  bash_major_version="${BASH_VERSINFO[0]:-0}"
# START Patch for Compatibility Testing
fi
# END Patch for Compatibility Testing

if [[ "$bash_major_version" -ge 4 ]]; then
  READ_TIMEOUT="0.2" # Use faster timeout for modern bash
fi
verbose_echo "Using read timeout: $READ_TIMEOUT seconds (Bash version: ${bash_major_version})"


###############################################################################

# --- Determine Absolute Paths (Final) ---
# Resolve the user path now that options are processed
TARGETDIR_ABS=""
TARGETFILE_ABS=""
GIT_DIR_PATH="" # Initialize

if [ -d "$USER_PATH" ]; then
  verbose_echo "Target is a directory."
  TARGETDIR="$USER_PATH"
  TARGETDIR_ABS=$(cd "$TARGETDIR" && pwd -P) || { stderr "Error resolving path for '$TARGETDIR'"; exit 5; }

  # GIT_DIR_PATH logic moved AFTER getopts, handled below
  EXCLUDE_REGEX='(\.git/|\.git$)'
  if [ -n "${EXCLUDE_PATTERN:-}" ]; then EXCLUDE_REGEX="(\.git/|\.git$|$EXCLUDE_PATTERN)"; fi
  if [ "$INW" = "inotifywait" ]; then INW_ARGS=("-qmr" "-e" "$EVENTS" "--exclude" "$EXCLUDE_REGEX" "$TARGETDIR_ABS"); else INW_ARGS=("--recursive" "--event" "$EVENTS" "-E" "--exclude" "$EXCLUDE_REGEX" "$TARGETDIR_ABS"); fi
  # GIT_ADD_ARGS logic moved to _perform_commit
  GIT_COMMIT_ARGS=""

elif [ -f "$USER_PATH" ]; then
  verbose_echo "Target is a file."
  TARGETDIR="${USER_PATH%/*}"
  TARGETFILE="${USER_PATH##*/}"
  # Handle case where file is in current directory (dirname is '.')
  if [ "$USER_PATH" = "$TARGETDIR" ] || [ -z "$TARGETDIR" ] && [[ "$USER_PATH" != /* ]]; then TARGETDIR="."; fi
  # Handle case where file is in root directory (dirname is '/')
  if [ -z "$TARGETDIR" ] && [[ "$USER_PATH" == /* ]]; then TARGETDIR="/"; fi
  TARGETDIR_ABS=$(cd "$TARGETDIR" && pwd -P) || { stderr "Error resolving path for '$TARGETDIR'"; exit 5; }
  TARGETFILE_ABS="$TARGETDIR_ABS/$TARGETFILE"

  # GIT_DIR_PATH logic moved AFTER getopts, handled below
  if [ "$INW" = "inotifywait" ]; then INW_ARGS=("-qm" "-e" "$EVENTS" "$TARGETFILE_ABS"); else INW_ARGS=("--event" "$EVENTS" "$TARGETFILE_ABS"); fi
  # GIT_ADD_ARGS logic moved to _perform_commit
  GIT_COMMIT_ARGS=""
else
  stderr "Error: The target is neither a regular file nor a directory."; exit 3;
fi

# --- NEW: CRITICAL PRE-PERMISSION CHECK ON TARGET DIRECTORY ---
# Check if the current user has the necessary permissions (R/W/X)
# on the target directory itself ($TARGETDIR_ABS). This must run *before*
# any attempt to run 'git rev-parse' which fails with the generic message.
if ! [ -r "$TARGETDIR_ABS" ] || ! [ -w "$TARGETDIR_ABS" ] || ! [ -x "$TARGETDIR_ABS" ]; then
  CURRENT_UID=""
  CURRENT_USER=""
  CURRENT_UID=$(id -u 2>/dev/null || echo "Unknown UID")
  CURRENT_USER=$(id -n -u 2>/dev/null || echo "Unknown User")

  resolution_message=""
  if [ -n "${GITWATCH_DOCKER_ENV:-}" ]; then
    resolution_message=$(printf "
    Resolution required:
    1. **Container User Mismatch**: The current user (UID %s) lacks the required permissions.
    2. **Recommended Fix**: Ensure the host volume mounted to the repository (e.g., %s) is owned by the container's non-root user ('appuser').
    - You may need to run \`chown\` on the host path or use Docker's \`user\` option.
    " "$CURRENT_UID" "$TARGETDIR_ABS")
  else
    resolution_message=$(printf "
    Resolution required:
    1. **Check Ownership**: The current user (UID %s) does not own or have R/W/X access to the directory.
    2. **Recommended Fix**: Ensure the watched directory is owned by the user running gitwatch.sh.
    - Run: \`sudo chown -R \$USER:\$USER \"\$TARGETDIR_ABS\"\`
    " "$CURRENT_UID")
  fi

  stderr "========================================================================================="
  stderr "⚠️  CRITICAL PERMISSION ERROR: Cannot Access Target Directory"
  stderr "========================================================================================="
  stderr "The application is running as user: $CURRENT_USER (UID $CURRENT_UID)"
  stderr "Attempted to access target directory: $TARGETDIR_ABS"
  stderr ""
  stderr "This error indicates that the current user lacks the necessary Read/Write/Execute"
  stderr "permissions on the target directory itself, preventing Git initialization/checks."
  stderr ""
  stderr "$resolution_message"
  stderr "========================================================================================="
  exit 7
fi
# --- END NEW: CRITICAL PRE-PERMISSION CHECK ON TARGET DIRECTORY ---

# --- Determine Git Directory Path (Final) ---
# This now uses the potentially modified $GIT command string from getopts -g handling
# Run rev-parse from within the target directory context to correctly find .git
# Use bash -c to correctly interpret the $GIT string
GIT_DIR_PATH=$(cd "$TARGETDIR_ABS" && bash -c "$GIT rev-parse --absolute-git-dir" 2>/dev/null) || {
  # If the primary detection fails (e.g., maybe $TARGETDIR_ABS is inside .git?)
  # And if -g was used, trust the resolved path from earlier getopts
  if [ -n "${GIT_DIR:-}" ]; then
    # Re-resolve GIT_DIR just to be absolutely sure GIT_DIR_PATH is set correctly
    GIT_DIR_PATH=$(cd "$GIT_DIR" && pwd -P) || { stderr "Error: Could not resolve specified GIT_DIR '$GIT_DIR' and could not find repository from '$TARGETDIR_ABS'."; exit 6; }
    verbose_echo "Using specified git directory (final resolution): $GIT_DIR_PATH"
  else
    # If -g wasn't used and rev-parse failed, it's not a git repo
    stderr "Error: Not a git repository (or cannot find .git): ${TARGETDIR_ABS}"; exit 6;
  fi
}
verbose_echo "Determined git directory for lockfiles: $GIT_DIR_PATH"

# --- CRITICAL PERMISSION CHECK FOR NON-ROOT USER ON VOLUME MOUNT ---
# Check if the current user has the necessary permissions (Read/Write/Execute)
# on the .git directory. Failure here indicates a permission mismatch.
if ! [ -r "$GIT_DIR_PATH" ] || ! [ -w "$GIT_DIR_PATH" ] || ! [ -x "$GIT_DIR_PATH" ]; then
  CURRENT_UID="" # Initialize
  CURRENT_USER="" # Initialize
  # Use process substitution to get UID/Username robustly if the commands exist
  CURRENT_UID=$(id -u 2>/dev/null || echo "Unknown UID")
  CURRENT_USER=$(id -n -u 2>/dev/null || echo "Unknown User")

  # --- Custom Resolution Message based on Environment ---
  resolution_message=""
  if [ -n "${GITWATCH_DOCKER_ENV:-}" ]; then
    # Docker/Container-specific resolution
    resolution_message=$(printf "
    Resolution required:
    1. **Container User Mismatch**: The current user (UID %s) lacks the required permissions.
    2. **Recommended Fix**: Ensure the host volume mounted to the repository (e.g., /app/gitwatch-test/vault) is owned by the container's non-root user ('appuser').
    - You may need to run \`chown\` on the host path or use Docker's \`user\` option.
    " "$CURRENT_UID")
  else
    # Generic/Daemon/Standalone resolution
    resolution_message=$(printf "
    Resolution required:
    1. **Check Ownership**: The current user (UID %s) does not own or have write access to the '.git' folder.
    2. **Recommended Fix**: Ensure the watched directory is owned by the user running gitwatch.sh.
    - Run: \`sudo chown -R \$USER:\$USER \"\$GIT_DIR_PATH\"\`
    " "$CURRENT_UID")
  fi
  # ---------------------------------------------------

  stderr "========================================================================================="
  stderr "⚠️  CRITICAL PERMISSION ERROR: Cannot Access Git Repository Metadata"
  stderr "========================================================================================="
  stderr "The application is running as user: $CURRENT_USER (UID $CURRENT_UID)"
  stderr "Attempted to access Git directory: $GIT_DIR_PATH"
  stderr ""
  stderr "This error indicates that the current user lacks the necessary Read/Write/Execute"
  stderr "permissions on the Git repository's metadata folder (the '.git' directory)."
  stderr ""
  stderr "$resolution_message"
  stderr "========================================================================================="
  exit 7
fi
# --- END PERMISSION CHECK ---

# Ensure GIT_DIR_PATH is absolute (belt-and-suspenders)
if [[ "$GIT_DIR_PATH" != /* ]]; then
  # This might happen if rev-parse somehow failed to give absolute path or -g was relative
  GIT_DIR_PATH=$(bash -c "$GIT rev-parse --git-path '$GIT_DIR_PATH'") || { stderr "Error finalizing git directory path."; exit 6; }
fi
# --- End Git Directory Path ---


# --- Lockfile Setup ---
LOCKFILE_DIR="$GIT_DIR_PATH"
LOCKFILE_BASENAME="gitwatch"

# Check for write permission. If it fails, fall back to $TMPDIR
if [ "$USE_FLOCK" -eq 1 ]; then
  if ! touch "$LOCKFILE_DIR/gitwatch.lock.tmp" 2>/dev/null; then
    verbose_echo "Warning: Cannot write lockfile to $LOCKFILE_DIR. Falling back to temporary directory."
    # Use $TMPDIR if set, otherwise /tmp
    LOCKFILE_DIR="${TMPDIR:-/tmp}"
    # Create a unique, predictable lockfile name based on the repo path
    # Use sha256sum if available, md5sum as fallback, or just path chars as last resort
    REPO_HASH=""
    if is_command "sha256sum"; then
      REPO_HASH=$(echo -n "$GIT_DIR_PATH" | sha256sum | awk '{print $1}')
    elif is_command "md5sum"; then
      REPO_HASH=$(echo -n "$GIT_DIR_PATH" | md5sum | awk '{print $1}')
    else
      # Simple "hash" for POSIX compliance, replaces / with _
      REPO_HASH="${GIT_DIR_PATH//\//_}"
    fi
    LOCKFILE_BASENAME="gitwatch-$REPO_HASH"
    verbose_echo "Using temporary lockfile base: $LOCKFILE_DIR/$LOCKFILE_BASENAME"
  else
    # We have write permission, clean up our test file
    rm "$LOCKFILE_DIR/gitwatch.lock.tmp"
  fi
fi

LOCKFILE="$LOCKFILE_DIR/$LOCKFILE_BASENAME.lock"
COMMIT_LOCKFILE="$LOCKFILE_DIR/$LOCKFILE_BASENAME.commit.lock"
# --- End tmpdir Fallback ---

if [ "$USE_FLOCK" -eq 1 ]; then
  # Open main lockfile on FD 9. Lock is held for the script's lifetime.
  # FD 9 is chosen arbitrarily, avoid 0, 1, 2.
  exec 9>"$LOCKFILE"
  "$FLOCK" -n 9 || {
    stderr "Error: gitwatch is already running on this repository (lockfile: $LOCKFILE)."; exit 1;
  }
  verbose_echo "Acquired main instance lock (FD 9) on $LOCKFILE"
fi
# --- End Lockfile Setup ---

# --- Change Directory AFTER Lockfile Setup ---
# Now change to the target directory for file watching and relative git operations
cd "$TARGETDIR_ABS" || {
  # This should not happen due to earlier check, but belts and suspenders
  stderr "Error: Can't change directory to '${TARGETDIR_ABS}' after lock setup."; exit 5;
}
verbose_echo "Changed working directory to $TARGETDIR_ABS"
# --- End Change Directory ---

# Run Git Config Check
# This is placed *after* changing directory, so repo-local config is found
check_git_config
# --- End Git Config Check ---


# Check if commit message needs any formatting (date splicing)
# Use bash check for %d, avoiding grep dependency here
if [[ "$COMMITMSG" != *%d* ]]; then # if commitmsg didn’t contain %d
  DATE_FMT=""                                     # empty date format (will disable splicing in the main loop)
  FORMATTED_COMMITMSG="$COMMITMSG"                # save (unchanging) commit message
else
  # FORMATTED_COMMITMSG needs to be set, otherwise 'set -u' might fail later if DATE_FMT is empty
  FORMATTED_COMMITMSG="$COMMITMSG"
fi

# We have already cd'd into the target directory
# Note: $GIT variable now correctly includes --git-dir/--work-tree if -g was used

# --- Prepare Pull/Push Command Strings (No eval needed here) ---
PULL_CMD="" # Ensure PULL_CMD is initialized for set -u
PUSH_CMD="" # Ensure PUSH_CMD is initialized for set -u

if [ -n "${REMOTE:-}" ]; then        # are we pushing to a remote?
  verbose_echo "Push remote selected: $REMOTE"
  if [ -z "${BRANCH:-}" ]; then      # Do we have a branch set to push to ?
    verbose_echo "No push branch selected, using default."
    PUSH_CMD="$GIT push '$REMOTE'" # Build command string, quoting remote
  else
    # check if we are on a detached HEAD
    # Use bash -c "$GIT ..." to run commands with correct context
    if HEADREF=$(bash -c "$GIT symbolic-ref HEAD" 2> /dev/null); then # HEAD is not detached
      verbose_echo "Push branch selected: $BRANCH, current branch: ${HEADREF#refs/heads/}"
      PUSH_CMD=$(printf "%s push %q %s:%q" "$GIT" "$REMOTE" "${HEADREF#refs/heads/}" "$BRANCH")
    else # HEAD is detached
      verbose_echo "Push branch selected: $BRANCH, HEAD is detached."
      PUSH_CMD=$(printf "%s push %q %q" "$GIT" "$REMOTE" "$BRANCH")
    fi
  fi
  if [[ $PULL_BEFORE_PUSH -eq 1 ]]; then
    verbose_echo "Pull before push is enabled."
    # Get current branch name for pull, handle detached HEAD
    CURRENT_BRANCH_FOR_PULL=$(bash -c "$GIT symbolic-ref --short HEAD" 2>/dev/null || echo "")
    if [ -n "$CURRENT_BRANCH_FOR_PULL" ]; then
      PULL_CMD=$(printf "%s pull --rebase %q %q" "$GIT" "$REMOTE" "$CURRENT_BRANCH_FOR_PULL")
    else
      stderr "Warning: Cannot determine current branch for pull (detached HEAD?). Using default pull."
      PULL_CMD=$(printf "%s pull --rebase %q" "$GIT" "$REMOTE")
    fi
  fi
else
  verbose_echo "No push remote selected."
fi
# --- End Pull/Push Command Setup ---

# diff-lines: Parses git diff output, extracts relevant lines, and prepends
#             the path and line number to each relevant content line.
#
# Logic: Based on state (previous_path, path, line), it reconstructs
#        the change log. Preserves color codes in the final output.
#
# Arguments: Receives git diff output via stdin.
diff-lines() {
  local path=""           # Current file path (for additions/modifications)
  local line=""           # Current line number in the new file (for additions)
  local previous_path=""  # Previous file path (used for deletions/renames)
  local esc=$'\033'       # Local variable for escape character
  local color_regex="^($esc\[[0-9;]+m)*" # Regex to match optional leading color codes
  local current_file_path # Path used for the final output line

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

    # Match '--- a/path' or '--- /dev/null' - Capture everything after 'a/' or '/dev/null'
    if [[ "$stripped_reply" =~ ^---\ (a/)?(.*) ]]; then
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
      # Ensure path is not /dev/null, which is technically possible but not relevant here
      if [[ "$path" == "/dev/null" ]]; then path=""; fi
      continue

      # Match hunk header: @@ -<old_start>[,<old_count>] +<new_start>[,<new_count>] @@
    elif [[ "$stripped_reply" =~ ^@@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+)(,[0-9]+)?\ @@ ]]; then
      # Capture line number from BASH_REMATCH[2] (new_start group)
      line=${BASH_REMATCH[2]:-1} # Set starting line number for additions, default to 1
      continue
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
        local display_content=${raw_content_match:0:150}

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


# Generates the commit message based on user flags
generate_commit_message() {
  local local_commit_msg="" # Initialize

  # Check if DATE_FMT is set and COMMITMSG contains %d
  if [ -n "$DATE_FMT" ] && [[ "$COMMITMSG" == *%d* ]]; then
    local formatted_date
    if ! formatted_date=$(date "$DATE_FMT"); then
      stderr "Warning: Invalid date format '$DATE_FMT'. Using default commit message."
      formatted_date="<date format error>"
    fi
    # Use simple parameter expansion, more robust than sed for this case
    local_commit_msg="${COMMITMSG//%d/$formatted_date}"
  else
    local_commit_msg="$FORMATTED_COMMITMSG"
  fi

  if [[ $LISTCHANGES -ge 0 ]]; then
    local DIFF_COMMITMSG
    set +e # Temporarily disable exit on error for this pipeline
    # Use --staged or --cached to show diff of what's about to be committed
    DIFF_COMMITMSG=$(bash -c "$GIT diff --staged -U0 '$LISTCHANGES_COLOR'" | diff-lines)
    local diff_lines_status=$?
    #set -e # Re-enable exit on error (Keep disabled if set -e is globally off)
    if [ $diff_lines_status -ne 0 ]; then
      stderr 'Warning: diff-lines pipeline failed. Commit message may be incomplete.'
      DIFF_COMMITMSG=""
    fi

    local LENGTH_DIFF_COMMITMSG=0
    # Count lines using wc -l (more robust than bash loop for potentially large diffs)
    if [ -n "$DIFF_COMMITMSG" ]; then
      # Ensure wc -l handles empty input correctly (outputs 0)
      LENGTH_DIFF_COMMITMSG=$(echo "$DIFF_COMMITMSG" | wc -l | xargs) # xargs trims whitespace
    fi

    if [[ $LENGTH_DIFF_COMMITMSG -eq 0 ]]; then
      # If diff is empty (e.g., only mode changes, or diff-lines failed), use status
      local_commit_msg="File changes detected: $(bash -c "$GIT status -s")"
    elif [[ $LISTCHANGES -eq 0 || $LENGTH_DIFF_COMMITMSG -le $LISTCHANGES ]]; then # LISTCHANGES=0 means no limit
      # Use git diff output as the commit msg
      local_commit_msg="$DIFF_COMMITMSG"
    else # Diff is longer than the limit
      # --- Replacement for 'grep |' ---
      local stat_summary=""
      # Process 'git diff --staged --stat' output line by line
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
      done <<< "$(bash -c "$GIT diff --staged --stat")" # Feed 'git diff --staged --stat' output to the loop
      # Use the summary if it's not empty, otherwise fallback
      if [ -n "$stat_summary" ]; then
        local_commit_msg="Too many lines changed ($LENGTH_DIFF_COMMITMSG > $LISTCHANGES). Summary:\n$stat_summary"
      else
        local_commit_msg="Too many lines changed ($LENGTH_DIFF_COMMITMSG > $LISTCHANGES) (diff --stat failed or had no summary)"
      fi
    fi
  fi

  if [ -n "${COMMITCMD:-}" ]; then
    if [ "$PASSDIFFS" -eq 1 ]; then
      # Use process substitution and pipe to custom command
      # Use bash -c for safer execution of complex commands
      local pipe_cmd
      # Pipe staged files diff
      pipe_cmd=$(printf "%s diff --staged --name-only | %s" "$GIT" "$COMMITCMD")
      local_commit_msg=$(bash -c "$pipe_cmd" || { stderr "ERROR: Custom commit command '$COMMITCMD' with pipe failed."; echo "Custom command failed"; } )
    else
      # Use bash -c for safer execution of complex commands
      local_commit_msg=$(bash -c "$COMMITCMD" || { stderr "ERROR: Custom commit command '$COMMITCMD' failed."; echo "Custom command failed"; } )
    fi
  fi

  echo "$local_commit_msg"
}


# The main commit and push logic
_perform_commit() {
  # *** NEW PURE BASH STATUS CHECK ***
  local porcelain_output
  porcelain_output=$(bash -c "$GIT status --porcelain")

  if [ -z "$porcelain_output" ]; then
    verbose_echo "No relevant changes detected by git status (porcelain check)."
    return 0
  fi
  verbose_echo "Relevant changes detected by git status (porcelain check): $porcelain_output"
  # *** END NEW PURE BASH STATUS CHECK ***

  if [ "$SKIP_IF_MERGING" -eq 1 ] && is_merging; then
    verbose_echo "Skipping commit - repo is merging"
    return 0
  fi

  # Add changes
  local add_cmd
  if [ -n "${TARGETFILE_ABS:-}" ]; then
    add_cmd=$(printf "%s add %q" "$GIT" "$TARGETFILE_ABS")
  else
    add_cmd=$(printf "%s add --all ." "$GIT")
  fi
  bash -c "$add_cmd" || { stderr "ERROR: 'git add' failed."; return 1; }
  verbose_echo "Running git add command: $add_cmd"

  # *** MODIFIED CHECK: Use git write-tree comparison ***
  # Final check: Only proceed if the staged tree differs from HEAD's tree (meaning content or number of files changed).
  local staged_tree_hash
  staged_tree_hash=$(bash -c "$GIT write-tree") || {
    # If write-tree fails (e.g., due to index corruption), simply abort.
    verbose_echo "Error in git write-tree. Aborting commit."
    return 0 # Treat as non-fatal, might recover on next change
  }
  local head_tree_hash
  # Get the tree hash of the last commit's content. Returns empty if no initial commit exists yet.
  head_tree_hash=$(bash -c "$GIT rev-parse HEAD:." 2>/dev/null) || head_tree_hash=""

  if [ "$staged_tree_hash" = "$head_tree_hash" ]; then
    verbose_echo "Staged tree is identical to HEAD (only ephemeral metadata changed). Aborting commit."
    # If git add coerced a spurious metadata change into the index, unstage it before exiting.
    bash -c "$GIT reset --mixed" &> /dev/null || true # Use reset --mixed
    return 0
  fi

  verbose_echo "Content or significant file changes detected (staged tree hash differs from HEAD). Committing."
  # *** END MODIFIED CHECK ***


  # Generate commit message (reflects staged changes)
  local FINAL_COMMIT_MSG
  FINAL_COMMIT_MSG=$(generate_commit_message)

  if [ -z "$FINAL_COMMIT_MSG" ]; then
    stderr "Warning: Generated commit message was empty. Using default."
    FINAL_COMMIT_MSG="Auto-commit: Changes detected"
  fi

  # Commit
  local commit_cmd
  commit_cmd=$(printf "%s commit %s -m %q" "$GIT" "$GIT_COMMIT_ARGS" "$FINAL_COMMIT_MSG")

  # Run the commit command and capture its output and exit code
  commit_output=$(bash -c "$commit_cmd" 2>&1) # Capture stdout and stderr
  commit_exit_code=$? # Capture the exit code immediately

  # Check the captured exit code
  if [ "$commit_exit_code" -eq 0 ]; then
    # Commit succeeded
    verbose_echo "Running git commit command: $commit_cmd"
    # Optional: Log the commit output if verbose and needed for debugging
    # verbose_echo "Commit output: $commit_output"
  else
    # Commit failed
    # Check stderr/stdout for "nothing to commit" as a secondary check (more robust than just exit code 1)
    if [[ "$commit_output" == *"nothing to commit"* ]]; then
      verbose_echo "Commit attempted, but no changes to commit (post write-tree check)."
      # This case should ideally not happen if write-tree check works, but handle defensively
      return 0 # Return success
    else
      # It was a different, unexpected error
      stderr "ERROR: 'git commit' failed with exit code $commit_exit_code."
      stderr "Commit output: $commit_output"
      return 1 # Return failure
    fi
  fi

  # Pull (if enabled)
  if [ -n "$PULL_CMD" ]; then
    verbose_echo "Executing pull command: $PULL_CMD"
    if ! bash -c "$PULL_CMD"; then
      stderr "ERROR: 'git pull' failed. Skipping push."
      return 1 # Abort
    fi
  fi

  # Push (if enabled)
  if [ -n "$PUSH_CMD" ]; then
    verbose_echo "Executing push command: $PUSH_CMD"
    if ! bash -c "$PUSH_CMD"; then
      stderr "ERROR: 'git push' failed."
      return 1 # Report failure
    fi
  fi
  return 0
}


# Wrapper for perform_commit that uses a lock to prevent concurrent runs
perform_commit() {
  if [ "$USE_FLOCK" -eq 0 ]; then
    _perform_commit # Run without lock
    local nocommit_status=$?
    if [ $nocommit_status -ne 0 ]; then
      stderr "Commit logic failed with status $nocommit_status."
    fi
    return $nocommit_status
  fi

  # Try to acquire a non-blocking lock on file descriptor 8 using COMMIT_LOCKFILE.
  (
    # Open FD 8 for the subshell, associating it with the lock file
    exec 8>"$COMMIT_LOCKFILE"
    "$FLOCK" -n 8 || {
      verbose_echo "Commit already in progress (commit lock busy), skipping this trigger."
      exit 0 # Exit subshell gracefully
    }
    verbose_echo "Acquired commit lock (FD 8) on $COMMIT_LOCKFILE, running commit logic."
    _perform_commit
    # Lock on FD 8 is released automatically when this subshell exits
  )
  local commit_status=$?
  if [ $commit_status -ne 0 ]; then
    stderr "Commit logic failed with status $commit_status."
    # Option: Exit the main script upon commit failure
    # exit 1
  fi
  return $commit_status
}

# ... (end of perform_commit function) ...

###############################################################################

# If -f is specified, perform an initial commit before starting to watch
if [ "$COMMIT_ON_START" -eq 1 ]; then
  verbose_echo "Performing initial commit check..."
  perform_commit
fi

# --- Debounce Timer PID File ---
# Using a file to store the PID of the *active* timer subshell
# Use sha256sum for uniqueness if available
if is_command "sha256sum"; then
  TIMER_PID_FILE="${TMPDIR:-/tmp}/gitwatch_timer_$(echo -n "$GIT_DIR_PATH" | sha256sum | awk '{print $1}').pid"
elif is_command "md5sum"; then
  TIMER_PID_FILE="${TMPDIR:-/tmp}/gitwatch_timer_$(echo -n "$GIT_DIR_PATH" | md5sum | awk '{print $1}').pid"
else
  # Fallback if no hash command found
  TIMER_PID_FILE="${TMPDIR:-/tmp}/gitwatch_timer_${GIT_DIR_PATH//\//_}.pid"
fi

# Cleanup PID file on exit
# Redefine trap to include PID file removal
trap 'rm -f "$TIMER_PID_FILE"; cleanup' EXIT INT TERM


# main program loop: wait for changes and commit them
verbose_echo "Starting file watch. Command: ${INW} ${INW_ARGS[*]}"
# Execute the watcher and pipe its output to the read loop
"${INW}" "${INW_ARGS[@]}" | while IFS= read -r line; do # Use IFS= to preserve leading spaces
  if [ -z "$line" ]; then
    verbose_echo "Received empty line from watcher, possibly pipe closed?"
    continue
  fi
  verbose_echo "Change detected: $line"

  # Drain any other events that are already in the pipe buffer.
  while IFS= read -t "$READ_TIMEOUT" -r drain_line; do
    [ -z "$drain_line" ] && break # Timeout means buffer is clear
    verbose_echo "Draining event: $drain_line"
  done

  # --- DEBOUNCE LOGIC REVISION 3 ---
  # Read the PID from the file if it exists
  OLD_TIMER_PID=""
  if [ -f "$TIMER_PID_FILE" ]; then
    OLD_TIMER_PID=$(cat "$TIMER_PID_FILE")
    # **Crucially, clear the PID file *before* killing**
    # This acts as an immediate signal to any waking timer that it's stale.
    rm -f "$TIMER_PID_FILE"
    verbose_echo "Debounce: Cleared PID file (was for PID $OLD_TIMER_PID)."
  fi

  # Check if that old process is still running and kill it forcefully
  if [[ -n "$OLD_TIMER_PID" ]] && kill -0 "$OLD_TIMER_PID" &>/dev/null; then
    verbose_echo "Debounce: Timer (PID $OLD_TIMER_PID) is active. Killing it forcefully (SIGKILL)."
    # Kill children first, then parent, using SIGKILL
    pkill -9 -P "$OLD_TIMER_PID" &>/dev/null || true
    kill -9 "$OLD_TIMER_PID" &>/dev/null || true
    # Give a tiny moment for the OS to process the kill
    sleep 0.05
  fi

  # Start the new timer in the background
  (
    # Subshell: Store own PID immediately
    MY_PID=$$
    echo "$MY_PID" > "$TIMER_PID_FILE"
    verbose_echo "Debounce Timer (PID $MY_PID): Started. PID stored."

    # Sleep
    sleep "$SLEEP_TIME"

    # **IMPROVED SAFEGUARD:** Check PID file *immediately* after sleep.
    # If the file is gone or contains a different PID, exit silently *before* printing/committing.
    if ! [ -f "$TIMER_PID_FILE" ] || [ "$(cat "$TIMER_PID_FILE")" != "$MY_PID" ]; then
      verbose_echo "Debounce Timer (PID $MY_PID): Stale timer detected immediately after sleep. Exiting silently."
      exit 0 # Exit subshell gracefully and silently
    fi

    # If we got here, we are the active timer. Proceed.
    verbose_echo "Debounce Timer (PID $MY_PID): Sleep finished. PID still valid. Attempting commit."
    perform_commit
    # Remove the PID file *after* finishing commit attempt
    # (Conditional rm -f is safe even if already removed)
    if [ -f "$TIMER_PID_FILE" ] && [ "$(cat "$TIMER_PID_FILE")" = "$MY_PID" ]; then
      rm -f "$TIMER_PID_FILE"
      verbose_echo "Debounce Timer (PID $MY_PID): Commit attempt finished. PID file removed."
    else
      verbose_echo "Debounce Timer (PID $MY_PID): Commit attempt finished. PID file was already removed or changed."
    fi
  ) &
  # --- END DEBOUNCE LOGIC REVISION 3 ---

done

verbose_echo "File watcher process ended (or failed). Exiting via loop termination."
# Ensure PID file is removed if loop terminates unexpectedly
rm -f "$TIMER_PID_FILE"
exit 0 # Explicit exit to ensure cleanup trap runs

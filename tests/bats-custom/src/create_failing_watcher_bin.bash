#!/usr/bin/env bash

# create_failing_watcher_bin: Creates a dummy script that mimics the watcher binary
#                             (inotifywait or fswatch) but immediately exits with an error code.
#
# Usage: create_failing_watcher_bin <name> <exit_code>
#
# Arguments:
#   name: The name of the binary (e.g., inotifywait)
#   exit_code: The exit code the binary should return (e.g., 5)
#
# Returns:
#   The absolute path to the created dummy binary (to stdout).
create_failing_watcher_bin() {
  local name="$1"
  local exit_code="$2"
  # shellcheck disable=SC2154 # testdir is a global var sourced from BATS
  local dummy_path="$testdir/bin/$name"

  # Ensure the directory exists
  # shellcheck disable=SC2154 # testdir is a global var sourced from BATS
  mkdir -p "$testdir/bin"

  echo "#!/usr/bin/env bash" > "$dummy_path"
  echo "echo \"*** DUMMY WATCHER: $name failed with code $exit_code ***\" >&2" >> "$dummy_path"
  echo "exit $exit_code" >> "$dummy_path"
  chmod +x "$dummy_path"
  echo "$dummy_path"
}

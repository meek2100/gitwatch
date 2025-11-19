#!/usr/bin/env bash

# write_mock_git_parser: Outputs the standard argument parsing logic for mock git scripts.
#
# Usage:
#   write_mock_git_parser >> "$dummy_script_path"
#
write_mock_git_parser() {
  cat << 'EOF'
# --- Standard Mock Git Argument Parser ---
# gitwatch.sh prepends flags (like -c core.quotepath=false) to $GW_GIT_BIN.
# We must skip these flags to find the actual subcommand (commit, push, etc.).

args=("$@")
idx=0
while [[ "${args[$idx]}" == -* ]]; do
  if [[ "${args[$idx]}" == "-c" ]]; then
    ((idx+=2)) # Skip flag and value
  else
    ((idx+=1)) # Skip flag
  fi
done
subcommand="${args[$idx]}"
# -----------------------------------------
EOF
}

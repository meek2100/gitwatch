#!/usr/bin/env bash

# ---
# Helper to generate a unique hash for a path
# This is copied from gitwatch.sh to be used in lockfile tests
# Depends on: is_command()
# ---
_get_path_hash() {
  local path_to_hash="$1"
  local path_hash=""

  if is_command "sha256sum"; then
    path_hash=$(echo -n "$path_to_hash" | sha256sum | (read -r hash _; echo "$hash"))
  elif is_command "md5sum"; then
    path_hash=$(echo -n "$path_to_hash" | md5sum | (read -r hash _; echo "$hash"))
  else
    # Simple "hash" for POSIX compliance, replaces / with _
    # Truncate to last 200 chars to avoid filesystem length limits on deep paths
    local safe_string="${path_to_hash//\//_}"
    path_hash="${safe_string: -200}"
  fi
  echo "$path_hash"
}

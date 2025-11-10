#!/usr/bin/env bash

# ==============================================================================
# BATS Test Suite Configuration
# ==============================================================================
# This file centralizes all global settings for the BATS test suite.
# ==============================================================================

# ---
# 1. Global Test Arguments
# ---
# -o DEBUG: Run in verbose debug mode by default.
# -t 10:    Set a global 10-second timeout (default is 60).
#
declare -a default_args=("-o" "DEBUG" "-t" "10")

# --- WARNING for override ---
# Check if the user-set variable is different from the default string representation
if [ -n "${GITWATCH_TEST_ARGS:-}" ] && [ "${GITWATCH_TEST_ARGS}" != "${default_args[*]}" ];
then
  echo "############################################################" >&3
  echo "# BATS WARNING: Global Test Arguments Overridden!" >&3
  echo "# Default args: (${default_args[*]})" >&3
  echo "# Current args: (${GITWATCH_TEST_ARGS})" >&3
  echo "# See tests/bats-custom/config.bash to reset." >&3
  echo "############################################################" >&3
fi
# --- END WARNING ---

export GITWATCH_TEST_ARGS="${GITWATCH_TEST_ARGS:-${default_args[*]}}"

# --- Create a BASH array for safe, quoted expansion in tests ---
# Use `read -r -a` to robustly parse the string into an array.
#
# shellcheck disable=SC2034 # This array is used externally by all .bats test files.
declare -a GITWATCH_TEST_ARGS_ARRAY
read -r -a GITWATCH_TEST_ARGS_ARRAY <<< "$GITWATCH_TEST_ARGS"

# ---
# 2. Global Test Wait Time
# ---
# Standard time (in seconds) to wait for gitwatch to respond.
#
# shellcheck disable=SC2034 # Used externally by .bats test files
WAITTIME=4

# ==============================================================================
# Debug Overrides
# ==============================================================================

# ---
# 3. Shell Debug Mode (set -x)
# ---
if [ -n "${BATS_SET_OPTIONS:-}" ];
then
  # --- WARNING ---
  echo "############################################################" >&3
  echo "# BATS WARNING: Shell Debug Mode Active!" >&3
  echo "# BATS_SET_OPTIONS=\"${BATS_SET_OPTIONS}\" is set." >&3
  echo "# See tests/bats-custom/config.bash to disable." >&3
  echo "############################################################" >&3
  # --- END WARNING ---
  # shellcheck disable=SC2086 # We explicitly WANT word splitting here
  set ${BATS_SET_OPTIONS}
fi

# ---
# 4. "Quick Test" Mode (Skip Slow Tests)
# ---
export BATS_QUICK_TEST="${BATS_QUICK_TEST:-false}"
if [ "${BATS_QUICK_TEST}" = "true" ];
then
  # --- WARNING ---
  echo "############################################################" >&3
  echo "# BATS WARNING: Quick Test Mode Active!" >&3
  echo "# BATS_QUICK_TEST=\"true\" is set. Slow tests will be SKIPPED." >&3
  echo "# See tests/bats-custom/config.bash to disable." >&3
  echo "############################################################" >&3
  # --- END WARNING ---
fi

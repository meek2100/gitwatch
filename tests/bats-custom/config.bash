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
  # Use verbose_echo (loaded first in load.bash)
  verbose_echo "############################################################"
  verbose_echo "# BATS WARNING: Global Test Arguments Overridden!"
  verbose_echo "# Default args: (${default_args[*]})"
  verbose_echo "# Current args: (${GITWATCH_TEST_ARGS})"
  verbose_echo "# See tests/bats-custom/config.bash to reset."
  verbose_echo "############################################################"
fi
# --- END WARNING ---

export GITWATCH_TEST_ARGS="${GITWATCH_TEST_ARGS:-${default_args[*]}}"

# --- Create a BASH array for safe, quoted expansion in tests ---
# Use `read -r -a` to robustly parse the string into an array.
#
# shellcheck disable=SC2034
declare -a GITWATCH_TEST_ARGS_ARRAY
# shellcheck disable=SC2034
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
  verbose_echo "############################################################"
  verbose_echo "# BATS WARNING: Shell Debug Mode Active!"
  verbose_echo "# BATS_SET_OPTIONS=\"${BATS_SET_OPTIONS}\" is set."
  verbose_echo "# See tests/bats-custom/config.bash to disable."
  verbose_echo "############################################################"
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
  verbose_echo "############################################################"
  verbose_echo "# BATS WARNING: Quick Test Mode Active!"
  verbose_echo "# BATS_QUICK_TEST=\"true\" is set. Slow tests will be SKIPPED."
  verbose_echo "# See tests/bats-custom/config.bash to disable."
  verbose_echo "############################################################"
  # --- END WARNING ---
fi

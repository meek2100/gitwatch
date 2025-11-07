#!/usr/bin/env bash

# ==============================================================================
# BATS Test Suite Configuration
# ==============================================================================
# This file centralizes all global settings for the BATS test suite.
# It is loaded by `startup-shutdown.bash` and `custom-helpers.bash`.
#
# Use the environment variables below to control test behavior for debugging.
# ==============================================================================


# ==============================================================================
# Standard Configuration
# (Most common settings)
# ==============================================================================

# ---
# 1. Global Test Arguments
# ---
# These are the *default* arguments passed to every gitwatch.sh call
# in the test suite.
#
# -o DEBUG: Run in verbose debug mode by default (replaces old -v).
# -t 10:    Set a global 10-second timeout (default is 60).
#
# You can override this from the command line for a single run, e.g.:
# export GITWATCH_TEST_ARGS="-o WARN" # Run tests at WARN level
# make test
#
declare -a default_args=("-o" "DEBUG" "-t" "10")

# --- WARNING for override ---
# Check if the user-set variable is different from the default string representation
if [ -n "${GITWATCH_TEST_ARGS:-}" ] && [ "${GITWATCH_TEST_ARGS[*]}" != "${default_args[*]}" ];
then
  echo "############################################################" >&3
  echo "# BATS WARNING: Global Test Arguments Overridden!" >&3
  echo "# Default args: (${default_args[*]})" >&3
  echo "# Current args: (${GITWATCH_TEST_ARGS[*]})" >&3
  echo "# See tests/bats-custom/bats-config.bash to reset." >&3
  echo "############################################################" >&3
fi
# --- END WARNING ---

export GITWATCH_TEST_ARGS="${GITWATCH_TEST_ARGS:-${default_args[@]}}"

# --- FIX: Create a BASH array for safe, quoted expansion in tests ---
# This new array is used by tests as "${GITWATCH_TEST_ARGS_ARRAY[@]}"
# to satisfy shellcheck SC2086 and fix word-splitting issues.
# shellcheck disable=SC2034,SC2206
declare -a GITWATCH_TEST_ARGS_ARRAY=(${GITWATCH_TEST_ARGS})
# --- END FIX ---


# ---
# 2. Global Test Wait Time
# ---
# Standard time (in seconds) to wait for gitwatch to respond.
# Used in tests that check if something *didn't* happen.
# (e.g., "touch a file, wait 4s, check that no commit was made")
#
# shellcheck disable=SC2034 # Used by tests
WAITTIME=4


# ==============================================================================
# Debug Overrides
# (Least common settings, for advanced debugging)
# ==============================================================================

# ---
# 3. Shell Debug Mode (set -x)
# ---

## 1. How to Use
# In your terminal, run:
# export BATS_SET_OPTIONS="-x"
# make test
#
# Or, for strict mode (stops on any error):
# export BATS_SET_OPTIONS="-euo pipefail -x"
# make test
#
## 2. What it Does
# Passes your options directly to the 'set' command in every test file.
# This is most commonly used to enable 'set -x' (command tracing).
#
## 3. When to Use / Safety
# This is for **local debugging only**.
# It creates a massive amount of
# log output and may change test behavior (e.g., 'set -u' could
# cause a test to fail that would normally pass).
#
## 4. Local Override Example
# For a quick test, uncomment the line below:
# export BATS_SET_OPTIONS="-x"
#
if [ -n "${BATS_SET_OPTIONS:-}" ];
then
  # --- WARNING ---
  echo "############################################################" >&3
  echo "# BATS WARNING: Shell Debug Mode Active!" >&3
  echo "# BATS_SET_OPTIONS=\"${BATS_SET_OPTIONS}\" is set." >&3
  echo "# See tests/bats-custom/bats-config.bash to disable." >&3
  echo "############################################################" >&3
  # --- END WARNING ---
  # shellcheck disable=SC2086 # We explicitly WANT word splitting here
  set ${BATS_SET_OPTIONS}
fi


# ---
# 4. "Quick Test" Mode (Skip Slow Tests)
# ---

## 1. How to Use
# In your terminal, run:
# export BATS_QUICK_TEST="true"
# make test
#
## 2. What it Does
# This flag tells any test file *known to be slow* to skip itself.
# This is perfect for when you are debugging a fast test (like a
# flag parser) and don't want to wait for slow rebase/timeout tests.
#
# (This requires the slow .bats files to have a setup() function
# that checks for this variable).
#
## 3. When to Use / Safety
# Use this locally to speed up your develop/test loop.
# **Never use this in CI**, as it will cause your test suite to
# report "success" while having skipped critical tests.
#
## 4. Local Override Example
# For a quick test, uncomment the line below:
# export BATS_QUICK_TEST="true"
#
export BATS_QUICK_TEST="${BATS_QUICK_TEST:-false}"
if [ "${BATS_QUICK_TEST}" = "true" ];
then
  # --- WARNING ---
  echo "############################################################" >&3
  echo "# BATS WARNING: Quick Test Mode Active!" >&3
  echo "# BATS_QUICK_TEST=\"true\" is set. Slow tests will be SKIPPED." >&3
  echo "# See tests/bats-custom/bats-config.bash to disable." >&3
  echo "############################################################" >&3
  # --- END WARNING ---
fi


# ---
# 5. Dependency Mocking (REMOVED)
# ---
# This feature (BATS_MOCK_DEPENDENCIES) has been removed.
# Please use manual PATH manipulation within your test file,
# as seen in 'tests/dependency-failure.bats', for a more
# reliable and self-contained test.
#
if [ -n "${BATS_MOCK_DEPENDENCIES:-}" ];
then
  # --- WARNING ---
  echo "############################################################" >&3
  echo "# BATS ERROR: BATS_MOCK_DEPENDENCIES is set but obsolete." >&3
  echo "# This feature has been removed. Please update your test" >&3
  echo "# to use manual PATH mocking (see dependency-failure.bats)." >&3
  echo "############################################################" >&3
  exit 1
fi

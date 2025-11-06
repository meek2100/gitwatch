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
# -v: Run in verbose mode by default.
# -t 10: Set a global 10-second timeout (default is 60).
#
# You can override this from the command line for a single run, e.g.:
# export GITWATCH_TEST_ARGS="-q" # Run tests in quiet mode
# make test
#
declare -a default_args=("-v" "-t" "10")

# --- WARNING for override ---
# Check if the user-set variable is different from the default string representation
if [ -n "${GITWATCH_TEST_ARGS:-}" ] && [ "${GITWATCH_TEST_ARGS[*]}" != "${default_args[*]}" ]; then
  echo "############################################################" >&3
  echo "# BATS WARNING: Global Test Arguments Overridden!" >&3
  echo "# Default args: (${default_args[*]})" >&3
  echo "# Current args: (${GITWATCH_TEST_ARGS[*]})" >&3
  echo "# See tests/bats-custom/bats-config.bash to reset." >&3
  echo "############################################################" >&3
fi
# --- END WARNING ---

export GITWATCH_TEST_ARGS="${GITWATCH_TEST_ARGS:-${default_args[@]}}"


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

BATS_SET_OPTIONS="-x"

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
# This is for **local debugging only**. It creates a massive amount of
# log output and may change test behavior (e.g., 'set -u' could
# cause a test to fail that would normally pass).
#
## 4. Local Override Example
# For a quick test, uncomment the line below:
# export BATS_SET_OPTIONS="-x"
#
if [ -n "${BATS_SET_OPTIONS:-}" ]; then
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
if [ "${BATS_QUICK_TEST}" = "true" ]; then
  # --- WARNING ---
  echo "############################################################" >&3
  echo "# BATS WARNING: Quick Test Mode Active!" >&3
  echo "# BATS_QUICK_TEST=\"true\" is set. Slow tests will be SKIPPED." >&3
  echo "# See tests/bats-custom/bats-config.bash to disable." >&3
  echo "############################################################" >&3
  # --- END WARNING ---
fi


# ---
# 5. Dependency Mocking (Simulate Failures)
# ---

## 1. How to Use
# In your terminal, set a comma-separated list of commands to "uninstall":
#
# # Simulate 'flock' being missing
# export BATS_MOCK_DEPENDENCIES="flock"
# make test
#
# # Simulate 'flock' AND 'git' being missing
# export BATS_MOCK_DEPENDENCIES="flock,git"
# make test
#
## 2. What it Does
# This script creates a *temporary dummy folder* with fake, failing
# scripts (e.g., a fake 'flock' that just 'exit 127').
# It then prepends this folder to your $PATH for the test run.
#
# This forces gitwatch.sh to believe the commands are missing,
# allowing you to test your script's error-handling and dependency
# check logic without *actually* uninstalling anything.
#
## 3. When to Use / Safety
# Use this **only** for testing the `dependency-failure.bats` test
# or for debugging how your script handles a missing command.
#
# **This will cause most of your tests to fail**, as they
# can no longer call the real 'git' or 'flock'. This is expected.
#
## 4. Local Override Example
# To test the 'flock' dependency check, uncomment the line below:
# export BATS_MOCK_DEPENDENCIES="flock"
#
export BATS_MOCK_DEPENDENCIES="${BATS_MOCK_DEPENDENCIES:-}"

if [ -n "$BATS_MOCK_DEPENDENCIES" ]; then
  # --- WARNING ---
  echo "############################################################" >&3
  echo "# BATS WARNING: Dependency Mocking Active!" >&3
  echo "# BATS_MOCK_DEPENDENCIES=\"${BATS_MOCK_DEPENDENCIES}\" is set." >&3
  echo "# Most tests will FAIL as commands are missing." >&3
  echo "# See tests/bats-custom/bats-config.bash to disable." >&3
  echo "############################################################" >&3
  # --- END WARNING ---

  # 1. Create a new dummy bin directory for this test run
  export BATS_DUMMY_BIN_DIR
  BATS_DUMMY_BIN_DIR=$(mktemp -d)

  # 2. Add it to the front of the PATH
  export PATH="$BATS_DUMMY_BIN_DIR:$PATH"

  echo "# BATS CONFIG: Mocks installed at: $BATS_DUMMY_BIN_DIR" >&3

  # 3. Create mock commands
  # Use tr to split the comma-separated list
  for cmd in $(echo "$BATS_MOCK_DEPENDENCIES" | tr ',' ' '); do
    echo "#!/usr/bin/env bash" > "$BATS_DUMMY_BIN_DIR/$cmd"
    echo "echo \"*** MOCK ERROR: '$cmd' is not installed (simulated by BATS_MOCK_DEPENDENCIES) ***\" >&2" >> "$BATS_DUMMY_BIN_DIR/$cmd"
    echo "exit 127" >> "$BATS_DUMMY_BIN_DIR/$cmd"
    chmod +x "$BATS_DUMMY_BIN_DIR/$cmd"
  done
fi

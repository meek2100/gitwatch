#!/usr/bin/env bash
# shellcheck disable=SC1091

# This file is the single entry point for all custom BATS logic
# for the gitwatch test suite, modeled after the bats-assert/load.bash
# convention.

# Get the directory of this file (robustly)
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# 1. Load foundational helpers
source "$DIR/src/verbose_echo.bash"
source "$DIR/src/is_command.bash"

# 2. Load configuration (sets global variables)
source "$DIR/config.bash"

# 3. Load all other helper functions
source "$DIR/src/_get_path_hash.bash"
source "$DIR/src/wait_for_git_change.bash"
source "$DIR/src/wait_for_process_to_die.bash"
source "$DIR/src/create_failing_watcher_bin.bash"
source "$DIR/src/write_mock_git_parser.bash"

# 4. Load the setup/teardown logic
source "$DIR/src/common_setup.bash"
source "$DIR/src/setup.bash"
source "$DIR/src/teardown.bash"

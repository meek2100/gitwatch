#!/usr/bin/env bash
# shellcheck disable=1090

# This file is the single entry point for all custom BATS logic
# for the gitwatch test suite, modeled after the bats-assert/load.bash
# convention.

# 1. Load foundational helpers
source "$(dirname "${BASH_SOURCE[0]}")/src/verbose_echo.bash"
source "$(dirname "${BASH_SOURCE[0]}")/src/is_command.bash"

# 2. Load configuration (sets global variables)
source "$(dirname "${BASH_SOURCE[0]}")/config.bash"

# 3. Load all other helper functions
source "$(dirname "${BASH_SOURCE[0]}")/src/_get_path_hash.bash"
source "$(dirname "${BASH_SOURCE[0]}")/src/wait_for_git_change.bash"
source "$(dirname "${BASH_SOURCE[0]}")/src/wait_for_process_to_die.bash"
source "$(dirname "${BASH_SOURCE[0]}")/src/create_failing_watcher_bin.bash"

# 4. Load the setup/teardown logic
source "$(dirname "${BASH_SOURCE[0]}")/src/common_setup.bash"
source "$(dirname "${BASH_SOURCE[0]}")/src/setup.bash"
source "$(dirname "${BASH_SOURCE[0]}")/src/teardown.bash"

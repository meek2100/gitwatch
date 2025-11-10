#!/usr/bin/env bash

# This file loads the gitwatch custom test suite.
# It is modeled after the bats-assert/load.bash convention.

# 1. Load configuration (sets global variables)
source "$(dirname "${BASH_SOURCE[0]}")/config.bash"

# 2. Source all helper functions
source "$(dirname "${BASH_SOURCE[0]}")/verbose_echo.bash"
source "$(dirname "${BASH_SOURCE[0]}")/src/wait_for_git_change.bash"
source "$(dirname "${BASH_SOURCE[0]}")/src/wait_for_process_to_die.bash"
source "$(dirname "${BASH_SOURCE[0]}")/src/create_failing_watcher_bin.bash"
source "$(dirname "${BASH_SOURCE[0]}")/src/is_command.bash"
source "$(dirname "${BASH_SOURCE[0]}")/_get_path_hash.bash"

# 3. Source the setup/teardown logic
# Source common private helpers first
source "$(dirname "${BASH_SOURCE[0]}")/src/common_setup.bash"
# Source the public setup hooks
source "$(dirname "${BASH_SOURCE[0]}")/src/setup.bash"
# Source the public teardown hooks
source "$(dirname "${BASH_SOURCE[0]}")/src/teardown.bash"

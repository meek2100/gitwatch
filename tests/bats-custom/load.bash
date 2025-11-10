#!/usr/bin/env bash

# This file is the single entry point for all custom BATS logic
# for the gitwatch test suite.

# Use 'load' as it's the idempotent BATS-blessed way to do this.

# 1. Load configuration variables first.
load 'bats-custom/bats-config'

# 2. Load helper functions next.
load 'bats-custom/custom-helpers'

# 3. Load the setup/teardown hooks last.
load 'bats-custom/startup-shutdown'

#!/usr/bin/env bash

# This file defines the public-facing `teardown` hook functions
# that BATS test files will call.
#
# Depends on:
#   - _common_teardown()
#   - verbose_echo()

teardown()
{
  _common_teardown
}

teardown_for_remotedirs() {
  verbose_echo "# Running custom cleanup for remotedirs"
  _common_teardown
}

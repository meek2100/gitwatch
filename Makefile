# Makefile for gitwatch development

# Use .PHONY to declare targets that are not files
.PHONY: all test lint install-hooks clean

# Default target
all: test

# Determine OS-portable core count for parallel jobs
# Default to 1 if detection fails
NPROC ?= $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)

# Run the BATS test suite
# We set BATS_LIB_PATH to include our custom helpers and the standard ones.
# This command mimics the CI workflow for fast, parallel execution.
test:
	@echo "Running BATS test suite in parallel on $(NPROC) cores..."
	@BATS_LIB_PATH="./tests" find tests -name "*.bats" -print0 | xargs -0 -n1 -P "$(NPROC)" bats --tap

# Run all pre-commit hooks against all files
lint:
	@echo "Running linters and formatters..."
	pre-commit run --all-files

# Install the pre-commit git hooks
install-hooks:
	@echo "Installing pre-commit hooks..."
	pre-commit install

# Clean up build/test artifacts
clean:
	@echo "Cleaning up..."
	rm -rf result result-*
	find . -name "*.tmp" -delete
	find . -name "*.XXXXX" -delete

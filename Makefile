# Makefile for gitwatch development

# Use .PHONY to declare targets that are not files
.PHONY: all test lint install-hooks clean

# Default target
all: test

# Run the BATS test suite
# We set BATS_LIB_PATH to include our custom helpers and the standard ones.
# This command is based on your CI workflow.
test:
	@echo "Running BATS test suite..."
	@BATS_LIB_PATH="./tests" bats tests/

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

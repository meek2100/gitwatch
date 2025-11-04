# Makefile for gitwatch development

# Use .PHONY to declare targets that are not files
.PHONY: all test lint install uninstall install-hooks clean build-windows-installer

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
	@BATS_LIB_PATH="./tests" find tests -name "*.bats" -print0 | \
	xargs -0 -n1 -P "$(NPROC)" bats --tap

# Run all pre-commit hooks against all files
lint:
	@echo "Running linters and formatters..."
	pre-commit run --all-files

# --- Installation Targets ---
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

install:
	@echo "Installing gitwatch.sh to $(BINDIR)/gitwatch..."
	@install -D -m 755 gitwatch.sh $(BINDIR)/gitwatch

uninstall:
	@echo "Removing gitwatch from $(BINDIR)/gitwatch..."
	@rm -f $(BINDIR)/gitwatch
# --- End Installation Targets ---

# Install the pre-commit git hooks
install-hooks:
	@echo "Installing pre-commit hooks..."
	pre-commit install

# --- Windows Installer Build ---
build-windows-installer:
	@echo "Building Windows installer (gitwatch-setup.exe)..."
	@echo "Checking for PowerShell (pwsh) and PS2EXE module..."
	@if ! command -v pwsh &> /dev/null; then \
		echo "Error: 'pwsh' (PowerShell) not found in PATH."; \
		echo "Please install PowerShell (https://docs.microsoft.com/powershell/scripting/install/installing-powershell)."; \
		exit 1; \
	fi
	@pwsh -Command "if (-not (Get-Module -ListAvailable -Name PS2EXE)) { echo 'Error: PS2EXE module not found. Please run: pwsh -Command \"Install-Module -Name PS2EXE -Scope CurrentUser\"'; exit 1; }"

	@echo "Copying gitwatch.sh to examples/windows..."
	@cp gitwatch.sh examples/windows/gitwatch.sh

	@echo "Running PS2EXE..."
	@pwsh -Command "Import-Module PS2EXE; \
		ps2exe -inputFile 'examples/windows/install.ps1' -outputFile 'examples/windows/gitwatch-setup.exe' -title 'Gitwatch Installer' -noconsole -noOutput"

	@echo "Cleaning up..."
	@rm examples/windows/gitwatch.sh

	@echo "Build complete: examples/windows/gitwatch-setup.exe"

# Clean up build/test artifacts
clean:
	@echo "Cleaning up..."
	rm -rf result result-*
	find . -name "*.tmp" -delete
	find . -name "*.XXXXX" -delete

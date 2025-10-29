# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Note: This version represents a major internal refactor focused on robustness, portability, containerization, and production readiness, incorporating all changes **after** commit `5cdaeb49dc`._

### Added

- **New Options:**
  - `-f`: Commit any pending changes on startup before starting the watch loop.
  - `-S`: Log messages to syslog instead of stderr/stdout.
  - `-v`: Enable verbose output for debugging (also enables `set -x` if not using syslog).
  - `-V`/`--version`: Print version information (read from `VERSION` file or embedded placeholder) and exit.
- **Robustness & Reliability:**
  - Added `flock` support for process locking to prevent concurrent runs on the same repository. Includes fallback to `/tmp` if `.git` is not writable.
  - Implemented `git write-tree` vs `HEAD` tree hash comparison to prevent empty commits (e.g., from timestamp-only or permission changes). Includes `git reset --mixed` if no real changes are staged.
  - Added new PID-file-based debounce logic (Revision 3) to handle rapid file changes gracefully, replacing older `sleep` PID method.
  - Implemented graceful shutdown signal handling (`INT`, `TERM`) and automatic cleanup via `trap`.
  - Added explicit pre-run permission checks for the target directory and `.git` directory with user-friendly error messages (including Docker context awareness).
  - Added check for `user.name` and `user.email` Git config presence on startup.
- **Portability & Compatibility:**
  - Official macOS support using `fswatch` as an alternative to `inotifywait`. Checks for `fswatch` via `command -v`.
  - Improved POSIX compliance (e.g., using `command -v` instead of `hash`, POSIX-compliant parameter expansions).
  - Added support for specifying alternative binary paths via environment variables (`GW_GIT_BIN`, `GW_INW_BIN`, `GW_FLOCK_BIN`).
  - Uses `pwd -P` for path resolution, removing dependency on `readlink`/`greadlink`.
  - Added check for `sha256sum`/`md5sum` needed for unique lockfile names in `/tmp`.
- **Containerization:**
  - Created official `Dockerfile` using Alpine, a non-root user (`appuser`), pinned versions, and best practices.
  - Added `docker-compose.yaml` for easy configuration and deployment, including volume mounts for SSH keys and `.gitconfig`.
  - Created `entrypoint.sh` for flexible container startup configuration via environment variables (converting flags like `PULL_BEFORE_PUSH="true"` to `-R`).
  - Added multi-stage `HEALTHCHECK` to the Dockerfile verifying process and watcher liveness.
- **Development & Maintenance:**
  - Added comprehensive BATS testing suite (`tests/`) covering core features, options, edge cases (spaces in paths, debounce, rebase conflicts), and multi-platform CI execution (Linux & macOS). Includes test helpers.
  - Integrated extensive linting and formatting via `.pre-commit-config.yaml` (`shellcheck`, `mdformat`, `yamllint`, `codespell`, `beautysh`, `prettier`). Added configuration files for linters (`.yamllint.yaml`, `.markdownlint.yaml`, `biome.json`).
  - Updated NixOS support (`flake.nix`, `gitwatch.nix`, `module.nix`) for packaging and system module integration to work with refactored code.
  - Automated Docker release workflow (`.github/workflows/publish-docker.yaml`) via GitHub Actions triggered by Git tags (`v*`).
  - Automated Release Creation workflow (`.github/workflows/release.yaml`) to update version files, changelog, and create GitHub Releases on tag push.
  - Added `.editorconfig` for consistent editor settings.
  - Updated `package.json` for bpkg integration.

### Changed

- Refactored script structure significantly for clarity, maintainability, and error handling. Uses more functions (e.g., `_perform_commit`, `perform_commit`, `generate_commit_message`).
- Uses `printf` with `%q` for safer command construction, preventing shell injection issues.
- Improved argument parsing (`getopts`) and path resolution logic.
- Enhanced `diff-lines` function for better parsing of diff output, color code handling, and added safety checks.
- Made commit message generation more robust, handling cases where diff commands might fail.
- Updated `README.md` extensively with Docker instructions, installation methods (Nix, bpkg), macOS requirements, and clarified usage based on refactored options and behavior.
- Switched CI testing from deprecated `run-tests.yaml` to `gitwatch.yaml` using BATS directly.
- Version number is now read from `VERSION` file or substituted placeholder, not read directly by the script at runtime unless `VERSION` is present.

### Removed

- Dependency on `readlink` and `greadlink`.
- Old debounce logic based on killing `sleep` PIDs.
- `.github/workflows/run-tests.yaml.disabled` file.

### New Contributors (Since v0.5)

- @meek2100 (Darin Theurer) performed the major refactor.
  *(Note: List any other *new* contributors specifically to the v0.6 changes if applicable)*

## [0.5] - YYYY-MM-DD (Unreleased)

_Note: Incorporates changes between commit `5f925e1f` (v0.4) and `5cdaeb49dc`._

### Added

- NixOS Integration:
  - Added Nix Flake support (`flake.nix`).
  - Added NixOS module (`module.nix`) for systemd service configuration.
  - Added/Updated Nix package definition (`gitwatch.nix`).
- Added `package.json` for `bpkg` support.
- Added `com.github.gitwatch.plist` for macOS launchd service example.
- Added `.gitignore` file.
- Initial GitHub Actions workflow (`run-tests.yaml`, later disabled) for basic testing.

### Changed

- Updated `flake.lock`.
- Minor README updates related to NixOS.

### New Contributors (Since v0.4)

- @meek2100 (Darin Theurer) added NixOS, bpkg support, and initial CI setup.

**Full Changelog**: `v0.4...v0.5`

## [0.4] - 2025-08-19

_Ended at commit `5f925e1f`._

### Added

- **New Options:**
  - `-c <command>`: Generate commit message using the output of a custom shell command. Overrides `-m`, `-d`, `-l`/`-L`.
  - `-C`: Pipe the list of changed files (`git diff --staged --name-only`) via stdin to the custom commit command specified by `-c`.
- Integrated `pre-commit` framework for automated code quality checks (#132).

### Changed

- Improved commit message generation when using `-l`/`-L` to handle cases with no diff output better.
- Fixed `eval` usage potentially related to command execution safety (ShellCheck SC2294 mentioned).

### New Contributors

- @mdeweerd made their first contribution in #132 (Pre-commit setup).
- @Serrindipity made their first contribution in #134 (Custom commit command).

**Full Changelog**: `v0.3...v0.4`

## [0.3] - 2025-06-11

_Ended at commit `338430af`._

### Added

- **New Options:**
  - `-R`: Perform `git pull --rebase <remote>` before executing the push command (requires `-r`).

### Changed

- Updated README with note about NixOS package availability starting from 24.11 (#129).

### New Contributors

_(No new contributors identified between v0.2 and v0.3 based on commit history)_

**Full Changelog**: `v0.2...v0.3`

## [0.2] - 2023-12-12

_Ended at commit `45c629c4`._

### Added

- **New Options:**
  - `-x <pattern>`: Exclude files/directories matching the specified regex pattern from `inotifywait` monitoring (adds to default `.git` exclude).
  - `-M`: Prevent commits if a Git merge is detected (`.git/MERGE_HEAD` exists).

### Changed

- Improved handling of detached HEAD state when pushing with `-b`.

### New Contributors

_(No new contributors identified between v0.1 and v0.2 based on commit history)_

**Full Changelog**: `v0.1...v0.2`

## [0.1] - 2020-06-12

### Added

- Initial release.
- Core functionality: Watch a file or directory using `inotifywait` (Linux) or `fswatch` (macOS) and commit changes to Git.
- Basic debounce mechanism using `sleep` PID management.
- **Options:**
  - `-s <secs>`: Sleep time (debounce delay).
  - `-d <fmt>`: Date format for `%d` in commit message.
  - `-r <remote>`: Remote repository name to push to.
  - `-b <branch>`: Branch name to push to (handles detached HEAD and specifies target branch format like `current:target`).
  - `-g <path>`: Specify `--git-dir` and `--work-tree` for Git commands.
  - `-l <lines>`: Include diff lines (processed by `diff-lines`) in commit message (up to `<lines>` count, 0 for unlimited). Colored output.
  - `-L <lines>`: Same as `-l` but without color.
  - `-m <msg>`: Custom commit message template with `%d` placeholder for date.
  - `-e <events>`: Custom event list string for `inotifywait`.
- Basic macOS compatibility using `fswatch` and checks for `greadlink`.
- Environment variable support for alternative binary paths (`GW_GIT_BIN`, `GW_INW_BIN`, `GW_RL_BIN`).

### New Contributors

- Initial contributions primarily by @dmusican (Dave Musicant) and @Nevik (Patrick Lehner), with significant early contributions from @mmcg066 (Matthew McGowan), @DoGe (Dominik D. Geyer), and @philthompson (Phil Thompson) visible in commit history before this tag.

**Full Changelog**: `7a093282...v0.1` (Assuming first commit `7a093282` as base)

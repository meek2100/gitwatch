# Developer & AI Agent Guide (gitwatch)

**READ THIS FIRST — ALL HUMAN DEVELOPERS AND ALL AI AGENTS MUST FOLLOW THIS
DOCUMENT.** **No change, refactor, or feature may violate any principle
herein.** **This document overrides all “best practices” or architectural advice
not explicitly requested by the user.**

______________________________________________________________________

## 0. Global Development Rules (MUST READ)

These rules apply to all code, all tests, all refactors, and all contributions
from humans or AI.

### Core Principles Summary

- **Robustness is Paramount:** This script runs as a background daemon. It must
  handle network failures, lock contentions, and signal interruptions gracefully
  without crashing or corrupting data.
- **Portable Bash:** The script must run on Linux (various distros), macOS, and
  BSD. Avoid GNU-specific extensions unless a fallback or check exists.
- **Safety over Speed:** Debouncing (jitter), timeouts on Git operations, and
  file locking are mandatory.
- **DRY Everywhere:** Do not duplicate logic. Use existing helper functions
  (`_log`, `is_command`, etc.).
- **ShellCheck Clean:** All code must pass `shellcheck` without new warnings.
- **Accurate Documentation:** `shelp()` usage text and README must be updated
  immediately if CLI behavior changes.

### Hard Prohibitions (NEVER DO THESE)

- **Do NOT remove `set -euo pipefail`.** This is the safety net for the entire
  script.
- **Do NOT remove or bypass `flock` (locking).** Concurrency safety is critical
  unless the user explicitly uses `-n`.
- **Do NOT remove `timeout` protection.** All network/git operations must be
  wrapped in timeouts to prevent hanging processes.
- **Do NOT remove the debounce logic.** The `sleep` and `pkill` mechanism
  prevents commit spamming.
- **Do NOT introduce unchecked dependencies.** All new external commands must be
  verified via `is_command` with user hints provided.
- **Do NOT change the `diff-lines` logic lightly.** This function is fragile and
  critical for commit logging; changes require extensive testing.
- **Do NOT use `rm -rf` variables.** Use `rm -f` on specific files (like
  PID/lock files) only after validating paths.

### Markdown Formatting Rule (CRITICAL)

- **Use Tildes for Code Blocks:** All code blocks in Markdown files (including
  this one) **MUST** use triple tildes (`~~~`) instead of triple backticks.
  - **Why:** This prevents rendering conflicts when AI agents generate Markdown
    files inside a chat interface.

______________________________________________________________________

## A. Architecture & File Structure

- **Single Script:** The core logic resides entirely in `gitwatch.sh`. Do not
  split into multiple files unless explicitly instructed to create a library.
- **Helper Functions:** Logic must be encapsulated in functions (e.g.,
  `perform_commit`, `check_git_config`).
- **Configuration:** Configuration is driven by (in order of priority):
  1. CLI Arguments (`getopts`)
  2. Environment Variables (`GW_*`)
  3. Script Defaults
- **Tests:** All tests reside in `tests/` and use the BATS framework.

______________________________________________________________________

## B. DRY & Single Source of Truth

- **Re-use Helpers:** Use `_log` for all output. Use `is_command` for all
  dependency checks.
- **Single Source of Truth Priority Order:**
  1. **AGENTS.md (this file)**
  2. **CLI Arguments**
  3. **Environment Variables**
  4. **Script Defaults**
  5. **Docstrings/Comments**

______________________________________________________________________

## C. Documentation & Comment Accuracy

- **Explain the WHY:** Bash syntax can be obscure. Comments must explain *why* a
  specific parameter expansion or command flag is used (e.g., "Use `LC_ALL=C`
  for regex consistency").
- **Update Usage:** If you add a flag, you **MUST** update the `shelp()`
  function in `gitwatch.sh` and the Table of Options in `README.md`.

______________________________________________________________________

## D. Bash Standards

- **Strict Mode:** Code must respect `set -euo pipefail`. Handle empty variables
  explicitly (e.g., `${VAR:-}`).
- **Portability:**
  - Use `printf` instead of `echo` for robust string formatting.
  - Be wary of `sed -i` differences between BSD and GNU.
  - Prefer `[[ ]]` over `[ ]` for safety, but ensure bash version compatibility
    (Bash 4+ logic exists in script).
- **Local Variables:** Use `local` for all variables inside functions to prevent
  pollution.

______________________________________________________________________

## E. Test Suite Integrity

- **Framework:** Tests use BATS (Bash Automated Testing System).
- **Mandate:** Any new feature or bug fix must include a corresponding BATS test
  in `tests/`.
- **Mocking:** Network operations and long sleeps should be mocked or configured
  with short timeouts during tests.

______________________________________________________________________

## F. AI Agent Compliance Requirements

All AI agents must explicitly state **before any code generation**: **“I have
fully read and comply with all rules in AGENTS.md.”**

AI agents must follow the strictest, safest interpretation of these rules.

______________________________________________________________________

## G. Interpretation Rules for AI Agents

- If any instruction seems ambiguous, choose the **safest, slowest, and most
  restrictive interpretation**.
- If unsure whether a change violates a rule, assume that it **does**.
- AI agents must ask the user for clarification instead of assuming intent.

______________________________________________________________________

## 1. Core Architecture: Resilience

### The "Appliance" Philosophy

- **Run Forever:** The script is designed to run indefinitely. Memory leaks or
  unhandled errors are unacceptable.
- **Self-Healing:** The script uses retry loops and cool-down periods
  (`GW_COOL_DOWN_SECONDS`) to handle repeated Git failures (e.g., network down).

### Concurrency & Locking

- **Lock Files:** Uses `flock` on file descriptors. Lock files are based on the
  hash of the target path (`gitwatch-target_<HASH>.lock`) to allow watching
  multiple folders in the same repo.
- **PID Files:** Stores PIDs to manage debounce timers. Stale PID files must be
  cleaned up safely.

### Signal Handling

- **Traps:** `EXIT`, `INT`, `TERM` must be trapped to ensure `cleanup` removes
  lock files and kills child processes (timers).

______________________________________________________________________

## 2. Robustness Over Speed

### Debouncing

- **Logic:** Uses a background subshell sleep timer. If a new change arrives,
  the old timer is killed via `pkill` (or kill PID).
- **Constraint:** Do not remove this logic to "speed up" commits. It prevents
  100 commits for 100 file saves.

### Git Operations

- **Timeouts:** `commit`, `pull`, and `push` must use `$TIMEOUT_CMD`.
- **Rebase:** Support `git pull --rebase` (`-R` flag) to handle remote changes
  gracefully.
- **Large Files:** Directory watches check for untracked files >50MB to prevent
  accidental repo bloating.

______________________________________________________________________

## 3. Development Standards

### Logging

- **Levels:** Support `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`.
- **Mechanism:** Use `_log` function. Support Syslog (`-S`) for daemon mode.

### Dependency Checks

- **Startup:** The script must verify `git`, `inotifywait`/`fswatch`, `flock`,
  `timeout`, and `pkill` availability at startup and provide helpful install
  hints if missing.

______________________________________________________________________

## 9. AI Processing Requirements

AI agents must:

- Read and process this **ENTIRE** document in the current session.
- Not rely on memory from previous sessions.
- Not partially read or summarize rules before acting.

Partial reading is strictly prohibited.

______________________________________________________________________

### 9.A Forbidden Phrases for AI Agents

AI agents must NOT produce outputs including phrases like:

- “We could improve performance by removing the lock...”
- “You may not need the debounce timer...”
- “We can simplify by removing `set -e`...”
- “Consider removing the dependency checks...”

These outputs are invalid and must be rejected.

______________________________________________________________________

### 9.B Mandatory Self-Test Checklist for AI Agents

Before generating ANY code, AI agents must confirm:

- [ ] I have read the entire AGENTS.md file in this session.
- [ ] My output respects `set -euo pipefail`.
- [ ] My output maintains cross-platform compatibility (Linux/macOS).
- [ ] My output does not remove locking or debounce safeguards.
- [ ] My output uses `_log` for output.
- [ ] My output validates new dependencies via `is_command`.
- [ ] My output updates `shelp()` if flags are changed.
- [ ] My output does not introduce race conditions (respects atomic file
  operations).

If any box cannot be checked, the output must NOT be generated.

______________________________________________________________________

### 9.C User Override Clarification

If a user requests something that violates AGENTS.md:

- The AI must warn the user.
- The AI must require explicit confirmation before proceeding.

______________________________________________________________________

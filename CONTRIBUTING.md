# How to Contribute to gitwatch

We're excited to have your help! This guide will get you set up to code, test,
and commit.

## 1. Initial Setup

This project uses `pre-commit` to enforce linting and formatting and `bats` for
testing.

1. **Clone the repository:**

   ```sh
   git clone https://github.com/meek2100/gitwatch.git
   cd gitwatch
   ```

2. **Install Core Dependencies:** You will need the runtime dependencies for
   `gitwatch` itself, plus the development dependencies for testing and linting.

   - **macOS (using Homebrew):**

     ```sh
     # Runtime deps
     brew install fswatch flock coreutils proctools
     # Testing deps
     brew install bats-core bats-support bats-assert bats-file
     # Linting deps
     brew install pre-commit shellcheck
     ```

   - **Linux (using apt):**

     ```sh
     # Runtime deps
     sudo apt-get install inotify-tools util-linux coreutils procps
     # Testing deps
     sudo apt-get install bats
     # (Note: bats helpers may need manual install if not packaged)
     # Linting deps
     pip install pre-commit
     sudo apt-get install shellcheck
     ```

3. **Install Git Hooks:** This command reads the `.pre-commit-config.yaml` and
   installs git hooks. This ensures that all linters and formatters run _before_
   you can make a commit.

   ```sh
   pre-commit install
   ```

## 2. Development Workflow

1. **Make your changes:** Edit the code, add features, or fix bugs.

2. **Run the Tests:** Run the full BATS test suite to ensure your change didn't
   break anything. We've created a simple command for this:

   ```sh
   make test
   ```

3. **Add a Changelog Fragment:** If your change is user-facing (a new feature,
   bugfix, or performance improvement), add a small changelog "fragment" file.

   - Go to the `.changelog/` directory.
   - Create a file named `<issue-number>.<type>.md` (e.g., `123.added.md` or
     `456.fixed.md`).
   - Write a brief, past-tense description of your change, e.g., "Fixed an issue
     where the -R flag would fail with detached HEADs."
   - This will be automatically compiled into `CHANGELOG.md` on the next
     release.

4. **Commit your changes:** When you run `git commit`, the `pre-commit` hooks
   will automatically run, format your code, and check for linting errors. If it
   fails, fix the errors and run `git commit` again.

5. **Open a Pull Request:** Push your branch to GitHub and open a Pull Request
   against the `master` branch.

Thank you for contributing!

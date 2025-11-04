# How to Contribute to gitwatch

We're excited to have your help! This guide will get you set up to code,
test, and commit.

## 1. Initial Setup

This project uses `pre-commit` to enforce linting and formatting and `bats`
for testing.

1. **Clone the repository:**

   ```sh
   git clone [https://github.com/meek2100/gitwatch.git](https://github.com/meek2100/gitwatch.git)
   cd gitwatch
   ```

2. **Install Core Dependencies:** You will need the runtime dependencies
   for `gitwatch` itself, plus the development dependencies for testing and
   linting.

   - **macOS (using Homebrew):**

     ```sh
     # Runtime deps
     brew install fswatch flock coreutils
     # Testing deps
     brew install bats-core bats-support bats-assert bats-file
     # Linting deps
     brew install pre-commit shellcheck
     ```

   - **Linux (using apt):**

     ```sh
     # Runtime deps
     sudo apt-get install inotify-tools util-linux coreutils
     # Testing deps
     sudo apt-get install bats
     # (Note: bats helpers may need manual install if not packaged)
     # Linting deps
     pip install pre-commit
     sudo apt-get install shellcheck
     ```

3. **Install Git Hooks:** This command reads the `.pre-commit-config.yaml`
   and installs git hooks. This ensures that all linters and formatters run
   _before_ you can make a commit.

   ```sh
   pre-commit install
   ```

## 2. Development Workflow

1. **Make your changes:** Edit the code, add features, or fix bugs.

2. **Run the Tests:** Run the full BATS test suite to ensure your change
   didn't break anything. We've created a simple command for this:

   ```sh
   make test
   ```

3. **Commit your changes:** When you run `git commit`, the `pre-commit`
   hooks will automatically run, format your code, and check for linting
   errors. If it fails, fix the errors and run `git commit` again.

4. **Open a Pull Request:** Push your branch to GitHub and open a Pull
   Request against the `master` branch. The `CHANGELOG.md` will be updated
   automatically when your PR is merged.

Thank you for contributing!

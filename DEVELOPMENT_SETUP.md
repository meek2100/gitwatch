# Gitwatch Development Setup Guide

This guide expands on the setup in `CONTRIBUTING.md` by providing instructions for configuring external tools and non-VS Code editors to maintain code quality.

## 1. Local Tool Configuration Files

The repository defines project-specific formatting and linting rules in dedicated configuration files. These rules are applied consistently by both the automated `pre-commit` hooks and external editor plugins.

| File                                        | Tool                    | Purpose                                                                                  |
| :------------------------------------------ | :---------------------- | :--------------------------------------------------------------------------------------- |
| **.editorconfig**                           | EditorConfig            | Defines core settings: indent size (2 spaces), `lf` line endings, etc.                   |
| **.shellcheckrc**                           | Shellcheck              | Configures static analysis rules and global warnings to ignore (e.g., in Bats tests).    |
| **.beautyshrc**                             | Beautysh                | Defines the shell script formatting style (e.g., 2-space indentation, binary-next-line). |
| **.hadolint.yaml**                          | Hadolint                | Configures the linter for Dockerfiles, including rules to ignore.                        |
| **.yamllint.yaml** / **.markdownlint.yaml** | Yamllint / Markdownlint | Define rules for YAML and Markdown files.                                                |

## 2. Editor Integration (Beyond VS Code)

For editors other than VS Code, you should configure the editor's extensions to utilize the locally defined tools and configuration files.

### 2.1. Vim / NeoVim Setup

If you use Vim or NeoVim, installing a Language Server Protocol (LSP) client and a formatter plugin is the recommended path for seamless integration.

1. **Linter (`shellcheck`):**

   - Install a Language Server client (e.g., `coc.nvim`, `vim-lsp`, native LSP) configured to use a tool that calls `shellcheck` (such as `bash-language-server`).
   - Ensure your setup respects the project's local **`.shellcheckrc`** file.

2. **Formatter (`beautysh`):**
   - Install a formatter plugin (e.g., `Neoformat`, `ALE`, `vim-autoformat`).
   - Configure the plugin to use the command **`beautysh --config .beautyshrc -`** as the external command for formatting shell scripts (`filetype=sh` or `filetype=bash`).

### 2.2. General Editor Setup

For other editors (Sublime Text, Atom, JetBrains IDEs):

1. **Install Plugins:** Find and install the plugins that integrate with **Shellcheck** and **Beautysh** for your editor.
2. **Configuration:** Configure these plugins to reference the project's local configuration files:
   - **Shellcheck:** Point the plugin to the **`.shellcheckrc`** file in the project root.
   - **Beautysh:** Ensure the formatter uses the project settings defined in **`.beautyshrc`**.
3. **Final Check:** Always ensure the **pre-commit hook** (run via `pre-commit install`) is active. This hook acts as the final quality gate, guaranteeing all formatting and linting rules are passed before a commit is created.

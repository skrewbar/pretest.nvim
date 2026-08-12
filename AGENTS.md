# AGENTS.md — pretest.nvim

Guidance for AI agents working on this repository.

## Purpose

Neovim plugin for local competitive-programming pretest judging: load/save `.prob` files, compile/run solutions, show results in a sidebar or float UI.

## Module boundaries

| Module | Responsibility |
|--------|----------------|
| `lua/pretest/init.lua` | `setup()`, user command registration |
| `lua/pretest/config.lua` | defaults + merge user opts |
| `lua/pretest/commands.lua` | `:Pretest` subcommand dispatch + completion |
| `lua/pretest/prob.lua` | `.prob` path, load/save, TC CRUD |
| `lua/pretest/runner.lua` | compile, run, timeout, verdicts |
| `lua/pretest/ui.lua` | sidebar/float, navigation, editable Input/Expected |
| `lua/pretest/util.lua` | paths, md5, text normalize, notify |

Do not pull Competitive Companion, online submit, or custom checkers into v1 modules.

## `.prob` compatibility rules

- Independently implement read/write for the shared JSON schema. **Do not copy CPH (or any GPL) source.**
- Filename: `.{basename}.prob` next to the source; `.{basename}_{md5(absolute srcPath)}.prob` when `save_dir` is set (shared dir, collision risk).
- Artifact directory: optional `save_dir`; if unset, use the source file's directory. `.prob` and binaries share this directory (`util.artifact_dir`). Binary names follow the same hash rule.
- Preserve unknown JSON fields when saving when practical.
- Do not use CPH trademarks/logos in docs or UI strings. Saying "compatible with `.prob` files" is fine.

## UI editing constraints

- **Input** and **Expected** bodies are editable in their section buffers.
- Problem **timeLimit** / **memoryLimit** are edited via `:Pretest edit_limits` (prompts); header limits line, other header lines, Output, and Stderr are read-only.
- Persist Input/Expected on `:w`, before TC switch (`<C-n>`/`<C-p>`/header cursor), and before `run`. Limits persist immediately on confirm.
- Stderr section is shown only when non-empty.

## Coding conventions

- Lua targeting Neovim 0.10+ (`vim.system`, `vim.fs`, `vim.notify`).
- Prefer small pure helpers in `util.lua`.
- Keep async work on `vim.system` callbacks; schedule UI updates with `vim.schedule`.
- No new dependencies unless clearly justified.
- User-facing command is `:Pretest <subcommand>` (CompetiTest-style), not many top-level commands.

## Out of scope (v1)

- Competitive Companion receive
- Online submission
- Custom checkers / interactive problems
- Cloning CPH webview UI

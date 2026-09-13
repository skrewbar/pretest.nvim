**English** | [한국어](ko/competitive-companion.md)

# Competitive Companion

[Competitive Companion](https://github.com/jmerle/competitive-companion) is a browser extension that parses a problem page and sends its testcases, limits, and title to a local port.

You can use it to fill Input, Expected, and time/memory limits automatically instead of typing them yourself.

## Setup

Install the extension for [Chrome](https://chromewebstore.google.com/detail/competitive-companion/cjnmckjndlpiamhfimnnjmnckgghkjbl) or [Firefox](https://addons.mozilla.org/firefox/addon/competitive-companion/).

pretest listens on `127.0.0.1:27121` by default. That port is already in the extension's default port list, so no extra configuration is required. If you change `companion.port`, add the same port under "Custom ports" in the browser extension settings.

## Receiving

Start receiving with `:Pretest receive [mode]`, then click the extension's **+** button on a problem or contest page. Every mode except `persistently` stops after one delivery.

The received problem name and limits always overwrite the `.prob` file.

### `receive` — current file

Writes testcases, name, and limits into the current source file's `.prob` and opens the UI.

If the `.prob` already has testcases, they are replaced when `replace_testcases` is `true` (the default). When it is `false`, you choose **Keep** (append after the existing cases) / **Replace** / **Cancel**.

### `receive problem` — create a new file

Creates a source file at `problem_path` and writes a `.prob`. If `template` is set, the new file is filled from that template.

- `prompt_path = true` (default): confirm the path in a prompt. Leaving it empty or pressing `<Esc>` cancels.
- `open = true` (default): open the created file and the UI.
- If a file already exists at that path, you are asked whether to overwrite it.

### `receive contest` — whole contest

Clicking **+** on a contest page sends every problem as one batch. After the batch is complete, pretest creates a source file and `.prob` for each problem under `contest_dir`, using `contest_problem_path` as the file name.

`prompt_path` and `open` work the same as in `receive problem`. The directory is confirmed once, and only the first problem is opened.

### `receive persistently` — keep receiving

Keeps receiving until `:Pretest receive stop` or Neovim exits. Batches with more than one task are handled as `contest`. A single task prompts for **This file** (`receive`) / **Problem** (`receive problem`) / **Cancel**.

Set `companion.listen_on_setup = true` to start this mode automatically when `setup()` runs. With lazy.nvim, `lazy = false` is also required (see [Installation](installation.md#lazynvim)).

### Status and stop

```vim
:Pretest receive status
:Pretest receive stop
```

## Options

See [Configuration](configuration.md#defaults) for the default values.

| Option | Description |
|--------|-------------|
| `port` | TCP port on `127.0.0.1` |
| `listen_on_setup` | Start `receive persistently` from `setup()` |
| `extension` | Extension (without a dot) of files created by `problem` / `contest`. If it does not map to a configured language, the file and `.prob` are still created but the UI does not open |
| `template` | Path to a file used as the initial contents of new source files. Use `{ cpp = "~/cp/template.cpp", py = "~/cp/template.py" }` to set a different path per extension |
| `problem_path` | Path where `receive problem` creates the file |
| `contest_dir` | Directory where `receive contest` creates files. Evaluated with the first task of the batch |
| `contest_problem_path` | Path of each contest problem file. Relative to `contest_dir` and may include subdirectories |
| `prompt_path` | Confirm the path in a prompt before creating the file |
| `open` | Open the created file (the first file for contests) and the UI |
| `replace_testcases` | `true`: replace existing testcases. `false`: choose Keep / Replace / Cancel |

## Path templates

`problem_path`, `contest_dir`, and `contest_problem_path` accept `{placeholder}`s. Values are cleaned as follows:

- whitespace becomes `_`
- characters other than letters, digits, `_`, and `-` become `_`
- consecutive `_`s are collapsed

Given this task

```json
{ "name": "G. Castle Defense", "group": "Codeforces - Educational Round 170" }
```

the placeholders resolve to:

| Placeholder | Value | Description |
|-------------|-------|-------------|
| `{cwd}` | `/home/me/cf` | Neovim's cwd |
| `{home}` | `/home/me` | Home directory |
| `{index}` | `G` | Problem number in the title (`A`, `B1`, `1`, …). Empty if none |
| `{slug}` | `Castle_Defense` | Title without the problem number |
| `{problem}` | `G_Castle_Defense` | `{index}_{slug}`. `{slug}` when there is no problem number |
| `{file}` | `G` | `{index}`. `{slug}` when there is no problem number |
| `{name}` | `G_Castle_Defense` | The full title |
| `{task_class}` | `GCastleDefense` | Java class name suggested by the extension. `{name}` if none |
| `{judge}` | `Codeforces` | Part of `group` before ` - ` |
| `{contest}` | `Educational_Round_170` | Part of `group` after ` - `. `unknown_contest` if there is no ` - ` |
| `{group}` | `Codeforces_-_Educational_Round_170` | The whole `group` |
| `{ext}` | `cpp` | `companion.extension` |

The problem number is recognized when the title is `<number><separator><title>`, where the separator is `.`, `-`, or `:` (`G. Castle Defense`, `A - Welcome`, `1: Two Sum`).

Instead of a string you can supply `function(task, ext) -> string` and compute the path from the received task (`task.name`, `task.group`, `task.url`, `task.timeLimit`, …).

```lua
problem_path = function(task, ext)
  local judge = task.group:match("^(.-) %- ") or "misc"
  return vim.fs.joinpath(vim.fn.getcwd(), judge:lower(), task.name:sub(1, 1) .. "." .. ext)
end,
```

### Examples

One directory per contest, files named by problem number:

```lua
contest_dir = "{cwd}/{contest}",
contest_problem_path = "{file}.{ext}",
-- → ./Educational_Round_170/A.cpp, B.cpp, ...
```

Judge / contest / problem hierarchy:

```lua
problem_path = "{cwd}/{judge}/{contest}/{problem}.{ext}",
-- → ./Codeforces/Educational_Round_170/G_Castle_Defense.cpp
```

A Python template under a fixed directory:

```lua
extension = "py",
template = "~/cp/template.py",
problem_path = "{home}/cp/{judge}/{problem}.{ext}",
```

## Troubleshooting

**`cannot bind 127.0.0.1:27121 ...`**
Another process is using the port. Stop the other receiver, or change both `companion.port` and the extension's "Custom ports". Only one Neovim instance can receive at a time.

**Nothing happens when clicking +**
Check `:Pretest receive status`. The icon is red when the extension does not support the site.

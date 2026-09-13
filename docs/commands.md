**English** | [한국어](ko/commands.md)

# Commands

Every pretest action is available as `:Pretest <subcommand> [argument]`.

```vim
:Pretest toggle
:Pretest toggle_layout
:Pretest toggle_hints
:Pretest run [index ...]
:Pretest run_current
:Pretest run_no_compile [index ...]
:Pretest run_current_no_compile
:Pretest stop
:Pretest add
:Pretest edit [index]
:Pretest delete [index]
:Pretest edit_name
:Pretest edit_limits
:Pretest rename <name>
:Pretest move <path>
:Pretest receive [problem | contest | persistently | stop | status]
```

Commands that act on a problem (`run*`, `add`, `edit*`, `delete`, `rename`, `move`, `receive`) need a supported *source file*. Run them from a buffer whose filetype is configured under [`languages`](configuration.md#languages), or from a pretest UI window while a session is open.

## UI

| Command | Description |
|---------|-------------|
| `toggle` | Open the UI for the current source file, or close it if it is open. Opening focuses **Input**. |
| `toggle_layout` | Switch between `sidebar` and `float`. Works while the UI is closed (applies on the next open) and is remembered for the Neovim session. |
| `toggle_hints` | Show or hide the key-hint lines in the UI header. Remembered for the session; the initial value is `show_header_hints`. |

## Running

| Command | Description |
|---------|-------------|
| `run [index ...]` | Compile if the language has a `compile` step, then run every testcase or only the given 1-based indices (`:Pretest run 2 4`). |
| `run_current` | Compile if needed, then run the selected testcase. |
| `run_no_compile [index ...]` | Like `run`, but skip compilation and use the existing binary. |
| `run_current_no_compile` | `run_current` without compilation. |
| `stop` | Kill the running compiler or program. The current case becomes `Stopped` and queued cases are not started. When stopped during compilation, `Stopped` is shown next to the testcase count in the header. |

Run commands save the source buffer first if it has unsaved changes, and open the UI if it is closed.

## Testcases

| Command | Description |
|---------|-------------|
| `add` | Append an empty testcase to the end of the list and select it. Opens the UI if it is closed. |
| `edit [index]` | Open the UI and focus **Input**. With `index`, select that testcase. |
| `delete [index]` | Delete the testcase selected in the UI, or testcase `index`. Clears all results. |
| `edit_name` | Prompt for a new problem name. |
| `edit_limits` | Prompt for the time limit (ms) and the memory limit (MB). A memory limit of `0` disables the memory check. |

Input and Expected are saved automatically before a case switch, a run, closing, and exit.

Input and Expected are edited directly in their windows and can be saved with `:w`.

## Source file

| Command | Description |
|---------|-------------|
| `rename <name>` | Rename the source file. Relative paths are resolved against the source's directory. |
| `move <path>` | Move the source file. Relative paths are resolved against Neovim's cwd. A path that ends in `/` or names an existing directory keeps the current file name. |

Both commands save the buffer, rename the file and buffer, and move the `.prob` file and compiled binary to match the new path.

The command does nothing if a file already exists at the destination, if the corresponding `.prob` already exists, or if the extension is not a configured language.

## Competitive Companion

| Command | Description |
|---------|-------------|
| `receive` | Receive one problem and overwrite the **current file's** `.prob` with its testcases, name, and limits. |
| `receive problem` | Receive one problem, create a new source file for it (from `companion.template` if set), and open it. |
| `receive contest` | Receive a whole contest and create one source file per problem under `companion.contest_dir`. |
| `receive persistently` | Keep receiving. Batches with more than one task are handled as contests; a single task prompts for *This file* / *Problem*. |
| `receive stop` | Stop receiving. |
| `receive status` | Report whether pretest is receiving, in which mode, and on which port. |

See [Competitive Companion](competitive-companion.md) for details.

## UI keys

Default keys active in the pretest UI. All of them can be changed through [`ui_keys`](configuration.md#ui_keys).

| Key | Modes | Action |
|-----|-------|--------|
| `<C-n>` / `<C-p>` | Normal, Insert | Next / previous testcase |
| `<Tab>` / `<S-Tab>` | Normal, Insert | Next / previous section |
| `R` | Normal | Run all testcases (`run`) |
| `r` | Normal | Run the current testcase (`run_current`) |
| `<C-S-r>` | Normal | Run all without compiling (`run_no_compile`) |
| `<C-r>` | Normal | Run the current case without compiling (`run_current_no_compile`) |
| `s` | Normal | Stop (`stop`) |
| `q` | Normal | Close the UI |

Additional behavior that cannot be remapped:

- Moving the cursor onto a testcase line in the header selects that case.
- `:q`, `:close`, or `<C-w>c` in any pretest window saves edits and closes the whole UI.

`<Tab>` and `<C-n>`/`<C-p>` are also bound in Insert mode. To restore the Insert-mode defaults, set `modes = "n"` on those bindings.

See [`ui_keys`](configuration.md#ui_keys) for details.

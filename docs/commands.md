**English** | [한국어](ko/commands.md)

# Commands

Every pretest action is available as `:Pretest <subcommand> [argument]`. `:Pretest` without a subcommand jumps between the source and the UI.

```vim
:Pretest
:Pretest toggle_layout
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
| `:Pretest` | Jump between the source and the UI. Opens the UI if it is closed and focuses the header. With the cursor outside the UI, moves it to the header. With the cursor inside the UI, moves it to the source window in `sidebar` mode, and also closes the UI in `float` mode. |
| `toggle_layout` | Switch between `sidebar` and `float`. Works while the UI is closed (applies on the next open) and is remembered for the Neovim session. |

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
| `add` | Append an empty testcase to the end of the list, select it, and move the cursor to **Input**. Opens the UI if it is closed. |
| `edit [index]` | Open the UI and focus **Input**. With `index`, select that testcase. |
| `delete [index]` | Delete the testcase selected in the UI, or testcase `index`, after a confirmation prompt. Stops a run in progress first. |
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

Default keys active in the pretest UI. Press `?` in any pretest window to list them. Changes made through [`ui_keys`](configuration.md#ui_keys) are reflected in that list.

| Key | Modes | Windows | Action |
|-----|-------|---------|--------|
| `<C-n>` / `<C-p>` | Normal, Insert | All | Next / previous testcase |
| `<Tab>` / `<S-Tab>` | Normal, Insert | All | Next / previous section |
| `<S-CR>` | Normal | All | Run all testcases (`run`) |
| `<CR>` | Normal | All | Run the current testcase (`run_current`) |
| `g<S-CR>` | Normal | All | Run all without compiling (`run_no_compile`) |
| `g<CR>` | Normal | All | Run the current case without compiling (`run_current_no_compile`) |
| `<C-c>` / `s` | Normal | All | Stop (`stop`) |
| `q` | Normal | All | Close the UI |
| `?` | Normal | All | Show the key list |
| `<C-a>` | Normal, Insert | All | Add a testcase (`add`) |
| `a` | Normal | Header | Add a testcase (`add`) |
| `dd` | Normal | Header | Delete the current testcase (`delete`) |
| `{count}d` | Normal | Header | Delete testcase `{count}` (`delete {count}`) |

Deleting a testcase always asks for confirmation.

In Input and Expected, `<C-a>` adds a testcase instead of Vim's increment. To keep the increment, set `add = "a"` in [`ui_keys`](configuration.md#ui_keys).

Additional behavior that cannot be remapped:

- Moving the cursor onto a testcase line in the header selects that case.
- `:q`, `:close`, or `<C-w>c` in any pretest window saves edits and closes the whole UI.

`<Tab>` and `<C-n>`/`<C-p>` are also bound in Insert mode. To unbind them in Insert mode, set `modes = "n"`.

See [`ui_keys`](configuration.md#ui_keys) for details.

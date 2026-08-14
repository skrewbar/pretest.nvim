# Commands

```vim
:Pretest toggle
:Pretest toggle_layout
:Pretest toggle_hints
:Pretest run [index...]
:Pretest run_current
:Pretest run_no_compile [index...]
:Pretest stop
:Pretest add
:Pretest edit [index]
:Pretest delete [index]
:Pretest edit_limits
:Pretest edit_name
:Pretest rename <name>
:Pretest move <path>
:Pretest receive
:Pretest receive problem
:Pretest receive contest
:Pretest receive persistently
:Pretest receive stop
:Pretest receive status
```

| Command | Description |
|---------|-------------|
| `toggle` | Open or close the UI |
| `toggle_layout` | Switch between sidebar and float |
| `toggle_hints` | Show or hide header key hints |
| `run [index...]` | Compile (if needed) and run all cases, or the given indices |
| `run_current` | Compile (if needed) and run the current case |
| `run_no_compile [index...]` | Run without compiling |
| `stop` | Stop an in-flight compile/run |
| `add` | Add a testcase |
| `edit [index]` | Focus the UI (and jump to `index` if given) |
| `delete [index]` | Delete the current case, or `index` |
| `edit_limits` | Prompt for time/memory limits |
| `edit_name` | Prompt for the problem name |
| `rename <name>` | Rename the source relative to its directory; rewrite `.prob` and the binary |
| `move <path>` | Move the source relative to the cwd (a directory keeps the current basename); rewrite `.prob` and the binary |

Neovim `:saveas` and an external `mv` do not reconnect `.prob` or the compile binary. Use `rename` / `move`.

## UI keys

These are the defaults in pretest UI buffers. Override with [`ui_keys`](configuration.md#ui-keys). `<C-n>` / `<C-p>` and `<Tab>` / `<S-Tab>` also work in Insert mode.

| Key | Action |
|-----|--------|
| `<C-n>` / `<C-p>` | Next / previous testcase |
| `<Tab>` / `<S-Tab>` | Next / previous section |
| `r` | Run current case |
| `R` | Run all cases |
| `<C-r>` | Run current case (no compile) |
| `<C-S-r>` | Run all cases (no compile) |
| `s` | Stop |
| `q` | Close UI |

You can also switch cases by moving the cursor onto a case line in the header.

**Input** and **Expected** are editable. Changes persist on `:w`, before a case switch, and before `run`. Header, Output, Runtime Error, and Stderr are read-only. Stderr is shown only when non-empty; Runtime Error only when the current verdict is RE.

## Competitive Companion

Install the [Competitive Companion](https://github.com/jmerle/competitive-companion) browser extension, then:

```vim
:Pretest receive                " write tests and limits into the current source's .prob (once)
:Pretest receive problem        " create source + .prob, then open it (once)
:Pretest receive contest        " wait for a full contest batch, create files in cwd (once)
:Pretest receive persistently   " keep listening; contest if batch size > 1, else ask
:Pretest receive stop
:Pretest receive status
```

Click Companion's green plus on a problem or contest page.

Receive overwrites the stored problem name and limits from Companion. Testcases follow `replace_testcases` (Keep/Replace prompt when `false`). Path templates and port live in [Configuration](configuration.md).

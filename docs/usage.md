**English** | [한국어](ko/usage.md)

# Usage

This page follows a typical workflow: opening the UI, entering testcases, running, reading verdicts, and where pretest keeps its files. For the full list of commands and keys, see [Commands](commands.md).

## Opening the UI

Open a source file whose filetype is configured under [`languages`](configuration.md#languages) (`cpp` and `python` by default) and open the UI with `:Pretest toggle`, or `<leader>tu` if you registered the keymaps.

pretest loads the `.prob` file for that source, or creates an empty problem named `Local: <filename>` if there is none, then opens the UI and puts the cursor in **Input**. Running `:Pretest toggle` again, pressing `q` inside a pretest window, or running `:q` in one of them closes the whole UI. Closing the UI does not discard anything: results and edits stay attached to the source file for the rest of the Neovim session.

`:Pretest toggle_layout` switches between the sidebar and floating layout at any time, and `:Pretest toggle_hints` shows or hides the key hints in the header.

## Layout

The sidebar layout (default, on the right) stacks the sections below vertically. The floating layout shows the same sections as a column of floating windows in the center of the screen.

```text
┌ Pretest ─────────────────────────────┐
│ Local: main                          │  problem name
│ TL 3000ms │ ML 1024MB                │  time | memory limit
│ ──────────────────────────────────── │
│ Testcases 2/3                        │  accepted / total
│  1  AC      12ms                     │
│  2  WA       9ms                     │  the current case is marked with brackets, e.g. [n]
│ [3] RE      15ms  SIGSEGV            │
│                                      │
│ <C-n>/<C-p> switch  :w save  q close │  key hints (toggle with toggle_hints)
│ R run-all  r run-one  …              │
├ Input ───────────────────────────────┤
│ 3                                    │  input / editable
│ 1 2 3                                │
├ Expected ────────────────────────────┤
│ 6                                    │  expected output / editable
├ Output ──────────────────────────────┤
│ 6                                    │  stdout of the current case
├ Runtime Error ───────────────────────┤
│ segmentation fault (SIGSEGV)         │  only when the current verdict is RE
├ Stderr ──────────────────────────────┤  only when stderr is non-empty
│ ...                                  │
└──────────────────────────────────────┘
```

- The **header** lists every testcase with its verdict, run time, and, for `RE`/`MLE`, a short reason. Moving the cursor onto a case line selects that case.
- `<C-n>`/`<C-p>` also select cases.
- **Input** / **Expected** are editable buffers (`filetype=pretest`).
- Completely empty lines are shown as `↵`, tabs as `>`, and trailing spaces as `-`.
- **Output** shows exactly what the program printed to stdout for the current case.
- **Runtime Error** appears only when the verdict is `RE` and explains the cause: a signal name, exit code, or a hint parsed from stderr (`ZeroDivisionError`, `AddressSanitizer`, assertion messages, …).
- **Stderr** appears only when there is something to show: the program's stderr, or the compiler output on `CE`.

`<Tab>` / `<S-Tab>` cycle focus through the visible sections in Normal and Insert mode.

## Testcases

### Adding and editing

Add a testcase with `:Pretest add` or `<leader>ta`.

Edits to Input/Expected are written to the `.prob` file:

- on `:w` in either buffer
- before switching to another case, before running testcases, when the UI closes, and when Neovim exits

Leading and trailing blank lines are stored exactly as typed. They do not affect judging, because trailing whitespace is ignored during comparison (see [Verdicts](#verdicts)).

### Navigating

| Action | How |
|--------|-----|
| Next / previous case | `<C-n>` / `<C-p>` in the pretest UI (Normal/Insert mode) |
| Jump to case *n* | `:Pretest edit n`, or move the cursor onto line *n* in the header |
| Focus the UI on the current case | `:Pretest edit` |

### Deleting

`:Pretest delete` removes the current case; `:Pretest delete 3` removes case 3. Results for all cases are cleared because indices shift.

### Name and limits

The header lines are read-only. Change them through prompts:

```vim
:Pretest edit_name     " problem name shown in the header
:Pretest edit_limits   " time limit in ms, then memory limit in MB (0 disables MLE)
```

New local problems start with `default_time_limit` (3000 ms) and `default_memory_limit` (1024 MB). Problems received from Competitive Companion carry the judge's limits.

## Running

| Command | UI key | Action |
|---------|--------|--------|
| `:Pretest run` | `R` | Compile, then run every testcase |
| `:Pretest run 1 3` | | Compile, then run cases 1 and 3 |
| `:Pretest run_current` | `r` | Compile, then run the current case |
| `:Pretest run_no_compile [n...]` | `<C-S-r>` | Skip compilation and run all (or the given) cases with the existing binary |
| `:Pretest run_current_no_compile` | `<C-r>` | Skip compilation and run the current case |
| `:Pretest stop` | `s` | Stop the running compile or execution |

Selected cases become `Pending`, the header shows `Compiling` while the compiler runs, then each case runs in order and its verdict fills in as it finishes.

Processes run with the source file's directory as the working directory, receive the case input on stdin, and are killed when they exceed the time limit. Compiled languages write their binary to the artifact directory (see [Where files are stored](#where-files-are-stored)). The `no_compile` commands reuse the last successful build.

## Verdicts

| Verdict | Meaning |
|---------|---------|
| `AC` | Output matches Expected |
| `WA` | Output differs from Expected |
| `TLE` | Killed after `timeLimit` ms |
| `MLE` | Peak memory exceeded `memoryLimit` MB (checked after the process exits; the reason column shows the peak, e.g. `MLE 21MB`) |
| `RE` | Exited with a non-zero code or was terminated by a signal. The reason column shows `SIGSEGV`, `exit 1`, `ZeroDivisionError`, … |
| `CE` | Compilation failed. Compiler output is shown in **Stderr** |
| `Stopped` | Interrupted by `:Pretest stop` / `s` |
| `Pending` / `Running` | Waiting / in progress |

Output is normalized before comparison:

- trailing whitespace is removed from each line
- trailing empty lines are removed
- `\r\n` is converted to `\n`

**Memory** is the peak RSS (resident set size) measured by OS tools, so the interpreter's baseline usage counts too. Set the memory limit to `0` to turn it off.

**Runtime errors** show the signal (`SIGSEGV`, `SIGABRT`, `SIGFPE`, …) or, when the process exited normally with a non-zero code, a hint parsed from stderr: sanitizer reports (`ASan`, `UBSan`), `Assertion failed`, or the last `Error:` / `Exception:` line (Python, Java). On Windows, NTSTATUS codes such as `ACCESS_VIOLATION` and `STACK_OVERFLOW` are recognized.

## Switching files

The UI follows the buffer you are editing. Moving to another supported source file switches the UI to that file's problem; results computed for the previous file are kept and restored when you come back. Moving to a regular file whose filetype is not configured (a Markdown note, a `.txt` input file, …) closes the UI. Special buffers such as terminals, help pages, file explorers, and floating windows are ignored, so the UI stays open while you use them.

## Renaming or moving the source

`.prob` files and binaries are named after the source's absolute path, so renaming a file outside pretest disconnects it from its testcases. Use these instead:

```vim
:Pretest rename b.cpp          " relative to the source's directory
:Pretest move solutions/       " relative to Neovim's cwd; a directory keeps the file name
:Pretest move ../round2/b.cpp
```

Both commands save the buffer if needed, rename the file on disk and the buffer, and move the `.prob` file and compiled binary to the new name. They do nothing if the destination file or `.prob` already exists, or if the new extension is not a supported language.

Both complete file paths with `<Tab>`.

## Where files are stored

Everything pretest writes goes into one *artifact directory* per source file:

| `save_dir` | Artifact directory | `.prob` file | Binary (compiled languages) |
|------------|-------------------|--------------|-----------------------------|
| unset (default) | `{src_dir}/.pretest/` | `.{basename}_{md5}.prob` | `{stem}.out` |
| set | `{save_dir}/` | `.{basename}_{md5}.prob` | `{stem}_{md5[1:8]}.out` |

`{basename}` is the file name including the extension (`main.cpp`), `{stem}` is the name without it (`main`), and `{md5}` is the MD5 of the source's absolute path.

`.prob` files are compatible with CPH, so you can migrate by renaming a `.cph` folder to `.pretest`.

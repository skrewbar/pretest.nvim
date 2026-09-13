# Configuration

All keys are optional. `languages` is deep-merged, so you can override just `compile.exec`. Keys are Neovim filetypes; add an entry to support another language. Optional `extensions` maps extra suffixes onto that filetype.

With [lazy.nvim](https://github.com/folke/lazy.nvim), pass the same table as `opts`.

Default config:

```lua
require("pretest").setup({
  save_dir = nil, -- nil → {src_dir}/.pretest
  ui = "sidebar", -- or "float"
  sidebar_position = "right", -- or "left"
  -- Size: (0, 1] is a fraction of editor columns/lines; > 1 is cells.
  sidebar_width = 40,
  sidebar_min_width = nil,
  sidebar_max_width = nil,
  float_width = 0.6,
  float_height = 0.8,
  float_min_width = 30,
  float_max_width = nil,
  float_min_height = 16,
  float_max_height = nil,
  default_time_limit = 3000, -- ms
  default_memory_limit = 1024, -- MB; peak RSS over this is MLE (0 disables)
  show_header_hints = true, -- starting value for :Pretest toggle_hints
  sidebar_sections = { -- relative heights
    header = 1,
    input = 1,
    expected = 1,
    output = 1,
  },
  float_sections = {
    header = 1,
    input = 1,
    expected = 1,
    output = 1,
  },
  ui_keys = {
    next_case = "<C-n>",
    prev_case = "<C-p>",
    next_section = "<Tab>",
    prev_section = "<S-Tab>",
    close = "q",
    stop = "s",
    run_all = "R",
    run_one = "r",
    -- <C-R>/<C-r> are identical in terminals; use Ctrl-Shift-r for "all".
    run_all_no_compile = "<C-S-r>",
    run_one_no_compile = "<C-r>",
  },
  languages = {
    cpp = {
      extensions = { "cpp", "cc", "cxx" },
      compile = {
        exec = "g++", -- e.g. "g++-16" or "clang++"
        args = { "-o", "$bin", "$src" },
      },
      run = {
        exec = "$bin",
        args = {},
      },
    },
    python = {
      extensions = { "py" },
      run = {
        exec = "python3",
        args = { "$src" },
      },
    },
  },
  companion = {
    port = 27121, -- Competitive Companion (same default as CPH)
    listen_on_setup = false,
    extension = "cpp",
    template = nil, -- path, or { cpp = "...", py = "..." }
    problem_path = "{cwd}/{problem}.{ext}", -- G_Castle_Defense.cpp
    contest_dir = "{cwd}",
    contest_problem_path = "{file}.{ext}", -- A.cpp (letter / number prefix)
    prompt_path = true, -- confirm path / contest directory
    open = true, -- :edit received source and show UI
    replace_testcases = true, -- false → Keep/Replace prompt
  },
})
```

## UI size

UI sizes (`sidebar_width`, `float_width`, `float_height`, and each `min_*` / `max_*`) are numbers. Values in `(0, 1]` are fractions of editor columns (width) or lines (height); values `> 1` are cells. Min/max clamp after the base size is resolved. Omit a min/max key (or leave it `nil`) to skip that bound.

## UI keys

UI-buffer maps (not the `<leader>t` suggested keys). Each action is a string, a list, `{ "<Tab>", modes = "n" }`, or `false` to unbind. Named actions replace the whole value; omitted actions keep the default.

Defaults: `next_case` / `prev_case` / `next_section` / `prev_section` use Normal and Insert; the rest are Normal only. Set `modes` on a binding to override, e.g. `{ "<Tab>", modes = "n" }` if Insert should type a tab.

```lua
ui_keys = {
  next_section = "<C-j>", -- replaces Tab; Insert+Normal
  close = { "q", "<Esc>" },
  run_all_no_compile = false,
}
```

`:w` still saves Input/Expected and is not in `ui_keys`. Header hints follow the configured keys.

## Languages

`$src` and `$bin` in `compile`/`run` `exec` and `args` are pretest placeholders. An `exec` string or argv element that is exactly `$src` or `$bin` expands to the absolute source path or output binary path; substrings are not expanded. You can pass a function instead; it receives `{ src_path, bin_path }` and should return the executable string (`exec`) or argv table (`args`). Function results are not expanded. `$bin` is `{stem}.out` (plus a short hash when `save_dir` is set). Languages with a `compile` step write the binary there.

Memory limit is judged from **peak RSS** after the case ends. The process is not killed early for memory; TLE still applies. Interpreter overhead (Python) counts toward RSS. Set the limit to `0` to disable.

Peak RSS is read from OS builtins (no extra packages, compiler, or `gtime`):

- **Linux:** GNU `/usr/bin/time -f %M -o <file>` (KiB). If that binary is missing or not GNU, `/proc/<pid>/status` `VmHWM` while the process is alive.
- **macOS:** `/usr/bin/time -l`; `maximum resident set size` (bytes → KiB). BSD rusage is stripped from stderr.
- **Windows:** `PeakWorkingSet64` via PowerShell before the libuv process handle is closed. If `Get-Process` only lists running processes, pretest attaches while the process is alive and reads the same counter after exit.

Header example: `MLE  21MB`.

On RE, a **Runtime Error** section shows the signal, exit code, or exception (e.g. `SIGSEGV`). Process stderr is unchanged in **Stderr**. To get sanitizer traces, add flags yourself:

```lua
args = { "-o", "$bin", "$src", "-fsanitize=address,undefined" },
```

## Artifact directory

`artifact_dir` is `save_dir` when set, otherwise `{src_dir}/.pretest`. `.prob` names use the full source basename (with extension) plus MD5 of the absolute source path.

```text
# under .pretest next to the source (default)
{src_dir}/.pretest/.{basename}_{md5(srcPath)}.prob
{src_dir}/.pretest/{stem}.out

# when save_dir is set (short hash on binaries avoids collisions)
{save_dir}/.{basename}_{md5(srcPath)}.prob
{save_dir}/{stem}_{md5(srcPath)[1:8]}.out
```

## Competitive Companion

Install the [Competitive Companion](https://github.com/jmerle/competitive-companion) browser extension. pretest listens on `127.0.0.1:27121` by default (already in Companion's port list), so no extra Companion config is required.

If bind fails, another process is using the port (CPH, CompetiTest, or another Neovim). Change `companion.port` or stop the other listener.

Received source names come from the problem title, not Java `taskClass`:

- **problem:** `{problem}` → `G_Castle_Defense.cpp` (`G. Castle Defense`)
- **contest:** `{file}` → `A.cpp`, `B.cpp` (letter/number prefix; full slug if there is none)

`{cwd}` is Neovim's current working directory. Placeholders: `{cwd}`, `{home}`, `{name}`, `{index}`, `{slug}`, `{problem}`, `{file}`, `{task_class}`, `{ext}`, `{group}`, `{judge}`, `{contest}`. Paths may also be a function `(task, ext) -> string`.

`.prob` files still follow the usual `artifact_dir` rules next to each source.

Receive overwrites the stored problem name and limits from Companion. Testcases follow `replace_testcases` (Keep/Replace prompt when `false`).

See [Commands](commands.md) for `:Pretest receive`.

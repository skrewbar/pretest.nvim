**English** | [한국어](ko/configuration.md)

# Configuration

Pass a table to `require("pretest").setup()` (or `opts` with lazy.nvim). Every key is optional and is deep-merged over the defaults, so omitted keys keep their default values. Lists (`args`, multi-key `ui_keys` values, `extensions`) are replaced as a whole rather than merged, so write the complete list when you change one.

## Defaults

```lua
require("pretest").setup({
  -- Where .prob files and binaries go. nil → "{src_dir}/.pretest"
  save_dir = nil,

  -- Layout ------------------------------------------------------------
  ui = "sidebar", -- "sidebar" | "float"
  sidebar_position = "right", -- "left" | "right"
  -- Size: a fraction when less than 1, cells when greater than 1
  sidebar_width = 40, -- 40 cells
  sidebar_min_width = nil,
  sidebar_max_width = nil,
  float_width = 0.6, -- 60% of the width
  float_height = 0.8,
  float_min_width = 30,
  float_max_width = nil,
  float_min_height = 16,
  float_max_height = nil,
  -- Relative section heights
  sidebar_sections = { header = 1, input = 1, expected = 1, output = 1 },
  float_sections = { header = 1, input = 1, expected = 1, output = 1 },
  show_header_hints = true,

  -- Default limits -----------------------------------------------------
  default_time_limit = 3000, -- ms
  default_memory_limit = 1024, -- MB; 0 disables MLE

  -- pretest UI keys ----------------------------------------------------
  ui_keys = {
    next_case = "<C-n>",
    prev_case = "<C-p>",
    next_section = "<Tab>",
    prev_section = "<S-Tab>",
    close = "q",
    stop = { "<C-c>", "s" },
    run_all = "<S-CR>",
    run_one = "<CR>",
    run_all_no_compile = "g<S-CR>",
    run_one_no_compile = "g<CR>",
  },

  -- Languages ----------------------------------------------------------
  languages = {
    cpp = {
      extensions = { "cpp", "cc", "cxx" },
      compile = { exec = "g++", args = { "-o", "$bin", "$src" } },
      run = { exec = "$bin", args = {} },
    },
    python = {
      extensions = { "py" },
      run = { exec = "python3", args = { "$src" } },
    },
  },

  -- Competitive Companion ----------------------------------------------
  companion = {
    port = 27121,
    listen_on_setup = false,
    extension = "cpp",
    template = nil, -- "path/to/template.cpp" or { cpp = "...", py = "..." }
    problem_path = "{cwd}/{problem}.{ext}",
    contest_dir = "{cwd}",
    contest_problem_path = "{file}.{ext}",
    prompt_path = true,
    open = true, -- open the buffer after receive when true
    replace_testcases = true,
  },
})
```

## `save_dir`

`nil` (default) keeps artifacts next to each source in `{src_dir}/.pretest/`. A path (`~` and environment variables are expanded) stores every `.prob` file and binary at that location. See [Usage → Where files are stored](usage.md#where-files-are-stored) for the file-name rules.

## Layout

### `ui`, `sidebar_position`

Initial layout and which side the sidebar opens on. `:Pretest toggle_layout` changes the layout for the current Neovim session.

### Sizes

`sidebar_width`, `float_width`, `float_height`, and the `*_min_*` / `*_max_*` values are numbers. Values in `(0, 1]` are fractions of the editor width (for width options) or height (for height options); values greater than `1` are cells. The base size is resolved first, then clamped by min/max, then to the editor. Leave a bound `nil` to skip it.

```lua
sidebar_width = 0.3, sidebar_min_width = 44, -- 30% of columns, never narrower than 44
float_height = 40,                            -- exactly 40 lines (including borders)
```

The sidebar width is fixed (`winfixwidth`) so other splits do not squeeze it. `float_height` is the total height of the floating stack including borders.

### `sidebar_sections`, `float_sections`

Relative weights for **header**, **Input**, **Expected**, and **Output**. Each section gets at least 3 lines; in the sidebar the header grows to fit the testcase list when there is room. **Runtime Error** and **Stderr** take fixed space only while shown (up to 4 and 8 lines respectively).

```lua
sidebar_sections = { header = 1, input = 2, expected = 2, output = 3 },
```

### `show_header_hints`

Whether the header shows key hints. `:Pretest toggle_hints` toggles this for the current session only. Hints are rendered from your actual `ui_keys`, so they stay accurate after remapping.

## `ui_keys`

Keys mapped only inside the pretest UI (buffer-local).

| Value | Meaning |
|-------|---------|
| `"<C-j>"` | One key, default modes |
| `{ "<C-j>", modes = "n" }` | One key with explicit modes (`"n"`, `"i"`, or a list) |
| `{ "q", "<Esc>" }` | Several keys |
| `{ { "<Tab>", modes = "n" }, "<C-l>" }` | Mixed |
| `false` | Unbind |

Default modes are **Normal/Insert** for `next_case`, `prev_case`, `next_section`, `prev_section`, and Normal only for the rest. Setting an action replaces its default entirely; omitted actions keep theirs.

```lua
ui_keys = {
  next_section = { "<Tab>", modes = "n" }, -- unbind <Tab> in Insert mode
  prev_section = { "<S-Tab>", modes = "n" },
  close = { "q", "<Esc>" },
  run_all_no_compile = false,
},
```

`:w` (save Input/Expected), header cursor selection, and `:q` closing the UI are built-in and not part of `ui_keys`.

> If your terminal emulator cannot distinguish `<CR>` from `<S-CR>`, change those keys.

## `languages`

You can change how a language is compiled and run, or add a new language.

The basic format is as follows.

```lua
languages = {
  <filetype> = {
    extensions = { "ext", ... }, -- (optional) extra suffixes to treat as this filetype
    compile = {                  -- (optional) omit for interpreted languages
      exec = "compiler",         -- string or function(ctx) -> string
      args = { ... },            -- string list or function(ctx) -> string[]
    },
    run = {
      exec = "program",          -- required
      args = { ... },
    },
  },
}
```

- `exec` is spawned directly, not through a shell. Therefore quoting, globbing, `~`, and `&&` do not work.
- In `exec` and each element of `args`, a value of `$src` is replaced with the absolute source path and `$bin` with the binary path. Placeholders embedded in a longer string (e.g. `"--out=$bin"`) are **not** replaced. Use a function when you need that.
- Functions receive `ctx = { src_path = "...", bin_path = "..." }` and must return a string (`exec`) or a list (`args`). The return value is used as is.
- You do not have to use `bin_path` / `$bin`. You can write elsewhere.
- Both compile and run use the source file's directory as the working directory.

### Which language a buffer uses

pretest first checks the buffer's `filetype`. If that is not a key in `languages`, it tries `vim.filetype.match` on the path, then the `extensions` lists, and finally a key equal to the extension. Files created by Competitive Companion use `companion.extension`, so that extension must map to a configured language for the UI to open automatically.

### Examples

- Changing the C++ compiler and flags

```lua
languages = {
  cpp = {
    compile = {
      exec = "clang++",
      args = { "-std=c++20", "-O2", "-Wall", "-fsanitize=address,undefined", "-o", "$bin", "$src" },
    },
  },
},
```

- Use PyPy instead of CPython

```lua
languages = { python = { run = { exec = "pypy3" } } },
```

- Add C and Rust

```lua
languages = {
  c = {
    extensions = { "c" },
    compile = { exec = "gcc", args = { "-O2", "-o", "$bin", "$src" } },
    run = { exec = "$bin" },
  },
  rust = {
    extensions = { "rs" },
    compile = { exec = "rustc", args = { "-O", "-o", "$bin", "$src" } },
    run = { exec = "$bin" },
  },
},
```

- Add Java

```lua
languages = {
  java = {
    extensions = { "java" },
    compile = {
      exec = "javac",
      args = function(ctx)
        return { "-d", vim.fs.dirname(ctx.bin_path), ctx.src_path }
      end,
    },
    run = {
      exec = "java",
      args = function(ctx)
        return { "-cp", vim.fs.dirname(ctx.bin_path), vim.fn.fnamemodify(ctx.src_path, ":t:r") }
      end,
    },
  },
},
```

Run through a shell when you need shell features, for example a larger stack on Linux:

```lua
run = {
  exec = "sh",
  args = function(ctx)
    return { "-c", "ulimit -s 262144 && exec " .. vim.fn.shellescape(ctx.bin_path) }
  end,
},
```

## Competitive Companion

The `companion` table is documented on its own page: [Competitive Companion](competitive-companion.md).

## Highlight groups

All groups are defined with `default = true` and can be overridden in your colorscheme or with `vim.api.nvim_set_hl(0, "PretestAC", { ... })`.

| Group | Default link | Used for |
|-------|--------------|----------|
| `PretestAC` | `DiagnosticOk` | `AC` verdicts and an all-green summary |
| `PretestWA` | `DiagnosticError` | `WA` |
| `PretestRE` | `DiagnosticError` | `RE` |
| `PretestCE` | `DiagnosticError` | `CE` |
| `PretestTLE` | `DiagnosticWarn` | `TLE` |
| `PretestMLE` | `DiagnosticWarn` | `MLE` |
| `PretestStopped` | `DiagnosticWarn` | `Stopped` |
| `PretestRunning` | `DiagnosticInfo` | `Running`, `Compiling` |
| `PretestPending` | `Comment` | Cases without a result |
| `PretestCurrent` | `Title` | `[n]` marker of the selected case |
| `PretestKey` | `Special` | Key names in header hints |
| `PretestHint` | `Comment` | Hint labels |
| `PretestSep` | `FloatBorder` foreground | Header separator line and `│` |

pretest buffers have `filetype=pretest` and names of the form `pretest://input#<bufnr>`, which you can use to exclude them from statuslines, autoformatters, or completion plugins.

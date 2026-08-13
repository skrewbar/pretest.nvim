# pretest.nvim

Local competitive programming test runner for Neovim.

Compile, run, and judge test cases next to your source file. Test data is stored in a single `.prob` JSON file per problem under `.pretest/` (or `save_dir`).

## Features (v1)

- C++ and Python runners
- Sidebar or floating UI (toggle at runtime)
- Header key hints (toggle with `:Pretest toggle_hints`; default on via `show_header_hints`)
- Navigate test cases with `<C-n>` / `<C-p>`, or by moving the cursor onto a case line in the header
- Move between Header / Input / Expected / Output (and Stderr when shown) with `<Tab>` / `<S-Tab>`
- Edit **Input** / **Expected** directly in the UI (`:w` or before run/switch)
- Edit problem name with `:Pretest edit_name`
- Edit problem time/memory limits with `:Pretest edit_limits`
- Verdicts: AC, WA, RE, TLE, CE
- Receive problems from [Competitive Companion](https://github.com/jmerle/competitive-companion)

## Install (lazy.nvim)

```lua
{
  "skrewbar/pretest.nvim",
  -- lazy = false, -- required for companion.listen_on_setup (startup receive)
  opts = {}, -- defaults; override keys from Configuration as needed
  cmd = "Pretest",
  keys = {
    { "<leader>tu", "<cmd>Pretest toggle<cr>", desc = "Toggle UI" },
    { "<leader>tt", "<cmd>Pretest toggle_layout<cr>", desc = "Toggle sidebar/float" },
    { "<leader>tR", "<cmd>Pretest run<cr>", desc = "Run all testcases" },
    { "<leader>tr", "<cmd>Pretest run_current<cr>", desc = "Run current testcase" },
    { "<leader>tn", "<cmd>Pretest run_no_compile<cr>", desc = "Run all (no compile)" },
    { "<leader>ta", "<cmd>Pretest add<cr>", desc = "Add testcase" },
    { "<leader>te", "<cmd>Pretest edit<cr>", desc = "Edit/Focus" },
    { "<leader>td", "<cmd>Pretest delete<cr>", desc = "Delete testcase" },
  },
}
```

## Configuration

All keys are optional. `languages` is deep-merged, so you can override just `compile.exec`.

```lua
require("pretest").setup({
  ui = "sidebar", -- or "float"
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
  save_dir = nil, -- nil → {src_dir}/.pretest
  default_time_limit = 3000, -- ms
  default_memory_limit = 1024, -- MB
  show_header_hints = true, -- starting value for :Pretest toggle_hints
  sidebar_sections = { header = 1, input = 1, expected = 1, output = 1 }, -- relative heights
  float_sections = { header = 1, input = 1, expected = 1, output = 1 },
  languages = {
    cpp = {
      compile = {
        exec = "g++", -- e.g. "g++-16" or "clang++"
        args = { "-o", "$bin", "$src" },
      },
    },
    python = {
      run = { exec = "python3" },
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

With lazy.nvim, pass the same table as `opts`.

UI sizes (`sidebar_width`, `float_width`, `float_height`, and each `min_*` / `max_*`) are numbers. Values in `(0, 1]` are fractions of editor columns (width) or lines (height); values `> 1` are cells. Min/max clamp after the base size is resolved. Omit a min/max key (or leave it `nil`) to skip that bound.

`$src` and `$bin` in `compile.args` are pretest placeholders. Before compile they expand to the absolute source path and the output binary path. You can pass a function instead; it receives `{ src_path, bin_path }` and should return the argv table. `exec` and `run.args` do not expand `$src` / `$bin` — use a function if you need those paths there.

## Commands

```vim
:Pretest toggle
:Pretest toggle_layout
:Pretest toggle_hints
:Pretest run [index...]
:Pretest run_current
:Pretest run_no_compile [index...]
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

## `.prob` compatibility

pretest.nvim reads and writes problem JSON files that are compatible with the `.prob` schema commonly used by VS Code CPH (independent implementation; not derived from CPH source).

Path pattern (same directory for `.prob` and compile binaries):

```text
# under .pretest next to the source (default)
{src_dir}/.pretest/.{basename}_{md5(srcPath)}.prob
{src_dir}/.pretest/{stem}.out

# when save_dir is set (short hash on binaries avoids collisions)
{save_dir}/.{basename}_{md5(srcPath)}.prob
{save_dir}/{stem}_{md5(srcPath)[1:8]}.out
```

`artifact_dir` is `save_dir` when set, otherwise `{src_dir}/.pretest`. `.prob` names use the full source basename (with extension) plus MD5 of the absolute source path, matching the common CPH naming pattern.

`:Pretest rename <name>` renames the source relative to its directory; `:Pretest move <path>` moves it relative to the cwd (a directory destination keeps the current basename). Both rewrite `.prob` and the compile binary for the new absolute path. Neovim `:saveas` and an external `mv` do not.

## Competitive Companion

Install the [Competitive Companion](https://github.com/jmerle/competitive-companion) browser extension. pretest listens on `127.0.0.1:27121` by default (already in Companion's port list), so no extra Companion config is required.

```vim
:Pretest receive                " write tests and limits into the current source's .prob (once)
:Pretest receive problem        " create source + .prob, then open it (once)
:Pretest receive contest        " wait for a full contest batch, create files in cwd (once)
:Pretest receive persistently   " keep listening; contest if batch size > 1, else ask
:Pretest receive stop
:Pretest receive status
```

Then click Companion's green plus on a problem or contest page.

Receive overwrites the stored problem name and limits from Companion. Testcases follow `replace_testcases` (Keep/Replace prompt when `false`).

If bind fails, another process is using the port (CPH, CompetiTest, or another Neovim). Change `companion.port` or stop the other listener.

Received source names come from the problem title, not Java `taskClass`:

- **problem:** `{problem}` → `G_Castle_Defense.cpp` (`G. Castle Defense`)
- **contest:** `{file}` → `A.cpp`, `B.cpp` (letter/number prefix; full slug if there is none)

`{cwd}` is Neovim's current working directory. Placeholders: `{cwd}`, `{home}`, `{name}`, `{index}`, `{slug}`, `{problem}`, `{file}`, `{task_class}`, `{ext}`, `{group}`, `{judge}`, `{contest}`. Paths may also be a function `(task, ext) -> string`.

`.prob` files still follow the usual `artifact_dir` rules next to each source.

## License

MIT

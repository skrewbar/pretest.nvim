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
- Edit problem time/memory limits with `:Pretest edit_limits`
- Verdicts: AC, WA, RE, TLE, CE

## Install (lazy.nvim)

```lua
{
  "skrewbar/pretest.nvim",
  lazy = false,
  opts = {}, -- defaults; override keys from Configuration as needed
  keys = {
    { "<leader>tu", "<cmd>Pretest show<cr>", desc = "Show/Toggle UI" },
    { "<leader>tt", "<cmd>Pretest toggle_ui<cr>", desc = "Toggle UI mode" },
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
  sidebar_width = 48,
  float_width = 0.4, -- fraction of editor columns
  float_height = 0.6, -- fraction of editor lines
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
})
```

With lazy.nvim, pass the same table as `opts`.

`$src` and `$bin` in `compile.args` are pretest placeholders. Before compile they expand to the absolute source path and the output binary path. You can pass a function instead; it receives `{ src_path, bin_path }` and should return the argv table. `exec` and `run.args` do not expand `$src` / `$bin` — use a function if you need those paths there.

## Commands

```vim
:Pretest show
:Pretest toggle_ui
:Pretest toggle_hints
:Pretest run [index...]
:Pretest run_current
:Pretest run_no_compile [index...]
:Pretest add
:Pretest edit [index]
:Pretest delete [index]
:Pretest edit_limits
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

## License

MIT

# pretest.nvim

Local competitive programming test runner for Neovim.

Compile, run, and judge test cases next to your source file. Test data is stored in a single `.prob` JSON file per problem.

## Features (v1)

- C++ and Python runners
- Sidebar or floating UI (toggle at runtime)
- Header key hints (toggle with `:Pretest toggle_hints`; default on via `show_header_hints`)
- Navigate test cases with `<C-n>` / `<C-p>`
- Edit **Input** / **Expected** directly in the UI (`:w` or before run/switch)
- Verdicts: AC, WA, RE, TLE, CE

## Install (lazy.nvim)

```lua
{
  dir = vim.fn.expand("~/Programming/pretest.nvim"), -- or your clone path / GitHub url
  lazy = false,
  opts = {
    -- save_dir = vim.fn.expand("~/cp/.probs"), -- optional; omit to store next to the source
    -- show_header_hints = true, -- default; starting value for :Pretest toggle_hints
    -- sidebar_sections = { header = 1, input = 1, expected = 1, output = 1 },
    -- float_sections = { header = 1, input = 1, expected = 1, output = 1 },
  },
  keys = {
    { "<leader>tr", "<cmd>Pretest show<cr>", desc = "Pretest show" },
    { "<leader>tt", "<cmd>Pretest toggle_ui<cr>", desc = "Pretest toggle UI" },
    { "<leader>th", "<cmd>Pretest toggle_hints<cr>", desc = "Pretest toggle hints" },
    { "<leader>tR", "<cmd>Pretest run<cr>", desc = "Pretest run" },
    { "<leader>to", "<cmd>Pretest run_current<cr>", desc = "Pretest run current" },
    { "<leader>ta", "<cmd>Pretest add<cr>", desc = "Pretest add" },
    { "<leader>te", "<cmd>Pretest edit<cr>", desc = "Pretest edit" },
    { "<leader>td", "<cmd>Pretest delete<cr>", desc = "Pretest delete" },
  },
}
```

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
```

## `.prob` compatibility

pretest.nvim reads and writes problem JSON files that are compatible with the `.prob` schema commonly used by VS Code CPH (independent implementation; not derived from CPH source).

Path pattern (same directory for `.prob` and compile binaries):

```text
# next to the source (default)
{src_dir}/.{basename}.prob
{src_dir}/{stem}.out

# when save_dir is set (hash avoids collisions across problems)
{save_dir}/.{basename}_{md5(srcPath)}.prob
{save_dir}/{stem}_{md5(srcPath)[1:8]}.out
```

`artifact_dir` is `save_dir` when set, otherwise the source file's directory. The MD5 suffix is only added when `save_dir` is set.

## License

MIT

**English** | [한국어](README.ko.md)

# pretest.nvim

Run testcases and check the results right inside Neovim.

![pretest.nvim demo](demo.gif)

## Features

- **Language settings** C++ and Python are supported out of the box; add or modify languages through the `languages` config.
- Switch between the **sidebar** and **floating** layout at runtime.
- **Competitive Companion integration** Receive a single problem into the current file, create a new file per problem, or generate a whole contest at once.
- **Buffer-aware UI** Moving between source files switches the UI to that file's problem, and per-file results are kept.
- **Safe file moves** `:Pretest rename` / `:Pretest move` carry the `.prob` file and compiled binary along with the source.

## Requirements

- [Neovim](https://neovim.io/) 0.10 or newer
- (Windows) One of `md5`, `openssl`, or `md5sum` on `PATH`
  If Git for Windows is installed in `C:\Program Files\Git`, add `C:\Program Files\Git\usr\bin` to `PATH`.

## Quick start

Install with [lazy.nvim](https://github.com/folke/lazy.nvim). For other plugin managers, see [Installation](docs/installation.md).

```lua
{
  "skrewbar/pretest.nvim",
  cmd = "Pretest",
  opts = {}, -- see docs/configuration.md
  keys = {
    { "<leader>tu", "<cmd>Pretest toggle<cr>", desc = "Toggle UI" },
    { "<leader>tt", "<cmd>Pretest toggle_layout<cr>", desc = "Toggle sidebar/float" },
    { "<leader>tR", "<cmd>Pretest run<cr>", desc = "Run all testcases" },
    { "<leader>tr", "<cmd>Pretest run_current<cr>", desc = "Run current testcase" },
    { "<leader>tn", "<cmd>Pretest run_current_no_compile<cr>", desc = "Run current testcase (no compile)" },
    { "<leader>tN", "<cmd>Pretest run_no_compile<cr>", desc = "Run all (no compile)" },
    { "<leader>ts", "<cmd>Pretest stop<cr>", desc = "Stop run" },
    { "<leader>ta", "<cmd>Pretest add<cr>", desc = "Add testcase" },
    { "<leader>te", "<cmd>Pretest edit<cr>", desc = "Edit/Focus" },
    { "<leader>td", "<cmd>Pretest delete<cr>", desc = "Delete testcase" },
  },
}
```

In a source file:

1. `<leader>ta` or `:Pretest add` opens the UI with a new empty testcase and puts the cursor in **Input**.
2. Fill in the Input section, move to **Expected** with `<Tab>`, type the expected output, and save with `:w`.
3. Press `R` (run all) or `r` (run the current case). Verdicts appear in the header and the program output in **Output**.
4. `<C-n>` / `<C-p>` move between testcases; `q` closes the UI.

Instead of typing testcases, you can run `:Pretest receive` and click the Competitive Companion button on a problem page. See [Competitive Companion](docs/competitive-companion.md).

## Documentation

- [Installation](docs/installation.md)
- [Usage](docs/usage.md)
- [Commands](docs/commands.md)
- [Configuration](docs/configuration.md)
- [Competitive Companion](docs/competitive-companion.md)

## `.prob` files

Testcases, the problem name, and limits are stored as JSON in `.pretest/.{filename}_{md5}.prob` next to the source file (or under `save_dir`). The format is compatible with the `.prob` files written by the [Competitive Programming Helper](https://github.com/agrawal-d/cph) VS Code extension, and fields pretest does not use are preserved. See [Usage → Where files are stored](docs/usage.md#where-files-are-stored).

## Related projects

- [CompetiTest.nvim](https://github.com/xeluxee/competitest.nvim)
- [Competitive Programming Helper](https://github.com/agrawal-d/cph)

## License

[Apache License 2.0](LICENSE). See [NOTICE](NOTICE).

**English** | [한국어](ko/installation.md)

# Installation

pretest.nvim is a pure Lua plugin with no runtime dependencies beyond Neovim 0.10+. Install it with any plugin manager, then call `require("pretest").setup()` (lazy.nvim does this for you through `opts`).

## Requirements

- Neovim 0.10+ \
  Uses `vim.system`, `vim.fs`, and `vim.uv`.
- (Windows) One of `md5`, `openssl`, or `md5sum` \
  Used to derive `.prob` file names. \
  If Git for Windows is installed, use `md5sum` or `openssl` from its `usr\bin`.

## lazy.nvim

```lua
-- lua/plugins/pretest.lua
return {
  "skrewbar/pretest.nvim",
  cmd = "Pretest",
  opts = {}, -- see configuration.md
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

With `cmd = "Pretest"` and `keys`, the plugin is not loaded until first use. To start receiving from Competitive Companion as soon as Neovim starts (`companion.listen_on_setup = true`), add `lazy = false` so that `setup()` runs at startup.

## vim.pack (Neovim 0.12+)

```lua
vim.pack.add({ "https://github.com/skrewbar/pretest.nvim" })
require("pretest").setup({})
```

## vim-plug

```vim
Plug 'skrewbar/pretest.nvim'
```

Run `:PlugInstall`, then call `setup()` from Lua (see [Setup without lazy.nvim](#setup-without-lazynvim)).

## mini.deps

```lua
require("mini.deps").add({ source = "skrewbar/pretest.nvim" })
require("pretest").setup({})
```

## Manual (Neovim packages)

Clone this repository into a `pack/*/start/` directory (see `:help packages`) and call `setup()` from your config:

```sh
git clone https://github.com/skrewbar/pretest.nvim \
  ~/.local/share/nvim/site/pack/pretest/start/pretest.nvim
```

## Setup without lazy.nvim

Add the following to `init.lua` or a file it sources.

```lua
require("pretest").setup({
  -- see configuration.md
})

local map = function(lhs, cmd, desc)
  vim.keymap.set("n", lhs, "<cmd>Pretest " .. cmd .. "<cr>", { desc = desc })
end

map("<leader>tu", "toggle", "Toggle UI")
map("<leader>tt", "toggle_layout", "Toggle sidebar/float")
map("<leader>tR", "run", "Run all testcases")
map("<leader>tr", "run_current", "Run current testcase")
map("<leader>tn", "run_current_no_compile", "Run current testcase (no compile)")
map("<leader>tN", "run_no_compile", "Run all (no compile)")
map("<leader>ts", "stop", "Stop run")
map("<leader>ta", "add", "Add testcase")
map("<leader>te", "edit", "Edit/Focus")
map("<leader>td", "delete", "Delete testcase")
```

Every action is available as `:Pretest <subcommand>`, so you can use keys other than `<leader>t`. Keys inside the pretest UI windows (`r`, `R`, `<C-n>`, …) are a separate setting, [`ui_keys`](configuration.md#ui_keys).

## which-key.nvim

[which-key.nvim](https://github.com/folke/which-key.nvim) v3 reads the `desc` of each mapping automatically. To set the `<leader>t` group name and icons, add a `spec` to which-key's options.

```lua
-- lua/plugins/pretest.lua
return {
  {
    "skrewbar/pretest.nvim",
    cmd = "Pretest",
    opts = {},
    keys = {
      -- ... same keys as above ...
    },
  },
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>t", group = "Pretest", icon = "󰤑" },
        { "<leader>tu", icon = "󰖷" },
        { "<leader>tt", icon = "󰖯" },
        { "<leader>tR", icon = "󰐊" },
        { "<leader>tr", icon = "󰑮" },
        { "<leader>tn", icon = "󰑮" },
        { "<leader>tN", icon = "󰓦" },
        { "<leader>ts", icon = "󰓛" },
        { "<leader>ta", icon = "󰐕" },
        { "<leader>te", icon = "󰏫" },
        { "<leader>td", icon = "󰆴" },
      },
    },
  },
}
```

With `optional = true`, the spec is merged into your existing which-key spec. Without lazy.nvim, pass the same table to `require("which-key").add({ ... })`.

## Verifying the install

Open any `.cpp` or `.py` file and run `:Pretest toggle`. A sidebar titled `Local: <filename>` should appear.

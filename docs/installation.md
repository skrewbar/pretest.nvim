# Installation

pretest.nvim does not depend on [lazy.nvim](https://github.com/folke/lazy.nvim). Install the plugin with any manager (or manually), then call `require("pretest").setup()` from your config.

For lazy.nvim, see the [README](../README.md#install-lazynvim).

## Neovim packages

Clone into a `pack/*/start/` directory (see `:help packages`):

```sh
git clone https://github.com/skrewbar/pretest.nvim \
  ~/.local/share/nvim/site/pack/pretest/start/pretest.nvim
```

## vim-plug

```vim
Plug 'skrewbar/pretest.nvim'
```

Run `:PlugInstall`, then load the plugin in your Lua config (see below).

## mini.deps

```lua
require("mini.deps").add({ source = "skrewbar/pretest.nvim" })
```

## Setup and keymaps

Add this to `init.lua` (or a file sourced from it):

```lua
require("pretest").setup({
  -- opts; see configuration.md
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

Competitive Companion at startup: set `companion.listen_on_setup = true` in `setup()` (see [Configuration](configuration.md)). With lazy.nvim you also need `lazy = false`; without lazy, calling `setup()` at startup is enough.

## which-key.nvim

Register the group and icons when which-key loads. Unlike lazy-loaded pretest, there is no timing issue here:

```lua
require("which-key").add({
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
})
```

Or merge into your which-key `setup({ spec = { ... } })` table.

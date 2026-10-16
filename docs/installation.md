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
    { "<leader>j", "<cmd>Pretest<cr>", desc = "Pretest" },
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

vim.keymap.set("n", "<leader>j", "<cmd>Pretest<cr>", { desc = "Pretest" })
```

`:Pretest` opens the UI. While the UI is open, it moves the cursor between the source and the UI header. Everything else is done with UI keys (press `?` in the UI to list them, or see [UI keys](commands.md#ui-keys)) or with `:Pretest <subcommand>`. The keys inside the UI are a separate setting, [`ui_keys`](configuration.md#ui_keys).

## which-key.nvim

[which-key.nvim](https://github.com/folke/which-key.nvim) v3 reads the `desc` of each mapping automatically. The UI keys are buffer-local mappings that carry a `desc` too, so which-key lists them inside the pretest UI without any setup. To add icons, add a `spec` to which-key's options. Entries under `real = true` show only where the matching buffer-local mapping exists (see [UI keys](commands.md#ui-keys)).

```lua
-- lua/plugins/pretest.lua
return {
  {
    "skrewbar/pretest.nvim",
    cmd = "Pretest",
    opts = {},
    keys = {
      { "<leader>j", "<cmd>Pretest<cr>", desc = "Pretest" },
    },
  },
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>j", icon = "󰤑" },
        -- Pretest UI buffer keys (shown only when the buffer-local mapping exists)
        {
          real = true,
          { "<C-n>", mode = { "n", "i" }, icon = "󰑐" },
          { "<C-p>", mode = { "n", "i" }, icon = "󰑐" },
          { "<Tab>", mode = { "n", "i" }, icon = "󰘳" },
          { "<S-Tab>", mode = { "n", "i" }, icon = "󰘵" },
          { "<S-CR>", icon = "󰐊" },
          { "<CR>", icon = "󰑮" },
          { "g<S-CR>", icon = "󰓦" },
          { "g<CR>", icon = "󰑮" },
          { "<C-c>", icon = "󰓛" },
          { "s", icon = "󰓛" },
          { "<C-a>", mode = { "n", "i" }, icon = "󰐕" },
          { "a", icon = "󰐕" },
          { "d", icon = "󰆴" },
          { "?", icon = "󰋖" },
          { "q", icon = "󰅖" },
        },
      },
    },
  },
}
```

With `optional = true`, the spec is merged into your existing which-key spec. Without lazy.nvim, pass the same table to `require("which-key").add({ ... })`. If you remap UI keys through [`ui_keys`](configuration.md#ui_keys), update the `real = true` block to match.

## Verifying the install

Open any `.cpp` or `.py` file and run `:Pretest`. A sidebar titled `Local: <filename>` should appear.

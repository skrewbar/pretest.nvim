[English](../installation.md) | **한국어**

# 설치

pretest.nvim은 Neovim 0.10+ 외에 런타임 의존성이 없는 순수 Lua 플러그인입니다. 아무 플러그인 매니저로 설치한 뒤 `require("pretest").setup()`을 호출하면 됩니다 (lazy.nvim은 `opts`를 통해 자동으로 호출합니다).

## 요구 사항

- Neovim 0.10+ \
  `vim.system`, `vim.fs`, `vim.uv`를 사용합니다.
- (Windows) `md5`, `openssl`, `md5sum`중 하나 \
  `.prob` 파일 이름 생성에 사용됩니다. \
  Git for Windows가 설치되어 있는 경우 `usr\bin`에 있는 `md5sum`과 `openssl`를 사용하면 됩니다.

## lazy.nvim

```lua
-- lua/plugins/pretest.lua
return {
  "skrewbar/pretest.nvim",
  cmd = "Pretest",
  opts = {}, -- configuration.md 참고
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

`cmd = "Pretest"`와 `keys`에 의해 플러그인은 사용하기 전까지 로드되지 않습니다. Neovim이 시작하는 즉시 Competitive Companion 수신을 시작하려면(`companion.listen_on_setup = true`) `lazy = false`를 추가해 `setup()`이 시작 시 실행되도록 해야 합니다.

## vim.pack (Neovim 0.12+)

```lua
vim.pack.add({ "https://github.com/skrewbar/pretest.nvim" })
require("pretest").setup({})
```

## vim-plug

```vim
Plug 'skrewbar/pretest.nvim'
```

`:PlugInstall`을 실행한 뒤 Lua에서 `setup()`을 호출합니다 ([lazy.nvim 없이 설정하기](#lazynvim-없이-설정하기) 참고).

## mini.deps

```lua
require("mini.deps").add({ source = "skrewbar/pretest.nvim" })
require("pretest").setup({})
```

## 수동 설치 (Neovim packages)

`pack/*/start/` 디렉터리에 이 리포지토리를 클론하고(`:help packages` 참고) 설정 파일에서 `setup()`을 호출합니다:

```sh
git clone https://github.com/skrewbar/pretest.nvim \
  ~/.local/share/nvim/site/pack/pretest/start/pretest.nvim
```

## lazy.nvim 없이 설정하기

`init.lua`혹은 `init.lua`가 불러오는 파일에 다음을 추가합니다.

```lua
require("pretest").setup({
  -- configuration.md 참고
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

모든 동작은 `:Pretest <subcommand>`로 실행할 수 있으므로 `<leader>t`가 아닌 다른 키를 사용해도 됩니다. pretest UI 창 안에서 쓰는 키(`r`, `R`, `<C-n>` 등)는 별도 설정인 [`ui_keys`](configuration.md#ui_keys)에서 바꿀 수 있습니다.

## which-key.nvim

[which-key.nvim](https://github.com/folke/which-key.nvim) v3는 각 매핑의 `desc`를 자동으로 읽습니다. `<leader>t` 그룹 이름과 아이콘을 지정하려면 which-key 옵션에 `spec`을 추가하면 됩니다.

```lua
-- lua/plugins/pretest.lua
return {
  {
    "skrewbar/pretest.nvim",
    cmd = "Pretest",
    opts = {},
    keys = {
      -- ... 위와 같은 keys ...
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

`optional = true`를 사용하면 기존 which-key spec에 병합됩니다. lazy.nvim을 쓰지 않는다면 같은 테이블을 `require("which-key").add({ ... })`에 넘기면 됩니다.

## 설치 확인

임의의 `.cpp` 또는 `.py` 파일을 열고 `:Pretest toggle`을 실행합니다. `Local: <파일명>`이 제목인 사이드바가 나타나야 합니다.

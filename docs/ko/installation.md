[English](../installation.md) | **한국어**

# 설치

pretest.nvim은 Neovim 0.10+ 외에 런타임 의존성이 없는 순수 Lua 플러그인입니다. 아무 플러그인 매니저로 설치한 뒤 `require("pretest").setup()`을 호출하면 됩니다 (lazy.nvim은 `opts`를 통해 자동으로 호출합니다).

## 요구 사항

- Neovim 0.10+ \
  `vim.system`, `vim.fs`, `vim.uv`를 사용합니다.
- (Windows) `md5`, `openssl`, `md5sum`중 하나 \
  `.prob` 파일 이름 생성에 사용됩니다. \
  Git for Windows가 설치되어 있는 경우 `usr\bin`에 있는 `md5sum`과 `openssl`를 사용하면 됩니다.
- (선택) [Nerd Font](https://www.nerdfonts.com/) \
  기본 [`empty_line_marker`](configuration.md#empty_line_marker)가 Nerd Font 글리프이므로 터미널 글꼴이 Nerd Font가 아니라면 바꿔 주세요.

## lazy.nvim

```lua
-- lua/plugins/pretest.lua
return {
  "skrewbar/pretest.nvim",
  cmd = "Pretest",
  opts = {}, -- configuration.md 참고
  keys = {
    { "<leader>j", "<cmd>Pretest<cr>", desc = "Pretest" },
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

vim.keymap.set("n", "<leader>j", "<cmd>Pretest<cr>", { desc = "Pretest" })
```

`:Pretest`를 실행하면 UI를 열 수 있습니다. UI가 열려있는 경우에는 커서가 소스와 UI 헤더 사이를 이동합니다. 나머지 동작은 UI 키(UI에서 `?`로 확인할 수 있습니다. [UI 키](commands.md#ui-keys) 참고)나 `:Pretest <subcommand>`로 실행할 수 있습니다. UI 안에서 쓰는 키는 별도 설정인 [`ui_keys`](configuration.md#ui_keys)에서 바꿀 수 있습니다.

## which-key.nvim

[which-key.nvim](https://github.com/folke/which-key.nvim) v3는 각 매핑의 `desc`를 자동으로 읽습니다. UI 키도 `desc`가 붙은 버퍼 로컬 매핑이므로, 따로 설정하지 않아도 pretest UI 안에서 which-key에 표시됩니다. 아이콘을 지정하려면 which-key 옵션에 `spec`을 추가하면 됩니다. `real = true` 아래의 항목은 해당 버퍼 로컬 키맵이 있을 때만 표시됩니다([UI 키](commands.md#ui-keys) 참고).

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
        -- Pretest UI 버퍼 키 (버퍼 로컬 키맵이 있을 때만 표시)
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

`optional = true`를 사용하면 기존 which-key spec에 병합됩니다. lazy.nvim을 쓰지 않는다면 같은 테이블을 `require("which-key").add({ ... })`에 넘기면 됩니다. [`ui_keys`](configuration.md#ui_keys)로 UI 키를 바꿨다면 `real = true` 블록도 같이 맞춰 주세요.

## 설치 확인

임의의 `.cpp` 또는 `.py` 파일을 열고 `:Pretest`를 실행합니다. `Local: <파일명>`이 제목인 사이드바가 나타나야 합니다.

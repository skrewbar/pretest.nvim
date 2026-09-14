[English](README.md) | **한국어**

# pretest.nvim

Neovim에서 테스트케이스를 실행하고 결과를 확인할 수 있는 플러그인입니다.

![pretest.nvim demo](demo.gif)

## 주요 기능

- **언어 설정** \
  기본적으로 C++과 Python을 지원하며, `languages` config을 통해 설정을 추가/수정할 수 있습니다.
- 실행 중에 레이아웃을 **사이드바**와 **플로팅** 사이에서 전환할 수 있습니다.
- **Competitive Companion 연동** \
  현재 파일에 문제 하나를 받거나, 문제마다 새 파일을 만들거나, 대회 전체를 한 번에 생성할 수 있습니다.
- **버퍼 연동 UI** \
  소스 파일 사이를 이동하면 UI도 해당 문제로 자동 전환되고, 파일별 결과는 그대로 유지됩니다.
- **안전한 파일 이동** \
  `:Pretest rename` / `:Pretest move`가 `.prob` 파일과 컴파일된 바이너리를 소스와 함께 옮깁니다.

## 요구 사항

- [Neovim](https://neovim.io/) 0.10 이상
- (Windows) `PATH`에 `md5`, `openssl`, `md5sum` 중 하나 \
  Git for Windows가 `C:\Program Files\Git`에 설치되어 있는 경우 `C:\Program Files\Git\usr\bin`를 `PATH`에 추가하면 됩니다.

## 빠른 시작

[lazy.nvim](https://github.com/folke/lazy.nvim)으로 설치합니다. 다른 플러그인 매니저는 [설치](docs/ko/installation.md)를 참고해 주세요.

```lua
{
  "skrewbar/pretest.nvim",
  cmd = "Pretest",
  opts = {}, -- docs/ko/configuration.md 참고
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

소스 파일에서:

1. `<leader>ta` 혹은 `:Pretest add`를 실행하면 빈 테스트케이스가 추가된 UI가 열리고 커서가 **Input**에 놓입니다.
2. Input 섹션을 채우고 `<Tab>`으로 **Expected**로 이동해 기대 출력을 입력한 뒤 `:w`로 저장합니다.
3. `R`(전체 실행) 또는 `r`(현재 케이스 실행)을 누릅니다. 헤더에 결과가 표시되고 **Output**에 프로그램 출력이 나타납니다.
4. `<C-n>` / `<C-p>`로 테스트케이스를 이동하고, `q`로 UI를 닫습니다.

직접 입력하는 대신 `:Pretest receive`를 실행하고 문제 페이지에서 Competitive Companion 버튼을 눌러도 됩니다. [Competitive Companion](docs/ko/competitive-companion.md) 문서를 참고하세요.

## 문서

- [설치](docs/ko/installation.md)
- [사용법](docs/ko/usage.md)
- [명령어](docs/ko/commands.md)
- [설정](docs/ko/configuration.md)
- [Competitive Companion](docs/ko/competitive-companion.md)

## `.prob` 파일

테스트케이스, 문제 이름, 제한은 소스 파일과 같은 위치의 `.pretest/.{파일명}_{md5}.prob`(또는 `save_dir` 아래)에 JSON으로 저장됩니다. 이 형식은 VS Code 확장 [Competitive Programming Helper](https://github.com/agrawal-d/cph)가 쓰는 `.prob` 파일과 호환되며, pretest가 사용하지 않는 필드도 보존됩니다. 자세한 내용은 [사용법 → 파일 저장 위치](docs/ko/usage.md#파일-저장-위치)를 참고하세요.

## 참고한 프로젝트

- [CompetiTest.nvim](https://github.com/xeluxee/competitest.nvim)
- [Competitive Programming Helper](https://github.com/agrawal-d/cph)

## 라이선스

[Apache License 2.0](LICENSE). [NOTICE](NOTICE)를 참고하세요.

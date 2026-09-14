[English](../configuration.md) | **한국어**

# 설정

`require("pretest").setup()`에 테이블을 넘깁니다 (lazy.nvim에서는 `opts`). 모든 키는 선택 사항이며 기본값 위에 deep-merge되므로 빠진 사항은 기본값으로 대체됩니다. 리스트(`args`, 여러 키를 가진 `ui_keys` 값, `extensions`)는 병합되지 않고 통째로 교체되므로, 하나를 바꿀 때는 리스트 전체를 적어야 합니다.

## 기본값

```lua
require("pretest").setup({
  -- .prob 파일과 바이너리 위치. nil → "{src_dir}/.pretest"
  save_dir = nil,

  -- 레이아웃 ------------------------------------------------------------
  ui = "sidebar", -- "sidebar" | "float"
  sidebar_position = "right", -- "left" | "right"
  -- 크기: 1보다 작은 경우 비율, 1보다 큰 경우 셀 개수
  sidebar_width = 40, -- 셀 40개
  sidebar_min_width = nil,
  sidebar_max_width = nil,
  float_width = 0.6, -- 가로의 60%
  float_height = 0.8,
  float_min_width = 30,
  float_max_width = nil,
  float_min_height = 16,
  float_max_height = nil,
  -- 섹션의 상대 높이
  sidebar_sections = { header = 1, input = 1, expected = 1, output = 1 },
  float_sections = { header = 1, input = 1, expected = 1, output = 1 },
  show_header_hints = true,

  -- 기본 제한 --------------------------------------------------
  default_time_limit = 3000, -- ms
  default_memory_limit = 1024, -- MB; 0이면 MLE 끄기

  -- pretest UI 키 ---------------------------------------------------
  ui_keys = {
    next_case = "<C-n>",
    prev_case = "<C-p>",
    next_section = "<Tab>",
    prev_section = "<S-Tab>",
    close = "q",
    stop = { "<C-c>", "s" },
    run_all = "<S-CR>",
    run_one = "<CR>",
    run_all_no_compile = "g<S-CR>",
    run_one_no_compile = "g<CR>",
  },

  -- 언어 -------------------------------------------
  languages = {
    cpp = {
      extensions = { "cpp", "cc", "cxx" },
      compile = { exec = "g++", args = { "-o", "$bin", "$src" } },
      run = { exec = "$bin", args = {} },
    },
    python = {
      extensions = { "py" },
      run = { exec = "python3", args = { "$src" } },
    },
  },

  -- Competitive Companion ------------------------------------------------
  companion = {
    port = 27121,
    listen_on_setup = false,
    extension = "cpp",
    template = nil, -- "path/to/template.cpp" 또는 { cpp = "...", py = "..." }
    problem_path = "{cwd}/{problem}.{ext}",
    contest_dir = "{cwd}",
    contest_problem_path = "{file}.{ext}",
    prompt_path = true,
    open = true, -- true인 경우 receive 후 버퍼 open
    replace_testcases = true,
  },
})
```

## `save_dir`

`nil`(기본값)이면 아티팩트를 각 소스 옆 `{src_dir}/.pretest/`에 둡니다. 경로를 지정하면(`~`와 환경 변수가 확장됩니다) 모든 `.prob` 파일과 바이너리를 해당 위치에 저장합니다. 저장되는 파일 이름 규칙은 [사용법 → 파일 저장 위치](usage.md#파일-저장-위치)를 참고하세요.

## 레이아웃

### `ui`, `sidebar_position`

초기 레이아웃과 사이드바가 열리는 방향입니다. `:Pretest toggle_layout`은 현재 Neovim 세션 동안의 레이아웃을 바꿉니다.

### 크기

`sidebar_width`, `float_width`, `float_height`와 `*_min_*` / `*_max_*` 의 값은 숫자입니다. `(0, 1]` 사이 값은 에디터 너비(너비 옵션) 또는 높이(높이 옵션)에 대한 비율이고, `1`보다 큰 값은 셀 개수입니다. 기본 크기를 먼저 계산하고 min/max로 제한한 뒤 에디터 크기로 다시 제한합니다. 제한을 두지 않으려면 `nil`로 두면 됩니다.

```lua
sidebar_width = 0.3, sidebar_min_width = 44, -- 열의 30%, 단 44보다 좁아지지 않음
float_height = 40,                            -- 정확히 40줄 (테두리 포함)
```

사이드바 너비는 고정(`winfixwidth`)되어 다른 분할 창이 밀어내지 않습니다. `float_height`는 테두리를 포함한 플로팅 창 기둥의 전체 높이입니다.

### `sidebar_sections`, `float_sections`

**헤더**, **Input**, **Expected**, **Output**의 상대 가중치입니다. 각 섹션은 최소 3줄을 차지하고, 사이드바에서는 공간이 있으면 헤더가 테스트케이스 목록에 맞게 늘어납니다. **Runtime Error**와 **Stderr**는 표시될 때만 고정 공간(각각 최대 4줄, 8줄)을 차지합니다.

```lua
sidebar_sections = { header = 1, input = 2, expected = 2, output = 3 },
```

### `show_header_hints`

헤더에 키 힌트를 보여줄 지 결정합니다. `:Pretest toggle_hints`를 사용하면 이번 세션 동안만 이를 토글합니다. 힌트는 실제 `ui_keys` 설정으로 렌더링되므로 키를 바꿔도 그에 맞게 표시됩니다.

## `ui_keys`

pretest UI 안에서만 매핑되는(버퍼 로컬) 키입니다.

| 값 | 의미 |
|----|------|
| `"<C-j>"` | 키 하나, 기본 모드 |
| `{ "<C-j>", modes = "n" }` | 키 하나, 모드 명시 (`"n"`, `"i"`, 또는 리스트) |
| `{ "q", "<Esc>" }` | 키 여러 개 |
| `{ { "<Tab>", modes = "n" }, "<C-l>" }` | 혼합 |
| `false` | 바인딩 해제 |

기본 모드는 `next_case`, `prev_case`, `next_section`, `prev_section`은 **Normal/Insert**, 나머지는 Normal 모드에서만 적용됩니다. 동작을 지정하면 그 동작의 기본값을 완전히 대체하고, 지정하지 않은 동작은 기본값을 유지합니다.

```lua
ui_keys = {
  next_section = { "<Tab>", modes = "n" }, -- Insert 모드에서 <Tab> 바인딩 해제
  prev_section = { "<S-Tab>", modes = "n" },
  close = { "q", "<Esc>" },
  run_all_no_compile = false,
},
```

`:w`(Input/Expected 저장), 헤더 커서로 케이스 선택, `:q`로 UI 닫기는 내장 동작이며 `ui_keys`에 포함되지 않습니다.

> `<CR>`과 `<S-CR>`를 구분하지 못하는 터미널 에뮬레이터를 사용하는 경우 다른 키로 변경해 주세요.

## `languages`

언어 컴파일/실행 방법을 수정하거나 새로운 언어를 추가할 수 있습니다.

기본적인 형식은 아래와 같습니다.

```lua
languages = {
  <filetype> = {
    extensions = { "ext", ... }, -- (선택) 이 filetype으로 취급할 추가 확장자
    compile = {                  -- (선택) 인터프리터 언어는 생략
      exec = "compiler",         -- 문자열 또는 function(ctx) -> string
      args = { ... },            -- 문자열 리스트 또는 function(ctx) -> string[]
    },
    run = {
      exec = "program",          -- 필수
      args = { ... },
    },
  },
}
```

- `exec`는 셸을 거치지 않고 직접 실행됩니다. 따라서 따옴표 처리, 글로빙, `~`, `&&`는 동작하지 않습니다.
- `exec`와 `args`의 각 원소에서 값이 `$src`이면 소스의 절대 경로로, `$bin`이면 바이너리 경로로 치환됩니다. 문자열 안에 포함된 경우(예: `"--out=$bin"`)는 치환하지 **않습니다**. 이러한 기능이 필요한 경우에는 함수를 사용하세요.
- 함수는 `ctx = { src_path = "...", bin_path = "..." }`를 받아 문자열(`exec`) 또는 리스트(`args`)를 반환해야 합니다. 반환값은 그대로 사용됩니다.
- `bin_path` 혹은 `$bin`을 꼭 사용할 필요는 없습니다. 다른 위치를 사용해도 됩니다.
- 컴파일과 실행 모두 소스 파일의 디렉터리를 작업 디렉터리로 사용합니다.

### 버퍼가 어떤 언어를 쓰는지

pretest는 먼저 버퍼의 `filetype`을 확인합니다. 그것이 `languages`의 키가 아니면 경로에 `vim.filetype.match`를 시도하고, 그다음 `extensions` 목록을, 마지막으로 확장자와 같은 이름의 키를 찾습니다. Competitive Companion이 만드는 파일은 `companion.extension`을 사용하므로, UI가 자동으로 열리려면 그 확장자가 설정된 언어에 대응해야 합니다.

### 예시

- C++의 컴파일러와 플래그 변경

```lua
languages = {
  cpp = {
    compile = {
      exec = "clang++",
      args = { "-std=c++20", "-O2", "-Wall", "-fsanitize=address,undefined", "-o", "$bin", "$src" },
    },
  },
},
```

- CPython 대신 PyPy 사용

```lua
languages = { python = { run = { exec = "pypy3" } } },
```

- C와 Rust 추가

```lua
languages = {
  c = {
    extensions = { "c" },
    compile = { exec = "gcc", args = { "-O2", "-o", "$bin", "$src" } },
    run = { exec = "$bin" },
  },
  rust = {
    extensions = { "rs" },
    compile = { exec = "rustc", args = { "-O", "-o", "$bin", "$src" } },
    run = { exec = "$bin" },
  },
},
```

- Java 추가

```lua
languages = {
  java = {
    extensions = { "java" },
    compile = {
      exec = "javac",
      args = function(ctx)
        return { "-d", vim.fs.dirname(ctx.bin_path), ctx.src_path }
      end,
    },
    run = {
      exec = "java",
      args = function(ctx)
        return { "-cp", vim.fs.dirname(ctx.bin_path), vim.fn.fnamemodify(ctx.src_path, ":t:r") }
      end,
    },
  },
},
```

셸 기능이 필요할 때는 셸을 통해 실행합니다. 예를 들어 Linux에서 스택 크기를 키우는 경우:

```lua
run = {
  exec = "sh",
  args = function(ctx)
    return { "-c", "ulimit -s 262144 && exec " .. vim.fn.shellescape(ctx.bin_path) }
  end,
},
```

## Competitive Companion

`companion` 테이블은 별도 문서에서 다룹니다: [Competitive Companion](competitive-companion.md).

## 하이라이트 그룹

모든 그룹은 `default = true`로 정의되어 컬러스킴이나 `vim.api.nvim_set_hl(0, "PretestAC", { ... })`로 덮어쓸 수 있습니다.

| 그룹 | 기본 링크 | 용도 |
|------|-----------|------|
| `PretestAC` | `DiagnosticOk` | `AC` 결과와 전부 맞았을 때의 요약 |
| `PretestWA` | `DiagnosticError` | `WA` |
| `PretestRE` | `DiagnosticError` | `RE` |
| `PretestCE` | `DiagnosticError` | `CE` |
| `PretestTLE` | `DiagnosticWarn` | `TLE` |
| `PretestMLE` | `DiagnosticWarn` | `MLE` |
| `PretestStopped` | `DiagnosticWarn` | `Stopped` |
| `PretestRunning` | `DiagnosticInfo` | `Running`, `Compiling` |
| `PretestPending` | `Comment` | 결과가 없는 케이스 |
| `PretestCurrent` | `Title` | 선택된 케이스의 `[n]` 표시 |
| `PretestKey` | `Special` | 헤더 힌트의 키 이름 |
| `PretestHint` | `Comment` | 힌트 설명 |
| `PretestSep` | `FloatBorder` 전경색 | 헤더 구분선과 `│` |

pretest 버퍼는 `filetype=pretest`이고 이름이 `pretest://input#<bufnr>` 형태이므로, 상태줄, 자동 포매터, 자동완성 플러그인에서 제외할 때 활용할 수 있습니다.

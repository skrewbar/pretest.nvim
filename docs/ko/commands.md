[English](../commands.md) | **한국어**

# 명령어

pretest의 모든 동작은 `:Pretest <subcommand> [argument]`로 실행할 수 있습니다.

```vim
:Pretest toggle
:Pretest toggle_layout
:Pretest toggle_hints
:Pretest run [index ...]
:Pretest run_current
:Pretest run_no_compile [index ...]
:Pretest run_current_no_compile
:Pretest stop
:Pretest add
:Pretest edit [index]
:Pretest delete [index]
:Pretest edit_name
:Pretest edit_limits
:Pretest rename <name>
:Pretest move <path>
:Pretest receive [problem | contest | persistently | stop | status]
```

문제를 다루는 명령(`run*`, `add`, `edit*`, `delete`, `rename`, `move`, `receive`)은 지원되는 *소스 파일*이 필요합니다. [`languages`](configuration.md#languages)에 설정된 filetype의 버퍼에서 실행하거나, 세션이 열려 있는 동안 pretest UI 창에서 실행해야 합니다.

## UI

| 명령 | 설명 |
|------|------|
| `toggle` | 현재 소스 파일의 UI를 열거나, 열려 있으면 닫습니다. 열 때 **Input**에 포커스합니다. |
| `toggle_layout` | `sidebar`와 `float`를 전환합니다. UI가 닫혀 있어도 동작하며(다음에 열 때 적용) Neovim 세션 동안 기억됩니다. |
| `toggle_hints` | UI 헤더의 키 힌트 줄을 보이거나 숨깁니다. 세션 동안 기억되며 초기값은 `show_header_hints`입니다. |

## 실행

| 명령 | 설명 |
|------|------|
| `run [index ...]` | 언어에 `compile` 단계가 있으면 컴파일한 뒤, 모든 테스트케이스 또는 지정한 1-based 번호만 실행합니다(`:Pretest run 2 4`). |
| `run_current` | 필요하면 컴파일한 뒤 선택된 테스트케이스를 실행합니다. |
| `run_no_compile [index ...]` | `run`과 같지만 컴파일을 건너뛰고 기존 바이너리를 사용합니다. |
| `run_current_no_compile` | 컴파일 없는 `run_current`입니다. |
| `stop` | 진행 중인 컴파일러나 프로그램을 종료합니다. 현재 케이스는 `Stopped`가 되고 대기 중인 케이스는 시작하지 않습니다. 컴파일 중에 중단하면 헤더의 테스트케이스 개수 옆에 `Stopped`가 표시됩니다. |

실행 명령은 소스 버퍼에 저장되지 않은 변경이 있으면 먼저 저장하고, UI가 닫혀 있으면 엽니다.

## 테스트케이스

| 명령 | 설명 |
|------|------|
| `add` | 빈 테스트케이스를 목록의 맨 마지막에 추가하고 선택합니다. UI가 닫혀있다면 엽니다. |
| `edit [index]` | UI를 열고 **Input**에 포커스합니다. `index`가 있으면 해당 테스트케이스를 선택합니다. |
| `delete [index]` | UI에서 선택된 테스트케이스 또는 `index`번 테스트케이스를 삭제합니다. 실행 중이면 실행을 멈춘 뒤 삭제합니다. |
| `edit_name` | 문제 이름을 입력받아 변경합니다. |
| `edit_limits` | 시간 제한(ms)과 메모리 제한(MB)을 각각 입력받아 변경합니다. 메모리 제한을 `0`으로 지정하면 메모리 제한을 검사하지 않습니다. |

Input과 Expected는 케이스 전환, 실행, 닫기, 종료 전 자동 저장됩니다.

Input과 Expected는 해당 창에서 직접 편집하고 `:w`로 저장할 수 있습니다.

## 소스 파일

| 명령 | 설명 |
|------|------|
| `rename <name>` | 소스 파일 이름을 바꿉니다. 상대 경로는 소스가 위치한 디렉터리 기준입니다. |
| `move <path>` | 소스 파일을 옮깁니다. 상대 경로는 Neovim의 cwd 기준입니다. `/`로 끝나거나 기존 디렉터리를 가리키는 경로면 현재 파일명을 유지합니다. |

두 명령은 버퍼를 저장한 뒤 파일과 버퍼 이름을 바꾸고, `.prob` 파일과 컴파일된 바이너리를 새 경로에 맞게 옮겨 줍니다.

옮기려는 경로에 이미 파일이 있거나 대응되는 `.prob`이 이미 있는 경우, 확장자가 설정된 언어가 아닌 경우에는 명령어가 실행되지 않습니다.

## Competitive Companion

| 명령 | 설명 |
|------|------|
| `receive` | 문제 하나를 수신해 테스트케이스, 이름, 제한을 **현재 파일**의 `.prob`에 덮어씁니다. |
| `receive problem` | 문제 하나를 수신해 새 소스 파일을 만들고(`companion.template`이 있으면 그 내용으로) 엽니다. |
| `receive contest` | 대회 전체를 수신해 `companion.contest_dir` 아래에 문제마다 소스 파일 하나를 만듭니다. |
| `receive persistently` | 지속적으로 수신합니다. 수신한 태스크가 둘 이상이면 대회로 처리하고, 하나인 경우 *This file* / *Problem*을 물어봅니다. |
| `receive stop` | 수신을 중지합니다. |
| `receive status` | 수신 중인지, 어느 모드인지, 어느 포트인지 알려 줍니다. |

자세한 내용은 [Competitive Companion](competitive-companion.md)을 참고하세요.

## UI 키

pretest UI에서 동작하는 기본 키입니다. 전부 [`ui_keys`](configuration.md#ui_keys)로 바꿀 수 있습니다.

| 키 | 모드 | 동작 |
|----|------|------|
| `<C-n>` / `<C-p>` | Normal, Insert | 다음 / 이전 테스트케이스 |
| `<Tab>` / `<S-Tab>` | Normal, Insert | 다음 / 이전 섹션 |
| `<S-CR>` | Normal | 모든 테스트케이스 실행 (`run`) |
| `<CR>` | Normal | 현재 테스트케이스 실행 (`run_current`) |
| `g<S-CR>` | Normal | 컴파일 없이 전체 실행 (`run_no_compile`) |
| `g<CR>` | Normal | 컴파일 없이 현재 케이스 실행 (`run_current_no_compile`) |
| `<C-c>` / `s` | Normal | 중지 (`stop`) |
| `q` | Normal | UI 닫기 |

키맵으로 바꿀 수 없는 추가 동작:

- 헤더의 테스트케이스 줄로 커서를 옮기면 그 케이스가 선택됩니다.
- pretest 창 어디서든 `:q`, `:close`, `<C-w>c`는 편집 내용을 저장한 뒤 UI 전체를 닫습니다.

`<Tab>`과 `<C-n>`/`<C-p>`는 Insert 모드에도 바인딩되어 있습니다. Insert 모드 기본 동작을 되살리려면 해당 바인딩에 `modes = "n"`을 지정하면 됩니다.

자세한 내용은 [`ui_keys`](configuration.md#ui_keys)를 참고하세요.

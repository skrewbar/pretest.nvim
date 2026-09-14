[English](../usage.md) | **한국어**

# 사용법

이 문서는 일반적인 작업 흐름을 따라갑니다. UI 열기, 테스트케이스 입력, 실행, 채점 결과 읽기, 그리고 pretest가 파일을 어디에 두는지까지 다룹니다. 명령과 키의 전체 목록은 [명령어](commands.md)를 참고하세요.

## UI 열기

[`languages`](configuration.md#languages)에 설정된 filetype(기본값은 `cpp`, `python`)의 소스 파일을 열고 `:Pretest toggle` 혹은 키맵을 등록했다면 `<leader>tu`로 UI를 엽니다.

pretest는 해당 소스의 `.prob` 파일을 읽어 오거나 없으면 `Local: <파일명>`이라는 빈 문제를 만들고 UI를 열어 커서를 **Input**에 둡니다. 다시 `:Pretest toggle`을 실행하거나, pretest 창 안에서 `q`를 누르거나, pretest 창 중 하나에서 `:q`를 실행하면 UI 전체가 닫힙니다. UI를 닫아도 결과와 편집 내용은 Neovim 세션이 끝날 때까지 그 소스 파일에 붙어 있습니다.

`:Pretest toggle_layout`은 언제든 사이드바와 플로팅 레이아웃을 전환하고, `:Pretest toggle_hints`는 헤더의 키 힌트를 보이거나 숨깁니다.

## 화면 구성

사이드바 레이아웃(기본값, 오른쪽)은 아래 섹션을 세로로 쌓습니다. 플로팅 레이아웃은 같은 섹션을 화면 중앙에 플로팅 창 기둥으로 보여 줍니다.

```text
┌ Pretest ─────────────────────────────┐
│ Local: main                          │  문제 이름
│ TL 3000ms │ ML 1024MB                │  시간 | 메모리 제한   
│ ──────────────────────────────────── │
│ Testcases 1/3                        │  맞은 개수 / 전체
│  1  AC      12ms                     │
│  2  WA       9ms                     │  
│ [3] RE      15ms  SIGSEGV            │  선택된 케이스는 [n]처럼 대괄호로 표시
│                                      │
│ <C-n>/<C-p> switch  :w save  q close │  키 힌트 (toggle_hints로 토글)
│ R run-all  r run-one  …              │
├ Input ───────────────────────────────┤
│ 3                                    │  입력 / 수정 가능
│ 1 2 3                                │
├ Expected ────────────────────────────┤
│ 6                                    │  예상 출력 / 수정 가능
├ Output ──────────────────────────────┤
│ 6                                    │  현재 케이스의 stdout
├ Runtime Error ───────────────────────┤
│ segmentation fault (SIGSEGV)         │  현재 결과가 RE일 때만
├ Stderr ──────────────────────────────┤  stderr가 비어 있지 않을 때만
│ ...                                  │
└──────────────────────────────────────┘
```

- **헤더**는 모든 테스트케이스의 결과, 실행 시간, 그리고 `RE`/`MLE`의 경우 짧은 원인을 나열합니다. 케이스를 나타내는 줄 위로 커서를 옮기면 그 케이스가 선택됩니다.
- `<C-n>/C-p>`로도 케이스를 선택할 수 있습니다.
- **Input** / **Expected**는 편집 가능한 버퍼입니다(`filetype=pretest`).
- 완전히 빈 줄은 `↵`, 탭은 `>`, 줄 끝 공백은 `-`로 표시됩니다.
- **Output**은 현재 케이스에서 프로그램이 stdout에 출력한 내용을 그대로 보여 줍니다.
- **Runtime Error**는 결과가 `RE`일 때만 나타나며 런타임 에러의 원인을 설명합니다. 시그널 이름, 종료 코드, 또는 stderr에서 파싱한 힌트(`ZeroDivisionError`, `AddressSanitizer`, assertion 메시지 등)입니다.
- **Stderr**는 보여 줄 내용이 있을 때만 나타납니다. 프로그램의 stderr, 또는 `CE`일 때 컴파일러 출력입니다.

`<Tab>` / `<S-Tab>`은 Normal/Insert 모드에서 보이는 섹션 사이로 포커스를 순환합니다.

## 테스트케이스

### 추가와 편집

`:Pretest add` 혹은 `<leader>ta`로 테스트케이스를 추가할 수 있습니다.

Input/Expected의 편집 내용은 다음 시점에 `.prob` 파일에 기록됩니다:

- 두 버퍼 중 하나에서 `:w`를 실행할 때
- 다른 케이스로 전환하기 전, 테스트케이스를 실행하기 전, UI를 닫을 때, Neovim을 종료할 때

앞뒤의 빈 줄은 입력한 그대로 저장됩니다. 비교할 때 줄 끝 공백을 무시하므로 채점에는 영향을 주지 않습니다([채점 결과](#채점-결과) 참고).

### 이동

| 동작 | 방법 |
|------|------|
| 다음 / 이전 케이스 | pretest UI 위에서 `<C-n>` / `<C-p>` (Normal/Insert 모드) |
| *n*번 케이스로 이동 | `:Pretest edit n`, 또는 헤더의 *n*번 줄로 커서 이동 |
| 현재 케이스로 UI 포커스 | `:Pretest edit` |

### 삭제

`:Pretest delete`는 현재 케이스를, `:Pretest delete 3`은 3번 케이스를 삭제합니다. 번호가 밀리기 때문에 모든 케이스의 결과가 지워집니다.

### 이름과 제한

헤더는 읽기 전용이므로 명령어로 변경해야 합니다.

```vim
:Pretest edit_name     " 헤더에 표시되는 문제 이름
:Pretest edit_limits   " 시간 제한(ms), 그다음 메모리 제한(MB, 0이면 MLE 끄기)
```

새 로컬 문제는 `default_time_limit` `default_memory_limit`으로 설정됩니다. Competitive Companion으로 받은 문제는 저지의 제한을 그대로 가져옵니다.

## 실행

| 명령 | UI 키 | 동작 |
|------|-------|-----------|
| `:Pretest run` | `R` | 컴파일 후 모든 테스트케이스 실행 |
| `:Pretest run 1 3` | | 컴파일 후 1번과 3번 케이스 실행 |
| `:Pretest run_current` | `r` | 컴파일 후 현재 케이스 실행 |
| `:Pretest run_no_compile [n...]` | `<C-S-r>` | 컴파일을 건너뛰고 기존 바이너리로 전체(또는 지정한) 케이스 실행 |
| `:Pretest run_current_no_compile` | `<C-r>` | 컴파일을 건너뛰고 현재 케이스 실행 |
| `:Pretest stop` | `s` | 진행 중인 컴파일이나 실행을 종료 |

선택된 케이스는 `Pending`이 되고, 컴파일러가 도는 동안 헤더에 `Compiling`이 표시된 뒤, 각 케이스가 순서대로 실행되며 끝나는 대로 결과가 채워집니다.

프로세스는 소스 파일의 디렉터리를 작업 디렉터리로 실행되고, 케이스 입력을 stdin으로 받으며, 시간 제한을 넘기면 종료됩니다. 컴파일 언어는 바이너리를 아티팩트 디렉터리에 씁니다([파일 저장 위치](#파일-저장-위치) 참고).

`no_compile` 계열 명령은 마지막으로 성공한 빌드를 재사용합니다.

## 채점 결과

| 결과 | 의미 |
|------|------|
| `AC` | 출력이 Expected와 일치 |
| `WA` | 출력이 Expected와 다름 |
| `TLE` | `timeLimit`ms 뒤에 강제 종료됨 |
| `MLE` | 최대 메모리가 `memoryLimit`MB를 초과 (프로세스 종료 후 판정. 원인 칸에 최대치 표시, 예: `MLE 21MB`) |
| `RE` | 0이 아닌 코드로 종료되었거나 시그널로 종료됨. 원인 칸에 `SIGSEGV`, `exit 1`, `ZeroDivisionError` 등 표시 |
| `CE` | 컴파일 실패. 컴파일러 출력은 **Stderr**에 표시 |
| `Stopped` | `:Pretest stop` / `s`로 중단됨 |
| `Pending` / `Running` | 대기 중 / 실행 중 |

출력을 비교할 때에는 다음과 같이 처리하고 비교합니다.

- 각 줄의 끝 공백 제거
- 마지막의 빈 줄 모두 제거
- `\r\n`을 `\n`으로 변경

**메모리**는 OS 도구로 측정한 최대 RSS로 판단합니다. 메모리 제한을 `0`으로 설정하면 메모리 제한을 끌 수 있습니다.

**런타임 에러**는 시그널(`SIGSEGV`, `SIGABRT`, `SIGFPE` 등)을 보여 주거나, 프로세스가 0이 아닌 코드로 정상 종료한 경우 stderr에서 파싱한 힌트를 보여 줍니다. sanitizer 보고(`ASan`, `UBSan`), `Assertion failed`, 또는 마지막 `Error:` / `Exception:` 줄(Python, Java)입니다. Windows에서는 `ACCESS_VIOLATION`, `STACK_OVERFLOW` 같은 NTSTATUS 코드를 인식합니다.

## 파일 전환

UI는 편집 중인 버퍼를 따라갑니다. 지원되는 다른 소스 파일로 이동하면 UI가 그 파일의 문제로 전환되고, 이전 파일에서 계산된 결과는 유지되어 돌아오면 복원됩니다. filetype이 설정되지 않은 일반 파일(Markdown 메모, `.txt` 입력 파일 등)로 이동하면 UI가 닫힙니다. 터미널, 도움말, 파일 탐색기, 플로팅 창 같은 특수 버퍼는 무시되므로 그것들을 쓰는 동안 UI는 열린 채로 유지됩니다.

## 소스 이름 변경 또는 이동

`.prob` 파일과 바이너리 이름은 소스의 절대 경로에서 만들어지므로, pretest 밖에서 파일 이름을 바꾸면 테스트케이스와의 연결이 끊어집니다. 대신 다음을 사용하세요:

```vim
:Pretest rename b.cpp          " 소스 디렉터리 기준 상대 경로
:Pretest move solutions/       " Neovim cwd 기준 상대 경로; 디렉터리면 파일명 유지
:Pretest move ../round2/b.cpp
```

두 명령 모두 필요하면 버퍼를 저장하고, 디스크의 파일과 버퍼 이름을 바꾸고, `.prob` 파일과 컴파일된 바이너리를 새 이름으로 옮깁니다. 기존 파일이나 기존 `.prob`을 덮어쓰거나 지원되지 않는 확장자로 옮기는 경우에는 실행되지 않습니다.

둘 다 `<Tab>`으로 파일 경로를 완성할 수 있습니다.

## 파일 저장 위치

pretest가 쓰는 모든 것은 소스 파일별 *아티팩트 디렉터리* 하나에 들어갑니다:

| `save_dir` | 아티팩트 디렉터리 | `.prob` 파일 | 바이너리 (컴파일 언어) |
|------------|-------------------|--------------|-------------------------|
| 미설정 (기본값) | `{src_dir}/.pretest/` | `.{basename}_{md5}.prob` | `{stem}.out` |
| 설정 | `{save_dir}/` | `.{basename}_{md5}.prob` | `{stem}_{md5[1:8]}.out` |

`{basename}`은 확장자를 포함한 파일 이름(`main.cpp`), `{stem}`은 확장자를 뺀 이름(`main`), `{md5}`는 소스 절대 경로의 MD5입니다.

`.prob` 파일은 CPH와 호환되므로 `.cph` 폴더의 이름을 `.pretest`로 변경하는 것으로 쉽게 migration할 수 있습니다.

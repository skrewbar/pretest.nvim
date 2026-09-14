[English](../competitive-companion.md) | **한국어**

# Competitive Companion

[Competitive Companion](https://github.com/jmerle/competitive-companion)은 문제 페이지를 파싱해 테스트케이스, 제한, 제목을 로컬 포트로 전송하는 브라우저 확장입니다.

이를 이용하면 Input, Expected, 시간/메모리 제한 등을 직접 입력하지 않고 자동으로 채울 수 있습니다.

## 준비

[Chrome](https://chromewebstore.google.com/detail/competitive-companion/cjnmckjndlpiamhfimnnjmnckgghkjbl) 또는 [Firefox](https://addons.mozilla.org/firefox/addon/competitive-companion/)용 확장을 설치합니다.

pretest는 기본적으로 `127.0.0.1:27121`을 수신합니다. 이 포트는 확장의 기본 포트 목록에 포함되어 있으므로 추가 설정이 필요하지 않습니다. `companion.port`를 변경한 경우에는 브라우저 확장 설정의 "Custom ports"에도 같은 포트를 추가해야 합니다.

## 수신

`:Pretest receive [mode]`로 수신을 시작한 뒤 문제 또는 대회 페이지에서 확장의 **+** 버튼을 누릅니다. `persistently`를 제외한 모드는 한 번 수신한 뒤 종료됩니다.

수신한 문제의 이름과 제한은 항상 `.prob`에 덮어씁니다.

### `receive` — 현재 파일

현재 소스 파일의 `.prob`에 테스트케이스, 이름, 제한을 기록하고 UI를 엽니다.

`.prob`에 테스트케이스가 이미 있는 경우 `replace_testcases`가 `true`(기본값)이면 교체하고, `false`이면 **Keep**(기존 케이스 뒤에 추가) / **Replace** / **Cancel** 중 선택합니다.

### `receive problem` — 새 파일 생성

`problem_path`에 소스 파일을 생성하고 `.prob`을 기록합니다. `template`이 설정되어 있으면 그 내용으로 파일을 채웁니다.

- `prompt_path = true`(기본값): 생성할 경로를 프롬프트로 확인합니다. 비워 두거나 `<Esc>`를 누르면 취소됩니다.
- `open = true`(기본값): 생성한 파일과 UI를 엽니다.
- 같은 경로에 파일이 이미 있으면 덮어쓸지 확인합니다.

### `receive contest` — 대회 전체

대회 페이지에서 **+**를 누르면 확장이 모든 문제를 하나의 배치로 보냅니다. pretest는 배치를 모두 받은 뒤 `contest_dir` 아래에 `contest_problem_path` 이름으로 문제별 소스 파일과 `.prob`을 생성합니다.

`prompt_path`와 `open`은 `receive problem`과 같이 동작합니다. 디렉터리를 한 번만 확인하고, 첫 문제만 엽니다.

### `receive persistently` — 지속 수신

`:Pretest receive stop`을 실행하거나 Neovim을 종료할 때까지 계속 수신합니다. 태스크가 둘 이상인 배치는 `contest`로 처리하고, 하나인 경우 **This file**(`receive`) / **Problem**(`receive problem`) / **Cancel** 중 선택합니다.

`companion.listen_on_setup = true`로 설정하면 `setup()`이 실행될 때 자동으로 이 모드로 시작합니다. lazy.nvim에서는 `lazy = false`가 필요합니다([설치](installation.md#lazynvim) 참고).

### 상태 확인과 중지

```vim
:Pretest receive status
:Pretest receive stop
```

## 옵션

기본값은 [설정](configuration.md#기본값)을 참고하세요.

| 옵션 | 설명 |
|------|------|
| `port` | `127.0.0.1`의 TCP 포트 |
| `listen_on_setup` | `setup()`에서 `receive persistently`를 시작 |
| `extension` | `problem` / `contest`가 생성하는 파일의 확장자(점 없이). 설정된 언어에 대응하지 않으면 파일과 `.prob`은 생성되지만 UI는 열리지 않습니다 |
| `template` | 새 소스 파일의 초기 내용으로 사용할 파일 경로. 확장자별로 다르게 지정하려면 `{ cpp = "~/cp/template.cpp", py = "~/cp/template.py" }` 형태로 지정 |
| `problem_path` | `receive problem`이 파일을 생성할 경로 |
| `contest_dir` | `receive contest`가 파일을 생성할 디렉터리. 배치의 첫 태스크로 평가 |
| `contest_problem_path` | 대회의 각 문제 파일 경로. `contest_dir` 기준 상대 경로이며 하위 디렉터리를 포함할 수 있음 |
| `prompt_path` | 파일을 생성하기 전에 경로를 프롬프트로 확인 |
| `open` | 생성한 파일(대회는 첫 파일)과 UI를 열기 |
| `replace_testcases` | `true`: 기존 테스트케이스를 교체. `false`: Keep / Replace / Cancel 선택 |

## 경로 템플릿

`problem_path`, `contest_dir`, `contest_problem_path`에는 `{placeholder}`를 사용할 수 있습니다. 값은 다음과 같이 정리됩니다.

- 공백은 `_`로 변경
- 글자, 숫자, `_`, `-` 외의 문자는 `_`로 변경
- 연속된 `_`는 하나로 합침

다음 태스크를 수신한 경우

```json
{ "name": "G. Castle Defense", "group": "Codeforces - Educational Round 170" }
```

각 placeholder의 값은 다음과 같습니다.

| Placeholder | 값 | 설명 |
|-------------|----|------|
| `{cwd}` | `/home/me/cf` | Neovim의 cwd |
| `{home}` | `/home/me` | 홈 디렉터리 |
| `{index}` | `G` | 제목의 문제 번호(`A`, `B1`, `1` 등). 없으면 빈 문자열 |
| `{slug}` | `Castle_Defense` | 문제 번호를 제외한 제목 |
| `{problem}` | `G_Castle_Defense` | `{index}_{slug}`. 문제 번호가 없으면 `{slug}` |
| `{file}` | `G` | `{index}`. 문제 번호가 없으면 `{slug}` |
| `{name}` | `G_Castle_Defense` | 제목 전체 |
| `{task_class}` | `GCastleDefense` | 확장이 제안한 Java 클래스 이름. 없으면 `{name}` |
| `{judge}` | `Codeforces` | `group`에서 ` - ` 앞부분 |
| `{contest}` | `Educational_Round_170` | `group`에서 ` - ` 뒷부분. ` - `가 없으면 `unknown_contest` |
| `{group}` | `Codeforces_-_Educational_Round_170` | `group` 전체 |
| `{ext}` | `cpp` | `companion.extension` |

문제 번호는 제목이 `<번호><구분자><제목>` 형태일 때 인식하며, 구분자는 `.`, `-`, `:` 중 하나입니다(`G. Castle Defense`, `A - Welcome`, `1: Two Sum`).

문자열 대신 `function(task, ext) -> string`을 지정하면 수신한 태스크(`task.name`, `task.group`, `task.url`, `task.timeLimit` 등)로 경로를 직접 계산할 수 있습니다.

```lua
problem_path = function(task, ext)
  local judge = task.group:match("^(.-) %- ") or "misc"
  return vim.fs.joinpath(vim.fn.getcwd(), judge:lower(), task.name:sub(1, 1) .. "." .. ext)
end,
```

### 예시

대회마다 디렉터리를 만들고 문제 번호로 파일 이름 지정:

```lua
contest_dir = "{cwd}/{contest}",
contest_problem_path = "{file}.{ext}",
-- → ./Educational_Round_170/A.cpp, B.cpp, ...
```

저지 / 대회 / 문제 계층으로 저장:

```lua
problem_path = "{cwd}/{judge}/{contest}/{problem}.{ext}",
-- → ./Codeforces/Educational_Round_170/G_Castle_Defense.cpp
```

Python 템플릿으로 고정 디렉터리에 저장:

```lua
extension = "py",
template = "~/cp/template.py",
problem_path = "{home}/cp/{judge}/{problem}.{ext}",
```

## 문제 해결

**`cannot bind 127.0.0.1:27121 ...`** \
다른 프로세스가 포트를 사용 중입니다. 다른 프로그램의 수신을 중지하거나, `companion.port`와 확장의 "Custom ports"를 함께 변경해야 합니다. 한 번에 하나의 Neovim만 수신할 수 있습니다.

**+를 눌러도 아무 일이 없음** \
`:Pretest receive status`로 수신 중인지 확인합니다. 확장이 해당 사이트를 지원하지 않는 경우 아이콘이 빨갛게 표시됩니다.

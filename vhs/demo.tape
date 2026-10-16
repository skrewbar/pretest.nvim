# Hero demo for README: open the UI, add a case, hit WA, fix the source, rerun.
#
# Uses the operator's Neovim config as-is (<leader> = Space, g++-16 from
# languages.cpp), then :colorscheme tokyonight and vhs/keys.lua (key overlay).
# From the repository root:
#   vhs vhs/demo.tape
#
# Requires nvim, g++-16, and VHS (plus ttyd + ffmpeg).
# Companion receive is not recorded here — that needs a browser.
#
# VHS sends Shift+Enter as a plain Enter, so `<S-CR>` (run all) is typed as
# its CSI u sequence. The `Type@0ms "<ESC>[13;2u"` lines contain a literal
# ESC byte (0x1b) before `[13;2u`; keep it when editing this file.

Output vhs/demo.gif

Require nvim
Require "g++-16"
Require bash

Set Shell "bash"
Set FontSize 18
Set FontFamily "JetBrainsMono Nerd Font Mono"
Set Width 1920
Set Height 1080
Set Padding 16
Set Theme "tokyonight-storm"
Set TypingSpeed 75ms
Set Framerate 24
Set PlaybackSpeed 1.0
Set CursorBlink false

# --- setup (not recorded) ------------------------------------------------
Hide
Type `set -e`
Enter
Type `test -f lua/pretest/init.lua || { echo "run vhs from the pretest.nvim repo root" >&2; exit 1; }`
Enter
Type `export PRETEST_REPO="$PWD"`
Enter
Type `WORKDIR="$(bash "$PRETEST_REPO/vhs/setup.sh")"`
Enter
Type `cd "$WORKDIR"`
Enter
Type `nvim -i NONE main.cpp`
Enter
Wait+Screen@30s /cin\.tie/
Type ":colorscheme tokyonight | source $PRETEST_REPO/vhs/keys.lua"
Enter
Sleep 400ms
Show

# --- open the UI: the cursor lands in the header ------------------------
Sleep 1s
Type ":Pretest"
Sleep 500ms
Enter
Wait+Screen@10s /Testcases/
Sleep 1s

# --- `a` adds a case and moves to Input; one that overflows int ---------
Type "a"
Sleep 600ms
Type "i"
Type "2000000000 2000000000"
Sleep 400ms
Tab
Sleep 400ms
Type "4000000000"
Escape
Sleep 700ms

# --- <S-CR> runs every case: case 3 is WA --------------------------------
Type@0ms "[13;2u"
Wait+Screen@45s /WA/
Sleep 2s

# --- <leader>j jumps to the source; widen to long long ------------------
Type@0ms " j"
Sleep 700ms
Type "/int a"
Enter
Sleep 400ms
Type "ciw"
Type "long long"
Escape
Sleep 400ms
Type ":w"
Enter
Sleep 800ms

# --- <leader>j back to the UI, <S-CR> again: all AC ---------------------
Type@0ms " j"
Sleep 700ms
Type@0ms "[13;2u"
Wait+Screen@45s /Testcases 3\/3/
Sleep 2.5s

# --- leave no .prob / binary in save_dir --------------------------------
Hide
Escape
Type ":qa!"
Enter
Sleep 400ms
Type `bash "$PRETEST_REPO/vhs/cleanup.sh"`
Enter
Type `cd "$PRETEST_REPO" && rm -rf "$WORKDIR"`
Enter

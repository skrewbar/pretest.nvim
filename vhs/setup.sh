#!/usr/bin/env bash
# Prepare a throwaway workspace with main.cpp and a matching .prob.
# Uses the user's Neovim config so save_dir / languages match the recording.
# Prints the workspace path on stdout.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/pretest-vhs.XXXXXX")"
cp "$here/main.cpp" "$work/main.cpp"

nvim --headless -i NONE "$work/main.cpp" -S "$here/seed.lua"
test -s "$work/.vhs-cleanup"

printf '%s\n' "$work"

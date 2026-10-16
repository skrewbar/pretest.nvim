#!/usr/bin/env bash
# Remove .prob / binary paths listed by seed.lua (usually under save_dir).
set -euo pipefail

list="${1:-.vhs-cleanup}"
if [[ ! -f "$list" ]]; then
  exit 0
fi

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  rm -f "$path"
  # macOS writes debug symbols next to the binary when compiled with -g.
  if [[ -d "$path.dSYM" ]]; then
    rm -rf "$path.dSYM"
  fi
done < "$list"

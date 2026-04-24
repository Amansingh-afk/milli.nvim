#!/usr/bin/env bash
# Generate preview GIFs for every bundled splash.
#
# Requires: vhs, ttyd, ffmpeg on PATH. Local nvim must have milli.nvim
# installed and loadable (lazy.nvim / packer / etc). Adjust Sleep values
# if splashes show up blank — means nvim hadn't finished loading before
# :MilliPreview was typed.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/previews"
SPLASH_DIR="$ROOT/lua/milli/splashes"

mkdir -p "$OUT"

for f in "$SPLASH_DIR"/*.lua; do
  name="$(basename "$f" .lua)"
  [ "$name" = "README" ] && continue

  tape="$(mktemp --suffix=.tape)"
  cat > "$tape" <<EOF
Output "$OUT/$name.gif"
Set FontSize 14
Set Width 1100
Set Height 800
Set Theme "Catppuccin Mocha"
Set TypingSpeed 0ms
Hide
Type "nvim"
Enter
Sleep 2s
Show
Type ":MilliPreview $name"
Enter
Sleep 6s
EOF

  echo "=== $name ==="
  vhs "$tape"
  rm -f "$tape"
done

echo "done. output in $OUT/"

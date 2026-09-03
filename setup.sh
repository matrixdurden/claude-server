#!/usr/bin/env bash
set -euo pipefail

URL="https://raw.githubusercontent.com/matrixdurden/claude-server/main/claude-server"
BIN_DIR="${HOME}/.local/bin"
BIN="$BIN_DIR/claude-server"

command -v curl >/dev/null 2>&1 || {
  printf 'error: curl is required\n' >&2
  exit 1
}

mkdir -p "$BIN_DIR"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL "$URL" -o "$tmp"
install -m 0755 "$tmp" "$BIN"

printf 'installed: %s\n' "$BIN"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    printf '\nAdd this to your shell PATH once:\n'
    printf '  export PATH="$HOME/.local/bin:$PATH"\n\n'
    ;;
esac

exec "$BIN"

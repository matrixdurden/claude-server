#!/usr/bin/env bash
set -euo pipefail

SERVICE="claude-remote.service"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/$SERVICE"
PROJECT_DIR="${1:-$PWD}"
USER_NAME="$(id -un)"
PATH_VALUE="${PATH:-/usr/local/bin:/usr/bin:/bin}"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

escape_unit() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//%/%%}"
  printf '%s' "$value"
}

command -v systemctl >/dev/null 2>&1 || fail "systemd is required"
command -v loginctl >/dev/null 2>&1 || fail "systemd-logind is required"

CLAUDE_BIN="$(type -P claude || true)"
[[ -n "$CLAUDE_BIN" && -x "$CLAUDE_BIN" ]] || fail "claude is not installed or not in PATH"
[[ -d "$PROJECT_DIR" ]] || fail "directory not found: $PROJECT_DIR"

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
CLAUDE_BIN="$(readlink -f "$CLAUDE_BIN" 2>/dev/null || printf '%s' "$CLAUDE_BIN")"

if [[ "$(loginctl show-user "$USER_NAME" -p Linger --value 2>/dev/null || true)" != "yes" ]]; then
  if [[ "$EUID" -eq 0 ]]; then
    loginctl enable-linger "$USER_NAME"
  elif command -v sudo >/dev/null 2>&1; then
    sudo loginctl enable-linger "$USER_NAME"
  else
    fail "sudo is required once to enable systemd linger"
  fi
fi

mkdir -p "$UNIT_DIR"

PROJECT_ESC="$(escape_unit "$PROJECT_DIR")"
CLAUDE_ESC="$(escape_unit "$CLAUDE_BIN")"
PATH_ESC="$(escape_unit "$PATH_VALUE")"

cat > "$UNIT" <<EOF
[Unit]
Description=Claude Code Remote Control
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory="$PROJECT_ESC"
Environment="PATH=$PATH_ESC"
ExecStart="$CLAUDE_ESC" remote-control --spawn same-dir
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable "$SERVICE" >/dev/null
systemctl --user restart "$SERVICE"

printf 'installed: %s\n' "$SERVICE"
printf 'directory: %s\n' "$PROJECT_DIR"
printf 'logs: journalctl --user -u %s -f\n' "$SERVICE"

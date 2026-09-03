#!/usr/bin/env bash
set -euo pipefail

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/claude-remote@.service"
LEGACY_UNIT="$UNIT_DIR/claude-remote.service"
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
command -v systemd-escape >/dev/null 2>&1 || fail "systemd-escape is required"
command -v loginctl >/dev/null 2>&1 || fail "systemd-logind is required"

CLAUDE_BIN="$(type -P claude || true)"
[[ -n "$CLAUDE_BIN" && -x "$CLAUDE_BIN" ]] || fail "claude is not installed or not in PATH"
CLAUDE_BIN="$(readlink -f "$CLAUDE_BIN" 2>/dev/null || printf '%s' "$CLAUDE_BIN")"

if [[ "$(loginctl show-user "$USER_NAME" -p Linger --value 2>/dev/null || true)" != "yes" ]]; then
  if (( EUID == 0 )); then
    loginctl enable-linger "$USER_NAME"
  else
    command -v sudo >/dev/null 2>&1 || fail "sudo is required once to enable systemd linger"
    sudo loginctl enable-linger "$USER_NAME"
  fi
fi

mkdir -p "$UNIT_DIR"

# Migrate the original single-project service, if present.
systemctl --user disable --now claude-remote.service >/dev/null 2>&1 || true
rm -f "$LEGACY_UNIT"

CLAUDE_ESC="$(escape_unit "$CLAUDE_BIN")"
PATH_ESC="$(escape_unit "$PATH_VALUE")"

cat > "$UNIT" <<EOF_UNIT
[Unit]
Description=Claude Code Remote Control - %I
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%I
Environment="PATH=$PATH_ESC"
ExecStart="$CLAUDE_ESC" remote-control --spawn same-dir
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF_UNIT

systemctl --user daemon-reload

(( $# )) || set -- "$PWD"

for project in "$@"; do
  [[ -d "$project" ]] || fail "directory not found: $project"
  project="$(cd "$project" && pwd -P)"
  instance="$(systemd-escape --path "$project")"
  service="claude-remote@$instance.service"

  systemctl --user enable "$service" >/dev/null
  systemctl --user restart "$service"

  printf 'installed: %s -> %s\n' "$service" "$project"
done

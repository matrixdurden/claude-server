#!/usr/bin/env bash
set -euo pipefail

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/claude-remote@.service"
LEGACY_UNIT="$UNIT_DIR/claude-remote.service"
BIN="$HOME/.local/bin/claude-server"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v systemctl >/dev/null 2>&1 || fail "systemd is required"
command -v systemd-escape >/dev/null 2>&1 || fail "systemd-escape is required"

remove_all() {
  local units=() link
  shopt -s nullglob
  for link in "$UNIT_DIR/default.target.wants"/claude-remote@*.service; do
    units+=("$(basename "$link")")
  done
  shopt -u nullglob

  if (( ${#units[@]} )); then
    systemctl --user disable --now "${units[@]}" >/dev/null 2>&1 || true
  fi

  systemctl --user disable --now claude-remote.service >/dev/null 2>&1 || true
  rm -f "$UNIT" "$LEGACY_UNIT" "$BIN"
  systemctl --user daemon-reload
  systemctl --user reset-failed >/dev/null 2>&1 || true

  printf 'removed: claude-server and all Remote Control services\n'
  printf 'Claude Code and systemd linger were left untouched.\n'
}

if [[ "${1:-}" == "--all" ]]; then
  remove_all
  exit 0
fi

(( $# )) || set -- "$PWD"

for project in "$@"; do
  [[ -d "$project" ]] || fail "directory not found: $project"
  project="$(cd "$project" && pwd -P)"
  instance="$(systemd-escape --path "$project")"
  service="claude-remote@$instance.service"

  systemctl --user disable --now "$service" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$service" >/dev/null 2>&1 || true
  printf 'removed: %s\n' "$project"
done

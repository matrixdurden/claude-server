#!/usr/bin/env bash
set -euo pipefail

SERVICE="claude-remote.service"
UNIT="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$SERVICE"

systemctl --user disable --now "$SERVICE" >/dev/null 2>&1 || true
rm -f "$UNIT"
systemctl --user daemon-reload
systemctl --user reset-failed "$SERVICE" >/dev/null 2>&1 || true

printf 'removed: %s\n' "$SERVICE"
printf 'Claude Code and systemd linger were left untouched.\n'

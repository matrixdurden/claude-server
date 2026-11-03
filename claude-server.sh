#!/usr/bin/env bash
set -euo pipefail

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/claude-remote@.service"
TTY=/dev/tty

RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'

PROJECT_PATHS=()
PROJECT_SERVICES=()
PROJECT_STATES=()
SELECTED=0
STATUS=""
TUI=0

fail() {
  printf '\n%s%serror:%s %s\n' "$BOLD" "$RED" "$RESET" "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

has_tty() {
  [[ -r "$TTY" && -w "$TTY" ]]
}

claude_bin() {
  local bin
  bin="$(type -P claude || true)"
  [[ -n "$bin" && -x "$bin" ]] || fail "claude is not installed or not in PATH"
  # Keep the launcher path: Claude updates replace the versioned binary it points to.
  printf '%s' "$bin"
}

clear_screen() {
  if (( TUI )); then
    printf '\033[2J\033[H'
  fi
}

header() {
  clear_screen
  printf '%s%sClaude Remote%s\n\n' "$BOLD" "$CYAN" "$RESET"
}

expand_path() {
  local path="$1"
  case "$path" in
    "~") path="$HOME" ;;
    "~/"*) path="$HOME/${path#\~/}" ;;
  esac
  printf '%s' "$path"
}

escape_unit_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//%/%%}"
  printf '%s' "$value"
}

service_name() {
  printf 'claude-remote@%s.service' "$(systemd-escape --path "$1")"
}

ensure_linger() {
  local user
  user="$(id -un)"

  [[ "$(loginctl show-user "$user" -p Linger --value 2>/dev/null || true)" == "yes" ]] && return

  if (( EUID == 0 )); then
    loginctl enable-linger "$user"
  elif have sudo; then
    header
    printf 'Systemd linger is required once for reboot/logout persistence.\n\n'
    sudo loginctl enable-linger "$user"
  else
    fail "sudo is required once to enable systemd linger"
  fi
}

ensure_template() {
  local bin_esc path_esc

  bin_esc="$(escape_unit_value "$(claude_bin)")"
  path_esc="$(escape_unit_value "${PATH:-/usr/local/bin:/usr/bin:/bin}")"

  ensure_linger
  mkdir -p "$UNIT_DIR"

  cat > "$UNIT" <<EOF_UNIT
[Unit]
Description=Claude Code Remote Control - %f
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%f
Environment="PATH=$path_esc"
ExecStart="$bin_esc" remote-control --spawn same-dir
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF_UNIT

  systemctl --user daemon-reload
}

load_projects() {
  PROJECT_PATHS=()
  PROJECT_SERVICES=()
  PROJECT_STATES=()

  local wants="$UNIT_DIR/default.target.wants"
  local link service instance path state

  shopt -s nullglob
  for link in "$wants"/claude-remote@*.service; do
    service="$(basename "$link")"
    instance="${service#claude-remote@}"
    instance="${instance%.service}"
    path="$(systemd-escape --unescape --path "$instance" 2>/dev/null || true)"
    [[ -n "$path" ]] || continue

    if systemctl --user is-active --quiet "$service" 2>/dev/null; then
      state="running"
    else
      state="stopped"
    fi

    PROJECT_PATHS+=("$path")
    PROJECT_SERVICES+=("$service")
    PROJECT_STATES+=("$state")
  done
  shopt -u nullglob

  if (( ${#PROJECT_PATHS[@]} == 0 )); then
    SELECTED=0
  elif (( SELECTED >= ${#PROJECT_PATHS[@]} )); then
    SELECTED=$((${#PROJECT_PATHS[@]} - 1))
  fi
}

cleanup_template_if_empty() {
  load_projects
  (( ${#PROJECT_PATHS[@]} )) && return
  rm -f "$UNIT"
  systemctl --user daemon-reload
}

render() {
  load_projects
  header

  if (( ${#PROJECT_PATHS[@]} == 0 )); then
    printf '  %sNo projects%s\n' "$DIM" "$RESET"
  else
    local i mark
    for i in "${!PROJECT_PATHS[@]}"; do
      if [[ "${PROJECT_STATES[$i]}" == "running" ]]; then
        mark="${GREEN}●${RESET}"
      else
        mark="${YELLOW}○${RESET}"
      fi

      if (( i == SELECTED )); then
        printf '%s%s›%s %b %s\n' "$BOLD" "$CYAN" "$RESET" "$mark" "${PROJECT_PATHS[$i]}"
      else
        printf '  %b %s\n' "$mark" "${PROJECT_PATHS[$i]}"
      fi
    done
  fi

  [[ -n "$STATUS" ]] && printf '\n%s%s%s\n' "$RED" "$STATUS" "$RESET"
  printf '\n%s↑↓ select   a add   del delete   q quit%s\n' "$DIM" "$RESET"
}

# A service stuck on a prompt still looks "active (running)", so check Claude's own
# config: the Remote Control question was answered and the folder (or a parent) trusted.
claude_ready() {
  local project="$1"
  local config="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
  local dirs=() dir="$project"

  [[ -r "$config" ]] || return 1

  while true; do
    dirs+=("$dir")
    [[ "$dir" == "/" ]] && break
    dir="$(dirname "$dir")"
  done

  if have jq; then
    jq -e '. as $c | .remoteDialogSeen == true
      and any($ARGS.positional[]; $c.projects[.].hasTrustDialogAccepted == true)' \
      "$config" --args "${dirs[@]}" >/dev/null 2>&1
  elif have python3; then
    python3 -c '
import json, sys
try:
    config = json.load(open(sys.argv[1]))
    projects = config.get("projects") or {}
    ready = config.get("remoteDialogSeen") is True and any(
        (projects.get(d) or {}).get("hasTrustDialogAccepted") is True for d in sys.argv[2:])
except Exception:
    ready = False
sys.exit(0 if ready else 1)
' "$config" "${dirs[@]}"
  else
    # Without a JSON reader, onboarding is the safe default.
    return 1
  fi
}

wait_running() {
  local service="$1"
  local i

  sleep 0.75
  for ((i = 0; i < 4; i++)); do
    if systemctl --user is-active --quiet "$service" 2>/dev/null; then
      sleep 0.5
      systemctl --user is-active --quiet "$service" 2>/dev/null && return 0
    fi
    sleep 0.25
  done
  return 1
}

onboard_project() {
  local project="$1"
  local bin
  bin="$(claude_bin)"

  has_tty || fail "Claude Remote Control needs one-time setup in $project; run this from a terminal"

  header
  printf 'Claude Remote Control needs one-time setup for:\n\n  %s\n\n' "$project"
  printf '%sTrust the folder and answer y to "Enable Remote Control?".%s\n' "$DIM" "$RESET"
  printf '%sWhen it shows Connected, press Ctrl+C.%s\n\n' "$DIM" "$RESET"

  # Run the same command as the service: plain `claude` never asks the Remote Control
  # question, and an unanswered prompt leaves the TTY-less service waiting forever.
  # The no-op trap keeps Ctrl+C from ending this script; exec resets it for Claude.
  trap ':' INT
  (
    cd "$project"
    exec "$bin" remote-control --spawn same-dir < "$TTY" > "$TTY" 2>&1
  ) || true
  trap - INT
}

add_project() {
  local project service i
  project="$(expand_path "$1")"

  if [[ ! -d "$project" ]]; then
    STATUS="Directory not found: $project"
    return
  fi

  project="$(cd "$project" && pwd -P)"
  ensure_template
  service="$(service_name "$project")"

  if ! claude_ready "$project"; then
    systemctl --user stop "$service" >/dev/null 2>&1 || true
    onboard_project "$project"

    if ! claude_ready "$project"; then
      # Never leave a service enabled that would wait on a prompt after reboot.
      remove_service "$service"
      STATUS="Claude Remote Control setup was not completed for $project"
      return
    fi
  fi

  systemctl --user enable "$service" >/dev/null
  systemctl --user restart "$service"

  # Setup is done at this point; a failed start is usually login, so show Claude's output.
  if ! wait_running "$service"; then
    systemctl --user stop "$service" >/dev/null 2>&1 || true
    onboard_project "$project"
    systemctl --user restart "$service"

    if ! wait_running "$service"; then
      STATUS="Remote Control could not start for $project"
    fi
  fi

  load_projects
  for i in "${!PROJECT_PATHS[@]}"; do
    if [[ "${PROJECT_PATHS[$i]}" == "$project" ]]; then
      SELECTED=$i
      break
    fi
  done
}

remove_service() {
  local service="$1"

  systemctl --user disable --now "$service" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$service" >/dev/null 2>&1 || true
  cleanup_template_if_empty
}

prompt_add() {
  render
  printf '\n%sPath%s [%s]: ' "$CYAN" "$RESET" "$PWD"

  local input
  IFS= read -er input < "$TTY" || return
  add_project "${input:-$PWD}"
}

delete_selected() {
  load_projects
  (( ${#PROJECT_PATHS[@]} )) || return
  remove_service "${PROJECT_SERVICES[$SELECTED]}"
}

move_up() {
  load_projects
  (( ${#PROJECT_PATHS[@]} )) || return
  SELECTED=$(((SELECTED - 1 + ${#PROJECT_PATHS[@]}) % ${#PROJECT_PATHS[@]}))
}

move_down() {
  load_projects
  (( ${#PROJECT_PATHS[@]} )) || return
  SELECTED=$(((SELECTED + 1) % ${#PROJECT_PATHS[@]}))
}

handle_escape() {
  local c1="" c2="" c3=""
  IFS= read -rsn1 -t 0.1 c1 < "$TTY" || true
  [[ "$c1" == "[" ]] || return

  IFS= read -rsn1 -t 0.1 c2 < "$TTY" || true
  case "$c2" in
    A) move_up ;;
    B) move_down ;;
    3)
      IFS= read -rsn1 -t 0.1 c3 < "$TTY" || true
      [[ "$c3" == "~" ]] && delete_selected
      ;;
  esac
}

tui() {
  has_tty || fail "an interactive terminal is required"
  TUI=1

  local key
  while true; do
    render
    STATUS=""

    IFS= read -rsn1 key < "$TTY" || break
    case "$key" in
      q|Q) break ;;
      a|A) prompt_add ;;
      d|D) delete_selected ;;
      k) move_up ;;
      j) move_down ;;
      $'\x1b') handle_escape ;;
    esac
  done

  clear_screen
}

cli_add() {
  add_project "$1"
  [[ -z "$STATUS" ]] || fail "$STATUS"
  printf '%s●%s %s\n' "$GREEN" "$RESET" "${PROJECT_PATHS[$SELECTED]}"
}

cli_remove() {
  local project service
  project="$(expand_path "$1")"
  [[ -d "$project" ]] && project="$(cd "$project" && pwd -P)"
  service="$(service_name "$project")"

  [[ -e "$UNIT_DIR/default.target.wants/$service" ]] || fail "not configured: $project"
  remove_service "$service"
  printf 'removed %s\n' "$project"
}

main() {
  have systemctl || fail "systemd is required"
  have systemd-escape || fail "systemd-escape is required"
  have loginctl || fail "systemd-logind is required"

  # Rewrite an existing template so older installs drop pinned version paths.
  if [[ -f "$UNIT" ]] && have claude; then
    ensure_template
  fi

  case "${1:-}" in
    "") tui ;;
    add) cli_add "${2:-$PWD}" ;;
    remove) cli_remove "${2:?usage: claude-server.sh remove <path>}" ;;
    *) fail "usage: claude-server.sh [add [path] | remove <path>]" ;;
  esac
}

main "$@"

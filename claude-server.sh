#!/usr/bin/env bash
set -euo pipefail

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/claude-remote@.service"
LEGACY_UNIT="$UNIT_DIR/claude-remote.service"
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

fail() {
  printf '\n%s%serror:%s %s\n' "$BOLD" "$RED" "$RESET" "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

claude_bin() {
  local bin
  bin="$(type -P claude || true)"
  [[ -n "$bin" && -x "$bin" ]] || fail "claude is not installed or not in PATH"
  readlink -f "$bin" 2>/dev/null || printf '%s' "$bin"
}

clear_screen() {
  printf '\033[2J\033[H'
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

ensure_linger() {
  local user
  user="$(id -un)"

  [[ "$(loginctl show-user "$user" -p Linger --value 2>/dev/null || true)" == "yes" ]] && return

  if (( EUID == 0 )); then
    loginctl enable-linger "$user"
  elif have sudo; then
    clear_screen
    printf '%s%sClaude Remote%s\n\nSystemd linger is required once for reboot/logout persistence.\n\n' "$BOLD" "$CYAN" "$RESET"
    sudo loginctl enable-linger "$user"
  else
    fail "sudo is required once to enable systemd linger"
  fi
}

ensure_template() {
  local bin path_value bin_esc path_esc

  have systemctl || fail "systemd is required"
  have systemd-escape || fail "systemd-escape is required"
  have loginctl || fail "systemd-logind is required"

  bin="$(claude_bin)"
  path_value="${PATH:-/usr/local/bin:/usr/bin:/bin}"

  ensure_linger
  mkdir -p "$UNIT_DIR"

  systemctl --user disable --now claude-remote.service >/dev/null 2>&1 || true
  rm -f "$LEGACY_UNIT"

  bin_esc="$(escape_unit_value "$bin")"
  path_esc="$(escape_unit_value "$path_value")"

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
  clear_screen
  printf '%s%sClaude Remote%s\n\n' "$BOLD" "$CYAN" "$RESET"

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

wait_running() {
  local service="$1"
  local i

  for ((i = 0; i < 8; i++)); do
    systemctl --user is-active --quiet "$service" 2>/dev/null && return 0
    sleep 0.25
  done
  return 1
}

onboard_project() {
  local project="$1"
  local bin
  bin="$(claude_bin)"

  clear_screen
  printf '%s%sClaude Remote%s\n\n' "$BOLD" "$CYAN" "$RESET"
  printf 'Claude needs one-time setup for:\n\n  %s\n\n' "$project"
  printf '%sComplete any login / workspace trust prompts, then use /exit to return here.%s\n\n' "$DIM" "$RESET"

  (
    cd "$project"
    "$bin" < "$TTY" > "$TTY" 2>&1
  ) || true
}

add_project() {
  render
  printf '\n%sPath%s [%s]: ' "$CYAN" "$RESET" "$PWD"

  local input project instance service i
  IFS= read -er input < "$TTY" || return
  input="${input:-$PWD}"
  project="$(expand_path "$input")"

  if [[ ! -d "$project" ]]; then
    STATUS="Directory not found: $project"
    return
  fi

  project="$(cd "$project" && pwd -P)"
  ensure_template

  instance="$(systemd-escape --path "$project")"
  service="claude-remote@$instance.service"

  systemctl --user enable "$service" >/dev/null
  systemctl --user restart "$service"

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

delete_selected() {
  load_projects
  (( ${#PROJECT_PATHS[@]} )) || return

  local service="${PROJECT_SERVICES[$SELECTED]}"

  systemctl --user disable --now "$service" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$service" >/dev/null 2>&1 || true
  cleanup_template_if_empty
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

main() {
  [[ -r "$TTY" && -w "$TTY" ]] || fail "an interactive terminal is required"
  have systemctl || fail "systemd is required"
  have systemd-escape || fail "systemd-escape is required"

  local key
  while true; do
    render
    STATUS=""

    IFS= read -rsn1 key < "$TTY" || break
    case "$key" in
      q|Q) break ;;
      a|A) add_project ;;
      d|D) delete_selected ;;
      k) move_up ;;
      j) move_down ;;
      $'\x1b') handle_escape ;;
    esac
  done

  clear_screen
}

main "$@"

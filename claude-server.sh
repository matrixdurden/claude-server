#!/usr/bin/env bash
set -euo pipefail

UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/claude-remote@.service"
LEGACY_UNIT="$UNIT_DIR/claude-remote.service"
TTY=/dev/tty

fail() {
  printf '\nerror: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

clear_screen() {
  printf '\033[2J\033[H'
}

pause() {
  printf '\nPress any key to continue...'
  IFS= read -rsn1 _ < "$TTY" || true
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
    printf '\nSystemd linger is required so Remote Control survives logout/reboot.\n'
    sudo loginctl enable-linger "$user"
  else
    fail "sudo is required once to enable systemd linger"
  fi
}

ensure_template() {
  local claude_bin path_value claude_esc path_esc

  have systemctl || fail "systemd is required"
  have systemd-escape || fail "systemd-escape is required"
  have loginctl || fail "systemd-logind is required"

  claude_bin="$(type -P claude || true)"
  [[ -n "$claude_bin" && -x "$claude_bin" ]] || fail "claude is not installed or not in PATH"
  claude_bin="$(readlink -f "$claude_bin" 2>/dev/null || printf '%s' "$claude_bin")"
  path_value="${PATH:-/usr/local/bin:/usr/bin:/bin}"

  ensure_linger
  mkdir -p "$UNIT_DIR"

  systemctl --user disable --now claude-remote.service >/dev/null 2>&1 || true
  rm -f "$LEGACY_UNIT"

  claude_esc="$(escape_unit_value "$claude_bin")"
  path_esc="$(escape_unit_value "$path_value")"

  cat > "$UNIT" <<EOF
[Unit]
Description=Claude Code Remote Control - %f
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=%f
Environment="PATH=$path_esc"
ExecStart="$claude_esc" remote-control --spawn same-dir
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

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
}

cleanup_template_if_empty() {
  load_projects
  (( ${#PROJECT_PATHS[@]} )) && return

  rm -f "$UNIT"
  systemctl --user daemon-reload
}

menu() {
  local title="$1"
  shift
  local items=("$@")
  local selected=0 key seq i

  while true; do
    clear_screen
    printf 'Claude Remote\n\n%s\n\n' "$title"

    for i in "${!items[@]}"; do
      if (( i == selected )); then
        printf '  \033[7m› %s\033[0m\n' "${items[$i]}"
      else
        printf '    %s\n' "${items[$i]}"
      fi
    done

    printf '\n↑/↓ move   Enter select   q back\n'

    IFS= read -rsn1 key < "$TTY" || return 1
    case "$key" in
      '') MENU_SELECTED=$selected; return 0 ;;
      q|Q) return 1 ;;
      $'\x1b')
        IFS= read -rsn2 -t 0.1 seq < "$TTY" || true
        case "$seq" in
          '[A') (( selected = (selected - 1 + ${#items[@]}) % ${#items[@]} )) ;;
          '[B') (( selected = (selected + 1) % ${#items[@]} )) ;;
        esac
        ;;
      k) (( selected = (selected - 1 + ${#items[@]}) % ${#items[@]} )) ;;
      j) (( selected = (selected + 1) % ${#items[@]} )) ;;
    esac
  done
}

add_project() {
  clear_screen
  printf 'Claude Remote\n\nAdd project\n\n'
  printf 'Project path [%s]: ' "$PWD"

  local input project instance service
  IFS= read -er input < "$TTY"
  input="${input:-$PWD}"
  project="$(expand_path "$input")"

  [[ -d "$project" ]] || {
    printf '\nDirectory not found: %s\n' "$project"
    pause
    return
  }

  project="$(cd "$project" && pwd -P)"
  ensure_template

  instance="$(systemd-escape --path "$project")"
  service="claude-remote@$instance.service"

  systemctl --user enable "$service" >/dev/null
  systemctl --user restart "$service"

  printf '\nAdded: %s\n' "$project"
  pause
}

remove_project() {
  load_projects

  if (( ${#PROJECT_PATHS[@]} == 0 )); then
    clear_screen
    printf 'Claude Remote\n\nNo projects configured.\n'
    pause
    return
  fi

  local items=() i answer
  for i in "${!PROJECT_PATHS[@]}"; do
    items+=("${PROJECT_PATHS[$i]}  [${PROJECT_STATES[$i]}]")
  done

  menu "Remove project" "${items[@]}" || return
  i=$MENU_SELECTED

  clear_screen
  printf 'Remove this project?\n\n  %s\n\n[y/N] ' "${PROJECT_PATHS[$i]}"
  IFS= read -rsn1 answer < "$TTY" || true
  printf '\n'

  [[ "$answer" == y || "$answer" == Y ]] || return

  systemctl --user disable --now "${PROJECT_SERVICES[$i]}" >/dev/null 2>&1 || true
  systemctl --user reset-failed "${PROJECT_SERVICES[$i]}" >/dev/null 2>&1 || true
  cleanup_template_if_empty

  printf '\nRemoved: %s\n' "${PROJECT_PATHS[$i]}"
  pause
}

list_projects() {
  load_projects
  clear_screen
  printf 'Claude Remote\n\nProjects\n\n'

  if (( ${#PROJECT_PATHS[@]} == 0 )); then
    printf '  No projects configured.\n'
  else
    local i mark
    for i in "${!PROJECT_PATHS[@]}"; do
      [[ "${PROJECT_STATES[$i]}" == running ]] && mark='●' || mark='○'
      printf '  %s %-8s %s\n' "$mark" "${PROJECT_STATES[$i]}" "${PROJECT_PATHS[$i]}"
    done
  fi

  pause
}

main() {
  [[ -r "$TTY" && -w "$TTY" ]] || fail "an interactive terminal is required"
  have systemctl || fail "systemd is required"
  have systemd-escape || fail "systemd-escape is required"

  while true; do
    menu "Manage Remote Control" \
      "Add project" \
      "Remove project" \
      "List projects" \
      "Exit" || break

    case "$MENU_SELECTED" in
      0) add_project ;;
      1) remove_project ;;
      2) list_projects ;;
      3) break ;;
    esac
  done

  clear_screen
}

main "$@"

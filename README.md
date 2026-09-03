# claude-server

Portable single-screen TUI for managing always-on Claude Code Remote Control sessions on Linux.

No Docker. No installed manager. No service IDs.

## Requirements

- Linux with systemd
- Claude Code already installed and available as `claude`
- Claude Code signed in
- Workspace trust / Remote Control first-use consent completed when prompted

## Run

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/claude-server.sh | bash
```

Nothing is installed. The script runs directly from the pipe and exits with the TUI.

```text
Claude Remote

  ● /srv/api
› ● /srv/web
  ○ /srv/old

↑↓ select   a add   del delete   q quit
```

## Controls

- `↑` / `↓` — select project
- `a` — add a project path
- `Delete` or `d` — immediately remove the selected project
- `q` — exit

There are no submenus and no confirmation screens.

Pressing `a` asks for a path. Press Enter on an empty path to use the current directory.

`●` means the Remote Control service is running. `○` means it is configured but currently stopped.

Each added project gets its own persistent `systemd --user` Remote Control service with automatic restart and reboot/logout persistence. When the last project is removed, the shared service template is cleaned up automatically.

The TUI itself is stateless and portable. Claude Code itself is never installed, updated, or removed by this script.

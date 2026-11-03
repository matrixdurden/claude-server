# claude-server

Portable single-screen TUI for managing always-on Claude Code Remote Control sessions on Linux.

No Docker. No installed manager. No service IDs.

## Requirements

- Linux with systemd
- Claude Code already installed and available as `claude`

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

Before starting a service, the script checks `~/.claude.json` (or `$CLAUDE_CONFIG_DIR/.claude.json`) for the two answers a background service cannot give: workspace trust for the project (or a parent folder) and the one-time "Enable Remote Control?" question (`remoteDialogSeen`). If either is missing, or the service fails to start, the TUI opens `claude remote-control` in that project. Trust the folder, answer `y`, and press Ctrl+C once it shows Connected; the TUI then starts the Remote Control service and returns to the project list. If setup was not completed, the project is not added.

Reading the config needs `jq` or `python3`; without either, the setup step runs on every add.

## Without the TUI

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/claude-server.sh | bash -s add ~/projects/api
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/claude-server.sh | bash -s remove ~/projects/api
```

`add` without a path uses the current directory. If first-time setup is needed, `claude remote-control` opens in the project; trust the folder, answer `y`, and press Ctrl+C once it shows Connected.

## Status

`●` means the Remote Control service is running. `○` means it is configured but currently stopped.

Each added project gets its own persistent `systemd --user` Remote Control service with automatic restart and reboot/logout persistence. When the last project is removed, the shared service template is cleaned up automatically.

Services start Claude through its launcher in `PATH` (for example `~/.local/bin/claude`), so they keep working after Claude updates itself. Running the script once rewrites older templates that pinned a versioned binary.

The TUI itself is stateless and portable. Claude Code itself is never installed, updated, or removed by this script.

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

If Claude Remote cannot start because the machine needs login, workspace trust, or other first-time Claude setup, the TUI automatically opens Claude in that project. Complete Claude's prompts and use `/exit`; the TUI then starts the Remote Control service and returns to the project list.

## Without the TUI

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/claude-server.sh | bash -s add ~/projects/api
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/claude-server.sh | bash -s remove ~/projects/api
```

`add` without a path uses the current directory. If first-time Claude setup is needed, Claude opens in the project; finish its prompts and type `/exit`.

## Status

`●` means the Remote Control service is running. `○` means it is configured but currently stopped.

Each added project gets its own persistent `systemd --user` Remote Control service with automatic restart and reboot/logout persistence. When the last project is removed, the shared service template is cleaned up automatically.

Services start Claude through its launcher in `PATH` (for example `~/.local/bin/claude`), so they keep working after Claude updates itself. Running the script once rewrites older templates that pinned a versioned binary.

The TUI itself is stateless and portable. Claude Code itself is never installed, updated, or removed by this script.

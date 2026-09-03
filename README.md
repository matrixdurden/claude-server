# claude-server

Portable TUI for managing always-on Claude Code Remote Control sessions on Linux.

No Docker. No installed manager. No service IDs to remember.

## Requirements

- Linux with systemd
- Claude Code already installed and available as `claude`
- Claude Code signed in
- Workspace trust / Remote Control first-use consent completed when prompted

## Run

Every time you want to manage it, run:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/claude-server.sh | bash
```

That opens the TUI directly:

```text
Claude Remote

Manage Remote Control

  › Add project
    Remove project
    List projects
    Exit

↑/↓ move   Enter select   q back
```

Nothing is installed as a `claude-server` command. The script runs from the pipe and exits when you leave the TUI.

## Add project

Choose **Add project**, type a directory path, and press Enter.

Press Enter without typing a path to use the current directory.

Each project gets its own persistent `systemd --user` Remote Control service. The service restarts automatically and survives logout/reboot.

## Remove project

Choose **Remove project**, select a configured directory with the arrow keys, and confirm.

When the last project is removed, the shared systemd template is cleaned up automatically.

## List projects

Shows configured directories and whether each Remote Control server is running.

## Notes

The TUI itself is stateless and portable. Only the systemd services needed to keep your selected Claude Remote projects running are persisted.

Claude Code itself is never installed, updated, or removed by this script.

# claude-server

Minimal TUI for running Claude Code Remote Control on Linux.

No Docker. No Claude Code installer. No service IDs to remember.

## Requirements

- Linux with systemd
- Claude Code already installed and available as `claude`
- Claude Code signed in
- Workspace trust / Remote Control first-use consent completed when prompted

## Setup

Run once:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/setup.sh | bash
```

Then use:

```bash
claude-server
```

The TUI gives you:

```text
claude-server

Manage Remote Control

  › Add project
    Remove project
    List projects
    Exit
```

Use `↑` / `↓` and `Enter`.

### Add project

Choose **Add project** and enter a directory:

```text
Project path [/home/user]: /srv/api
```

Pressing Enter without typing anything uses the current directory.

### Remove project

Choose **Remove project**, select the directory with the arrow keys, then confirm.

### List projects

Shows configured directories and whether each Remote Control server is running.

## Full uninstall

Removes the manager and all Claude Remote services:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/uninstall.sh | bash -s -- --all
```

Claude Code itself and systemd linger are left untouched.

## Non-interactive

The old script interface is still available for automation:

```bash
# add
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/install.sh | bash -s -- /srv/api /srv/web

# remove
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/uninstall.sh | bash -s -- /srv/api
```

Each project gets its own `systemd --user` Remote Control service with automatic restart and reboot persistence.

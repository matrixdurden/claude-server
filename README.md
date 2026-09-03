# claude-server

Minimal always-on Claude Code Remote Control service for Linux.

No Docker. No Claude Code installer. Just a small `systemd --user` service.

## Prerequisites

- Linux with systemd
- Claude Code already installed and available as `claude`
- Signed in to Claude Code with your Claude account
- Workspace trust accepted for the project directory

## Install

Run from the project directory you want Claude to control:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/install.sh | bash
```

Or pass the project directory explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/install.sh | bash -s -- /path/to/project
```

The installer:

- finds your existing `claude` binary
- creates `~/.config/systemd/user/claude-remote.service`
- preserves your current `PATH` for remote sessions
- enables systemd linger so it survives logout and reboot
- enables and starts the service
- can be run again safely to update the configuration

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/uninstall.sh | bash
```

This removes only the Remote Control service. Claude Code and systemd linger are left untouched.

## Commands

```bash
systemctl --user status claude-remote.service
systemctl --user restart claude-remote.service
journalctl --user -u claude-remote.service -f
```

## Notes

Remote Control uses Claude Code's server mode:

```bash
claude remote-control --spawn same-dir
```

Authentication and workspace trust are intentionally not automated. If this is a fresh machine or project, complete those once interactively before installing the service.

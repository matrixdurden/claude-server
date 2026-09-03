# claude-server

Minimal always-on Claude Code Remote Control services for Linux.

No Docker. No Claude Code installer. One systemd template, any number of project directories.

## Prerequisites

- Linux with systemd
- Claude Code already installed and available as `claude`
- Signed in to Claude Code
- Workspace trust accepted for each project

## Install

Current directory:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/install.sh | bash
```

One project:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/install.sh | bash -s -- /srv/api
```

Multiple projects:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/install.sh | bash -s -- /srv/api /srv/web /srv/infra
```

Each directory gets its own Remote Control server. Re-running install is safe and can add more projects.

The installer also migrates the old single `claude-remote.service` setup automatically.

## Uninstall

Current directory:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/uninstall.sh | bash
```

One or more projects:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/uninstall.sh | bash -s -- /srv/api /srv/web
```

Everything:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/uninstall.sh | bash -s -- --all
```

Claude Code and systemd linger are left untouched.

## Change a project directory

Remove the old path, then install the new one:

```bash
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/uninstall.sh | bash -s -- /srv/old
curl -fsSL https://raw.githubusercontent.com/matrixdurden/claude-server/main/install.sh | bash -s -- /srv/new
```

## Status and logs

```bash
systemctl --user list-units 'claude-remote@*.service'
journalctl --user -u 'claude-remote@*.service' -f
```

Remote Control runs as:

```bash
claude remote-control --spawn same-dir
```

Authentication and workspace trust are intentionally not automated.

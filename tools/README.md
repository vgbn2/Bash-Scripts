# Repository Operations

This directory contains source installation and synchronization helpers.

## Native setup

```bash
tools/install-system.sh status
tools/install-system.sh install --yes
tools/install-system.sh links --yes
tools/install-system.sh packages core --yes
tools/install-system.sh packages all --yes
```

`install --yes` is the first-time setup shortcut: it creates the command links
and installs the core package group. Package installation supports Debian/Ubuntu
APT hosts and never runs without `--yes`; it prompts for sudo in an interactive
terminal. Command links are user-local and existing regular files are not
overwritten.

## Source mirror

```bash
tools/sync-to-home.sh
tools/sync-to-home.sh --apply --yes
```

The first form previews the mirror. Applying uses the repository as the
canonical source and may delete stale files from the configured mirror. Broad
or overlapping destinations are rejected. `.git`, `.agents`, and `.codex`
metadata are excluded and protected from deletion.

## Host-to-child workspace synchronization

```bash
CODEPTIT_SYNC_HOST=user@host \
CODEPTIT_SYNC_DIR=/remote/path \
tools/sync-codeptit.sh --dry-run
```

The sync is one-way, does not delete child-only files, uses SSH batch mode,
retains partial transfers, limits bandwidth, and prevents overlapping runs.

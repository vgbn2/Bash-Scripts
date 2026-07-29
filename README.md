# Linux System Operations Toolkit

An operator-focused Bash toolkit for Linux diagnostics, guarded maintenance,
hardware controls, local-AI inspection, gaming compatibility, and workstation
synchronization.

This repository is the canonical source. Runtime state, logs, model data, game
data, backups, and machine-specific secrets remain outside the checkout.

## Quick start

Clone over HTTPS without configuring a GitHub account or SSH key:

```bash
git clone https://github.com/vgbn2/Bash-Scripts.git
cd Bash-Scripts
tests/smoke.sh
tools/install-system.sh status
tools/install-system.sh links --yes
system help
```

`status` is read-only. The link action requires `--yes`, creates command links
under `~/.local/bin`, and does not install packages or enable services. If
`~/.local/bin` is not already in `PATH`, follow the command's printed guidance
and open a new shell.

## Operating principles

- Read-only inspection is the default wherever practical.
- State-changing commands use explicit verbs and validated arguments.
- High-impact maintenance, package installation, firmware operations, and
  repairs require `--yes`.
- Diagnostic commands report missing telemetry as incomplete, never healthy.
- Source tests use temporary files and mocked host commands; they do not
  qualify live hardware or services.
- Debian/Ubuntu with APT is the supported native-package platform. Hardware
  controls remain dependent on kernel and device support.

## Repository structure

- `system/` - the `system` command and its feature modules
- `hardware/` - CPU, GPU, and thermal helpers
- `maintenance/` - health reports and explicit repair helpers
- `desktop/` - desktop-startup scripts
- `gaming/` - game launch, performance, and mod backup helpers
- `ai/` - local-model launch and resource-check helpers
- `network/` - connectivity and bandwidth-control helpers
- `backup/` - backup and restore helpers
- `archive/` - historical snapshots retained for reference, not active routing
- `tools/` - maintenance helpers, including the home mirror command

## Command center

Use `system` as the command center:

```bash
system
system menu
system status
system monitor
system doctor
system ai help
system games all
system network processes
system ssh status
system gpu health
system thermals once 80
```

Typing a section without a subcommand opens an interactive scoped prompt:

```text
$ system ai
system ai> status
system ai> models
system ai> back
```

Inside any scoped prompt, `help`, `menu`, and `commands` show the available
commands, `clear` redraws the menu, `repeat` runs the previous command again,
and `back` returns to the normal shell. Unknown commands show help for that
section. Direct help is also available, for example:

```bash
system network help
system display help
system cooling help
```

The optional foreground monitor refreshes without creating a background
service:

```bash
system monitor
system monitor all 5
system monitor network
system monitor once
```

Press `Ctrl+C` to stop it. Supported sections are `cpu`, `gpu`, `ram`,
`disk`, `network`, `battery`, and `processes`.

Games use the same scoped architecture:

```bash
system games
system games steam
system games non-steam
system games launchers
system games all
```

Compatibility entry points remain available through small symlinks in
`~/.local/bin`:

```bash
system help
cpu status
system-health
system-repair suggest
gaming help
ai help
```

State-changing repairs are guarded at the canonical command, including when
called outside `system`:

```bash
system repair thermal --yes
system repair gpu --yes
system repair desktop --yes
```

## Installation and environment audit

No setup action runs automatically. Start with the read-only audit:

```bash
tools/install-system.sh status
# After the `system` link exists, this is equivalent:
system doctor
system setup status
```

Create the user command links explicitly:

```bash
tools/install-system.sh links --yes
```

The installer links `system`, `cpu`, `system-health`, `system-repair`,
`gaming`, and `ai` into `~/.local/bin`. It refuses to overwrite an existing
regular file. Set `SYSTEM_INSTALL_BIN_DIR` to use a different destination.

Install the native Debian/Ubuntu baseline only when requested:

```bash
tools/install-system.sh packages core --yes
# Equivalent after linking:
system setup core --yes
```

The core group covers the commands used by general status, storage, network,
health, SSH, and synchronization features. The broader optional group adds
the feature-specific display, controller, firmware, network-monitoring, and
GPU-diagnostic packages. Use `system setup status` to see every package and
the feature associated with a missing command:

```bash
system setup all --yes
```

Both package actions use `sudo apt-get`; neither enables services nor changes
firmware, CPU policy, display settings, or network shaping. OpenRGB is
deliberately excluded from the broad group because device support and safe
operation must be checked separately. Use `system input install-rgb --yes`
only after that review.

## Guarded maintenance and diagnostics

GPU health and thermal checks now return explicit results instead of treating
missing telemetry as healthy:

```bash
system gpu health
system thermals once 80
system thermals watch 80 10
```

The thermal watcher checks both CPU and NVIDIA telemetry, reports the hotter
reading, and rate-limits repeated notifications. It never changes a hardware
profile or fan setting.

Archival is preview-only unless an action includes `--yes`:

```bash
HDD_BASE=/media/user/archive system archive preview
HDD_BASE=/media/user/archive system archive archive --yes
system archive cleanup --yes
```

The archive path must resolve to a mounted filesystem other than `/`. Relative
subdirectories are preserved and existing destination files are never
overwritten. Archive sources and targets must not overlap; an absent source is
reported and skipped while other configured sources continue. Cleanup is
separate because it removes unused Flatpak runtimes, vacuumed journal history,
and cached APT packages.

Local-AI checks are read-only by default:

```bash
ai status
ai models
ai check <model>
ai diagnose
```

`ai stop <model>` is the only AI command that changes runtime state. The helper
does not automatically download or launch models.

## Network and SSH

```bash
system network processes
system network connections
system ssh status
system ssh keys
```

Install optional network diagnostics explicitly:

```bash
system network install-tools --yes
```

This installs `nethogs`, `iftop`, `bind9-dnsutils`, `iperf3`, and `ethtool`
using sudo. SSH checks never enable or start the SSH server.

## Input, displays, controllers, and firmware

```bash
system input status
system input settings
system input backlight
system controllers status
system controllers test js0
system display status
system display brightness
system firmware status
system firmware updates
system cooling status
system cooling profile balanced
```

Supported controls are guarded and validated:

```bash
system input backlight <level>
system display brightness <1-100>
system display contrast <1-100> [display-number]
system display color warm <1700-4700>
system display color preset <6500|7500|9300|user1> [display-number]
system input mouse-speed <-1.0 to 1.0>
system firmware refresh --yes
system firmware update --yes
```

NVMe storage reports include health, temperature, spare capacity, wear,
power cycles, unsafe shutdowns, error counters, host commands, and data
read/write totals:

```bash
system ssd health
system ssd raw /dev/nvme1n1
```

USB keyboard RGB is available only when OpenRGB recognizes the device:

```bash
system input install-rgb --yes
system input rgb status
system input rgb set <device> <pattern> <RRGGBB> --yes
```

Network shaping supports both directions. The percentage is calculated from
the maximum Mbps value you provide:

```bash
system network limit-download 50 1000
system network limit-upload 50 1000
system network clear-download
system network clear-upload
```

Upload shaping replaces the active interface's outgoing traffic queue and
affects all outgoing traffic, including SSH and file synchronization.

Firmware update requires AC power and at least 40% battery. Raw keyboard-event
logging, synthetic input, direct embedded-controller writes, and automatic
firmware installation are deliberately excluded.

Cooling uses firmware profiles. Manual fan RPM/PWM control is shown only if the
kernel exposes `fan*_input` or `pwm*` interfaces; this Lenovo currently exposes
profiles instead of direct fan controls.

## Source mirror

Preview the mirror update:

```bash
tools/sync-to-home.sh
```

Apply the mirror update:

```bash
tools/sync-to-home.sh --apply --yes
```

The default mirror destination is `$HOME/bash`; override it with
`BASH_MIRROR_DIR` when needed. Because apply mode uses `rsync --delete`, it
rejects `/`, the home directory, the source directory, and overlapping
source/destination paths. Repository and agent metadata (`.git`, `.agents`,
and `.codex`) are excluded and protected from deletion.

## Verification

Run the non-live regression suite:

```bash
tests/smoke.sh
```

It checks Bash syntax, help routing, temporary command-link installation,
confirmation gates, collision-safe archival, truthful GPU failure reporting,
and CPU/GPU thermal selection using mocked commands. It does not invoke sudo,
install packages, clean caches, move real files, or change hardware settings.

Conventional command exit statuses are used:

- `0`: requested check or action completed successfully
- `1`: operational failure, detected critical condition, or exceeded thermal
  threshold where documented
- `2`: invalid usage, missing confirmation, or an incomplete diagnostic where
  documented
- `127`: required command is unavailable

Individual command help remains authoritative for specialized statuses. A
source-level pass is not evidence that sudo access, hardware telemetry,
firmware delivery, graphical sessions, remote SSH, or scheduled execution
works on a particular host.

## Scheduled host-to-child sync

The host-side CodePTIT sync script is:

```bash
tools/sync-codeptit.sh --dry-run
CODEPTIT_SYNC_HOST=user@child-host \
CODEPTIT_SYNC_DIR=/home/user/Documents/codeptit \
tools/sync-codeptit.sh
```

It syncs the complete `Documents/codeptit` folder to the child machine at
about 5 MB/s, keeps partial files, prevents overlapping runs, and does not
delete child-only files. Scheduled use requires SSH key authentication:

```cron
0 2 * * * CODEPTIT_SYNC_HOST=user@child-host CODEPTIT_SYNC_DIR=/home/user/Documents/codeptit /path/to/bash/tools/sync-codeptit.sh
```

# Personal Linux system tools

This folder is the editable source for the custom tools on this laptop.

## Layout

- `system/` - the `system` command and its feature modules
- `hardware/` - CPU, GPU, and thermal helpers
- `maintenance/` - health reports and explicit repair helpers
- `desktop/` - desktop-startup scripts
- `gaming/` - game launch, performance, and mod backup helpers
- `ai/` - local-model launch and resource-check helpers
- `network/` - connectivity and bandwidth-control helpers
- `backup/` - backup and restore helpers
- `archive/` - old local script snapshots
- `tools/` - maintenance helpers, including the home mirror command

## Commands

Use `system` as the command center:

```bash
system
system menu
system status
system monitor
system ai help
system games all
system network processes
system ssh status
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

The older short commands remain available through small symlinks in
`~/.local/bin` for compatibility:

```bash
system help
cpu status
system-health
system-repair suggest
gaming help
ai help
```

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

This installs `nethogs`, `iftop`, `dnsutils`, `iperf3`, and `ethtool` using
sudo. SSH checks never enable or start the SSH server.

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

## Mirror to home

Preview the mirror update:

```bash
tools/sync-to-home.sh
```

Apply the mirror update:

```bash
tools/sync-to-home.sh --apply
```

The default mirror destination is `$HOME/bash`; override it with
`BASH_MIRROR_DIR` when needed.

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

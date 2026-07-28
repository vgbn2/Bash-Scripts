# Gaming helpers

Put only custom helper scripts here, such as:

- game launch wrappers
- performance-profile switches
- mod-configuration backups
- Steam/GPU diagnostic helpers

Do not put game installs, saves, or mod files here.

## Gaming command

```bash
gaming status
gaming games
gaming steam
gaming non-steam
gaming launchers
gaming all
gaming compatibility
gaming diagnose
```

The preferred command-center form is:

```bash
system games
system games steam
system games non-steam
system games all
```

Repair actions are deliberately explicit because they may stop Steam or change
NVIDIA device-node state:

```bash
gaming repair-flatpak-gpu --yes
gaming repair-nvidia-devices --yes
```

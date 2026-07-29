# Gaming and Graphics Diagnostics

The gaming command inventories Steam and non-Steam titles, checks Proton
prefixes, and reports NVIDIA, Vulkan, Flatpak, and launcher state. It does not
modify Proton selections or game configuration.

Use the command-center interface:

```bash
system games status
system games steam
system games non-steam
system games launchers
system games all
system games compatibility
system games diagnose
```

The `gaming` compatibility command exposes the same operations.

## Repairs

Repairs are explicit because they can stop Steam, install Flatpak runtime
components, or recreate NVIDIA device nodes:

```bash
system games repair-flatpak-gpu --yes
system games repair-nvidia-devices --yes
```

The Flatpak repair delegates to the canonical guarded `system-repair` command,
so bypassing the gaming dispatcher does not bypass confirmation.

Game installations, prefixes, saves, launcher configuration, and mod data are
runtime assets and must remain outside this repository.

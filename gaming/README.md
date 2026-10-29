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

## Frame Generation & Lossless Scaling

Adaptive frame generation with Alder Lake P-core isolation and dedicated GPU offload:

```bash
# Witcher 3: Wild Hunt (DX12 borderless mode, 60 FPS in-engine cap, LSFG 3.0 adaptive 120 FPS target)
system games framegen witcher [target_fps]
system games framegen witcher status
system games framegen witcher optimize [base_fps] [target_fps]

# Total War: ROME REMASTERED
system games framegen rome [target_fps]

# Standalone Lossless Scaling companion controller
system games lossless [start|stop|status|detect|engage|tune]
system games fg [2x|3x|4x] [fps]
```

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

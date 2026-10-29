# Linux System Operations & Hardware Optimization Toolkit

An operator-focused, zero-magic Bash toolkit for Linux diagnostics, hardware controls, CPU/GPU undervolting, adaptive frame generation, local-AI telemetry, cybersecurity audits, guarded maintenance, and workstation synchronization.

This repository is the canonical source. Runtime state, logs, model binaries, game files, backups, and machine-specific secrets remain strictly outside the checkout.

---

## Quick Start

### 1. Verification & Smoke Test
Clone over HTTPS without needing GitHub credentials or SSH keys:

```bash
git clone https://github.com/vgbn2/Bash-Scripts.git
cd Bash-Scripts
tests/smoke.sh
```

### 2. Inspect Environment & Create Command Links
Inspect system packages and create user symlinks under `~/.local/bin`:

```bash
tools/install-system.sh status
tools/install-system.sh links --yes
system help
```

`status` is strictly read-only. The link action creates symlinks under `~/.local/bin` and does not install packages or enable services. Ensure `~/.local/bin` is in your `PATH`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## Operating Principles

- **Zero-Magic & Stdlib Primacy**: Direct interaction with Linux sysfs, `/proc`, MSRs, and vendor APIs. No unneeded abstraction layers.
- **Read-Only Inspection by Default**: All status, health, and audit commands are strictly observational.
- **Explicit Confirmation for State Changes**: Any operation that modifies voltage, clocks, files, packages, or services requires explicit flags (e.g. `--yes`).
- **Truthful Telemetry**: Diagnostic scripts report missing or unreachable telemetry as incomplete/missing, never as healthy.
- **Strict Anti-Cheat & Test Integrity**: Zero tolerance for test tampering, `set +e` error masking, or `|| true` silent swallowing. Tested via `anti-cheat-enforcer`.

---

## Comprehensive Utility Catalog & Use Cases

```
Bash-Scripts/
├── system/       → Central system command, interactive TUI menu, status, & hardware monitors
├── hardware/     → CPU/GPU undervolting, frequency governors, fan profiles, & MSR/PCIe register forensics
├── gaming/       → Game launchers, Proton doctor, Lossless Scaling LSFG 3.0, & game-specific framegen
├── security/     → Local host hardening, subnet discovery, capacity stress-testing, & Kali Linux bridge
├── ai/           → Local LLM inspection, Ollama/llama-server process tracking, & VRAM allocation
├── desktop/      → Multi-project terminal runner with weekend & time-of-day awareness
├── network/      → Wake-on-LAN, bandwidth shaping, process socket tracking, & SSH diagnostics
├── maintenance/  → Health auditing & guarded auto-repair recipes (thermals, GPU, desktop, packages)
├── backup/       → Non-destructive system snapshots & incremental storage backups
└── tools/        → System installation, home directory mirror, & CodePTIT sync
```

---

### 1. System Command Center (`system/`)
**Entrypoint**: `system` (or `system-health`, `system-repair`)

Unified CLI command center with interactive scoped prompt support.

| Command | Use Case & What It Is For |
| :--- | :--- |
| `system status` | Snapshot of CPU, GPU, memory, disk, network, and battery telemetry. |
| `system monitor [all\|cpu\|gpu\|...]` | Live-refreshing terminal monitor without background daemon overhead. |
| `system doctor` | Environment audit checking tool links, required utilities, and platform support. |
| `system ssd health` | Deep NVMe SMART audit: wear percentage, temperature, spare capacity, byte counters. |
| `system thermals watch [limit] [interval]` | Dual CPU + GPU thermal watcher with rate-limited desktop notifications. |
| `system repair [thermal\|gpu\|desktop] --yes` | Guarded repair recipes resolving thermal governor locks, GPU device nodes, and desktop crashes. |

*Interactive Scoped Shell*:
```bash
system ai          # Drops into 'system ai>' interactive prompt
system games       # Drops into 'system games>' interactive prompt
```

---

### 2. Hardware Control, Undervolt & Register Forensics (`hardware/`)
**Entrypoints**: `undervolt`, `cpu`, `fan`, `hardware-register-inspector.sh`, `check_gpu.sh`

Low-level hardware tuning, thermal optimization, and kernel fault forensics.

| Utility / Script | Use Case & What It Is For |
| :--- | :--- |
| **`undervolt`** | **CPU/GPU Voltage & Power Management**: Eliminates thermal throttling and increases sustained clock speeds on Intel Core (10th-12th Gen hybrid), AMD Ryzen, and NVIDIA mobile/desktop GPUs. Supports manual offsets, GPU clock/power clamping, and benchmark evaluations. |
| **`hardware-register-inspector.sh`** | **Kernel & Register Forensics**: Directly interrogates CPU MSRs (`0x150`, `0x1B0`, `0x610`), decodes PCIe Type 0 configuration headers, extracts NVML throttle bitmasks, and parses kernel dmesg for Intel VT-d DMAR faults and NVIDIA Xid crash cascades. |
| **`cpu`** | **Frequency & Governor Tuning**: Displays per-core frequencies, toggles Intel Turbo Boost, switches governors (`performance`, `powersave`), and enforces max frequency ceilings (e.g. 4.0 GHz). |
| **`fan`** | **Firmware Fan Profiles**: Quick switching of vendor-level ACPI/firmware cooling profiles (e.g. Lenovo Legion Quiet, Balanced, Performance). |
| **`check_gpu.sh`** | **NVIDIA Telemetry Watcher**: Cron-friendly background monitor reporting GPU temperatures, VRAM consumption, and throttle events via desktop notifications. |
| **`hardware-optimization.service`** | **Systemd Boot Service**: Automatically applies undervolt, frequency ceilings, and governor profiles on machine boot. |

*Example Commands*:
```bash
# Inspect current voltage offsets and power envelopes
undervolt status

# Run 5-minute stress evaluation and monitor thermals
undervolt eval 5

# Deep hardware register inspection
hardware-register-inspector.sh all
hardware-register-inspector.sh msr
hardware-register-inspector.sh gpu
hardware-register-inspector.sh journal

# CPU frequency management
cpu status
cpu profile performance
cpu max 4000
```

---

### 3. Gaming & Adaptive Frame Generation Suite (`gaming/`)
**Entrypoints**: `gaming`, `gaming-doctor`, `lossless-scaling.sh`, `witcher3-framegen.sh`, `rome-total-framegen.sh`

Complete Linux gaming launcher, Proton environment validator, and Lossless Scaling frame generation suite.

| Utility / Script | Use Case & What It Is For |
| :--- | :--- |
| **`gaming`** | **Gaming Command Center**: Inventories Steam, non-Steam, and Flatpak games; checks Proton prefixes; and dispatches games with MangoHud and Prime GPU offload. |
| **`gaming-doctor`** | **Graphics Stack Diagnostic**: Validates Vulkan ICDs, 32-bit GL drivers, NVIDIA Prime offload, Proton prefixes, and input lag optimizations. |
| **`lossless-scaling.sh`** | **Standalone Lossless Scaling Companion Controller**: Manages Lossless Scaling (LSFG 3.0) under Proton with dedicated NVIDIA GPU offload. Automatically detects game windows, tunes `Settings.xml` (Adaptive 100/120/144/160 FPS, 2x/3x/4x multipliers), and triggers hotkeys (`Ctrl+Alt+S`) via `xdotool`. |
| **`witcher3-framegen.sh`** | **The Witcher 3 DX12 Launcher**: Enforces borderless window mode, 60 FPS in-engine cap (guaranteeing steady pacing and 35% GPU headroom), disables VSync, enables NVIDIA Reflex, pins Alder Lake P-cores (CPUs 0-7), bypasses anti-Wine DLSS blocks (`frog_get_version`), and synchronizes LSFG 3.0 for 120 FPS target. |
| **`rome-total-framegen.sh`** | **Total War: ROME REMASTERED Launcher**: Isolates CPU affinity to P-cores (0-7), elevates single-core turbo ceiling to 4.2 GHz for RTS battle simulation, and offloads rendering to NVIDIA RTX 3050. |

*Example Commands*:
```bash
# Witcher 3 with 120 FPS target (60 FPS base + 2x LSFG 3.0)
gaming framegen witcher 120
gaming framegen witcher status

# Standalone Lossless Scaling Controller
lossless-scaling.sh start 100 2     # Start companion for 100 FPS target (2x)
lossless-scaling.sh profile 3x 144  # Switch to 3x profile (144 FPS target)
lossless-scaling.sh detect          # Detect active game process and window ID
lossless-scaling.sh engage          # Focus game window and trigger frame generation
```

---

### 4. Homelab Cybersecurity & Pentest Toolkit (`security/`)
**Entrypoint**: `security`

A non-destructive, CLI-first cybersecurity and reconnaissance toolkit for homelab administration, local host hardening audits, and pentest lab management.

| Subcommand | Use Case & What It Is For |
| :--- | :--- |
| **`security audit host`** | **Local Hardening Audit**: Audits listening ports on `0.0.0.0`, SUID binaries, SSH configuration, active firewall rules (`ufw`, `nftables`), and world-writable files. |
| **`security network`** | **Subnet & Port Reconnaissance**: Subnet discovery to map online devices across local VLANs and TCP port scanning using native sockets or `nmap`. |
| **`security capacity`** | **Resilience & Stress Testing**: Non-destructive concurrency, throughput, and rate-limiting stress testing against web services. |
| **`security headers` / `ssl`** | **Web & TLS Audit**: Verifies HTTP security response headers (`HSTS`, `CSP`, `X-Frame-Options`) and validates SSL/TLS certificate chains and cipher negotiation. |
| **`security kali`** | **Kali Linux VM Lab Bridge**: Health check, status, and direct command execution / X11 forwarding connector for remote Kali Linux VM 210 (`192.168.4.131`). |
| **`security cheatsheet`** | **Offline Security Reference**: Fast syntax recall for Nmap, Wireshark, Metasploit, Gobuster, SQLMap, and Linux privilege escalation. |

*Example Commands*:
```bash
# Audit host security posture
security audit host
security audit ports
security audit ssh

# Network scanning
security scan 192.168.0.0/24
security ports 192.168.4.110

# Kali Linux VM integration
security kali status
security kali claude
security kali x11 wireshark
```

---

### 5. AI & Local LLM Telemetry (`ai/`)
**Entrypoint**: `ai`

Read-only inspection and resource management for local LLM runtimes (Ollama, llama-server).

| Command | Use Case & What It Is For |
| :--- | :--- |
| `ai status` | Inspects running inference servers, loaded models, and GPU VRAM consumption. |
| `ai models` | Lists locally cached models, parameter sizes, and quantization formats. |
| `ai check <model>` | Evaluates whether a model will fit in available RAM/VRAM before launch. |
| `ai diagnose` | Checks GPU driver offload, compute layers, and context memory allocations. |
| `ai stop <model>` | Explicitly unloads a model from memory to free VRAM for gaming or other tasks. |

---

### 6. Desktop & Productivity (`desktop/`)
**Entrypoint**: `desktop/open-project-terminals.sh`

Automated terminal workspace launcher tailored for competitive programming, research, and multi-repo development.

| Feature | Use Case & What It Is For |
| :--- | :--- |
| **`open-project-terminals.sh`** | Launches tiling terminal windows (Neovim, interactive shell, runner) into active project directories. Includes time-of-day and weekend-awareness (UTC+7) to focus on study during weekends and operations during weekdays. |

---

### 7. Network, Infrastructure & Wake-on-LAN (`network/`, `tools/`)
**Entrypoints**: `network/wake.sh`, `tools/sync-codeptit.sh`, `tools/sync-to-home.sh`

| Tool | Use Case & What It Is For |
| :--- | :--- |
| **`wake.sh`** | **Wake-on-LAN**: Broadcasts magic packets to wake up homelab physical nodes or workstations remotely. |
| **`tools/sync-codeptit.sh`** | **Rate-Limited Resilient Sync**: Synchronizes large code repositories to secondary machines over SSH with bandwidth capping (~5 MB/s) and lockfile protection. |
| **`tools/sync-to-home.sh`** | **Safe Home Mirror**: Mirrors toolkit scripts to `~/bash` while strictly preserving repository metadata (`.git`, `.agents`). |

---

## Testing & Quality Assurance

The test suite runs entirely offline without requiring root privileges, live GPUs, or active internet connectivity:

```bash
# Run complete test suite
tests/smoke.sh
tests/safety.sh
tests/test_hardware_register_inspector.sh
tests/test_lossless_scaling_profiles.sh
tests/test_security.sh
tests/test_undervolt.sh
tests/test_witcher_framegen.sh
```

### Anti-Cheat Enforcement
All pull requests and modifications are audited by `anti-cheat-enforcer --diff --require-tests`:
- Rejects error swallowing (`|| true`, empty `except: pass`).
- Rejects shell error masking (`set +e` inside tests).
- Rejects assertion weakening or deletion.
- Ensures all new features and bug fixes have exercising unit tests.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

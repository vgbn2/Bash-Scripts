# Hardware Operations & Kernel Telemetry

This directory contains hardware optimization, CPU/GPU undervolting, register interrogation, cooling profile, and thermal monitoring utilities.

## Utilities & Use Cases

### 1. `undervolt` — CPU & GPU Voltage / Frequency Management
- **Use Case**: Eliminates thermal throttling, decreases fan noise, and increases sustained clock speeds on Intel Core (10th/11th/12th Gen hybrid), AMD Ryzen, and NVIDIA mobile/desktop GPUs.
- **Commands**:
  - `undervolt status`: Display current CPU core/cache voltage offsets and GPU clock/power envelopes.
  - `undervolt eval [minutes]`: Benchmark stability and log thermals under stress.
  - `undervolt set core <mV> cache <mV>`: Apply manual voltage offsets (e.g. `-80 -80`).
  - `undervolt gpu <clock_mhz> <power_watts>`: Clamp NVIDIA GPU maximum graphics clocks and power limits.
  - `undervolt reset`: Safely restore stock voltage and power profiles.

### 2. `hardware-register-inspector.sh` — MSR, PCIe & Kernel Forensics
- **Use Case**: Direct hardware interrogation for diagnosing IOMMU DMA faults, PCIe lane degradation, NVML throttle causes, and CPU register states.
- **Commands**:
  - `hardware-register-inspector.sh all`: Complete system audit (CPU MSRs, PCIe config space, NVML telemetry, kernel journal).
  - `hardware-register-inspector.sh msr`: Inspect CPU Package Thermals, PL1/PL2 power limits (`MSR 0x610`), Voltage planes (`MSR 0x150`), and Energy Policy (`MSR 0x1B0`).
  - `hardware-register-inspector.sh pcie`: Decode PCIe Type 0 configuration header, Bus Master DMA enable, Link Width/Speed.
  - `hardware-register-inspector.sh gpu`: Decode NVML active throttle bitmasks (Thermal, Power, Reliability, SW Power cap).
  - `hardware-register-inspector.sh journal`: Scan kernel dmesg for Intel VT-d DMAR faults, NVIDIA Xid events, and MCEs.

### 3. `cpu` — Frequency & Governor Management
- **Use Case**: Enforces steady clock frequencies for competitive programming, low-latency gaming, or powersaving.
- **Commands**:
  - `cpu status`: Show per-core frequencies, current governor (`performance`/`powersave`), and turbo status.
  - `cpu profile [performance|balanced|battery]`: Quick-switch scaling governor across all threads.
  - `cpu turbo [on|off]`: Toggle Intel Turbo Boost.
  - `cpu max <MHz>`: Set hard upper ceiling for CPU scaling frequency.

### 4. `fan` — Firmware Cooling Profiles
- **Use Case**: Quick switching of vendor-level ACPI/firmware cooling profiles (e.g. Lenovo Legion / ThinkPad).
- **Commands**:
  - `fan status`: Show current active thermal/fan profile.
  - `fan quiet | fan balanced | fan performance`: Switch firmware profile.

### 5. `check_gpu.sh` — NVIDIA Telemetry & Cron Health Check
- **Use Case**: Lightweight, cron-friendly background watcher reporting GPU temperatures, VRAM usage, and throttle states via desktop notifications (`notify-send`).

### 6. `hardware-optimization.service` & `cpu-frequency-4ghz.service` — Systemd Units
- **Use Case**: Boots directly into optimized hardware settings, applying undervolts and 4.0 GHz CPU clock limits automatically without manual intervention.

## Integration

All utilities integrate directly into the `system` CLI:

```bash
system cpu status
system undervolt status
system gpu health
system thermals watch 80 10
```

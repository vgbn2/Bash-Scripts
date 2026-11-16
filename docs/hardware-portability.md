# Generic Hardware Control & Portability Contract

This document specifies the contracts, failure behavior, and verification procedures for `hardware/cpu`, `hardware/undervolt`, and `gaming/rome-total-framegen.sh`.

## 1. Architectural Contracts

### Dynamic Bound Discovery (`hardware/cpu`)
- **Sysfs Discovery**: CPU frequency limits are dynamically discovered from `/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq` and `cpuinfo_max_freq` (or `policy0`). Static laptop limits (2.4–4.4 GHz) are removed.
- **Multi-Vendor Turbo Control**:
  - Intel: `/sys/devices/system/cpu/intel_pstate/no_turbo` (0=on, 1=off).
  - AMD / Generic: `/sys/devices/system/cpu/cpufreq/boost` (1=on, 0=off).
  - Unsupported hosts report `turbo control is not supported on this CPU / governor` and exit nonzero without corrupting state.
- **Fail-Closed Scaling**: If cpufreq sysfs files are missing or unwritable, `cpu <GHz>` reports failure and exits nonzero.
- **Platform Profile Fault Tolerance**: Preset commands (`cool`, `balanced`, `game`, `full`) do not crash when ACPI `platform_profile` is absent (e.g. desktop PCs, VMs).

### Fail-Closed Persistence (`hardware/undervolt`)
- **Explicit Parameter Requirement**: `undervolt service <unit|enable|apply>` requires explicit user-provided tuning parameters (`core_mV`, `cache_mV`, `PL1_W`, `PL2_W`).
- **No Implicit Laptop Defaults**: Hardcoded laptop defaults (-60 mV, 28/35 W, 3.2 GHz, 210–1600 MHz) are removed. If arguments are omitted, the tool fails closed with exit code 2 and usage instructions.
- **Minimal Service Generation**: Optional controls (CPU frequency ceiling and GPU clock lock) are only included in the generated systemd unit if explicitly specified by the user.

### Safe Game Launching (`gaming/rome-total-framegen.sh`)
- **Zero-Side-Effect Help**: `-h` and `--help` parse arguments first and exit 0 without executing sysfs writes, Steam URI dispatches, or background processes.
- **Opt-In CPU Pinning & Frequency Elevation**: Core pinning (`--pin <cores>`) and frequency elevation (`--freq <kHz>`) are opt-in. Without explicit flags, the native OS scheduler and current governor ceilings are preserved.
- **Dry-Run Mode**: `--dry-run` validates parameters and outputs the execution plan without side effects.

---

## 2. 4-Tier Operational Runbook

### 1. Inspection & Diagnostic Probes (Read-Only)
```bash
# Probe current CPU status, governor bounds, and turbo state
hardware/cpu status # inspect profile, turbo, package temp, and detected min/max GHz bounds

# Verify game launcher help without side effects
gaming/rome-total-framegen.sh --help # must output usage and exit 0 immediately

# Test dry-run execution plan
gaming/rome-total-framegen.sh --dry-run --fps 120 --pin 0-3 # displays target parameters without launching
```

### 2. Remediation & Action (Mutation)
```bash
# Set CPU max frequency within discovered hardware bounds
hardware/cpu 3.3 # sets scaling_max_freq across all cores

# Generate systemd unit with explicit host-specific parameters
hardware/undervolt service unit -45 -45 40 50 3400000 300 1700 # produces custom service unit
```

### 3. Verification & Oracle Gate (Proof)
```bash
# Run pure shell hardware portability test suite
bash tests/test_hardware_generic.sh # must pass all capability and validation assertions with exit code 0
```

### 4. Rollback & Emergency Exit (Safety)
```bash
# Reset CPU undervolt offsets to 0 mV
hardware/undervolt cpu-reset # restores factory voltage offsets

# Restore default governor ceiling to hardware max
hardware/cpu full # resets CPU frequency ceiling to maximum detected limit
```

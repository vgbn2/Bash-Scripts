#!/usr/bin/env bash
# Pure shell regression tests for generic hardware capability discovery and fail-closed tuning.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

ROME_SCRIPT="$REPO_ROOT/gaming/rome-total-framegen.sh"
CPU_SCRIPT="$REPO_ROOT/hardware/cpu"
UV_SCRIPT="$REPO_ROOT/hardware/undervolt"

TEMP_DIR=$(mktemp -d /tmp/opencode/hw-test-XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM

assert() {
    local msg="$1"
    shift
    if ! "$@"; then
        echo "FAIL: $msg" >&2
        exit 1
    fi
}

assert_match() {
    local pattern="$1"
    local file="$2"
    if ! grep -q "$pattern" "$file"; then
        echo "FAIL: pattern '$pattern' not found in $file" >&2
        exit 1
    fi
}

# ==============================================================================
# 1. Total War: ROME Framegen Launcher Safety & Argument Validation
# ==============================================================================

# 1.1 -h and --help must exit 0 without launching game or writing sysfs
rc=0
help_out=$(bash "$ROME_SCRIPT" --help 2>&1) || rc=$?
assert "rome-total-framegen --help must exit 0" test "$rc" -eq 0
assert "rome-total-framegen --help must contain usage info" test -n "$(grep -i 'usage:' <<< "$help_out")"
assert "rome-total-framegen --help must not report game session ended" test -z "$(grep 'Game session ended' <<< "$help_out")"

# 1.2 Invalid arguments must fail with exit 2 and not launch game
rc=0
bad_out=$(bash "$ROME_SCRIPT" --invalid-option 2>&1) || rc=$?
assert "rome-total-framegen invalid option must return nonzero" test "$rc" -ne 0
assert "rome-total-framegen invalid option must explain error" test -n "$(grep 'unknown argument' <<< "$bad_out")"

# 1.3 Bad parameter values must fail validation
rc=0
bash "$ROME_SCRIPT" --fps bad >/dev/null 2>&1 || rc=$?
assert "rome-total-framegen bad --fps must exit nonzero" test "$rc" -ne 0

rc=0
bash "$ROME_SCRIPT" --pin "bad;rm -rf" >/dev/null 2>&1 || rc=$?
assert "rome-total-framegen bad --pin syntax must exit nonzero" test "$rc" -ne 0

rc=0
bash "$ROME_SCRIPT" --freq "bad_freq" >/dev/null 2>&1 || rc=$?
assert "rome-total-framegen bad --freq must exit nonzero" test "$rc" -ne 0

# 1.4 --dry-run prints plan and exits 0 cleanly
rc=0
dry_out=$(bash "$ROME_SCRIPT" --dry-run --fps 120 --ls --pin 0-3 2>&1) || rc=$?
assert "rome-total-framegen --dry-run must exit 0" test "$rc" -eq 0
assert "rome-total-framegen --dry-run must reflect FPS" test -n "$(grep '120' <<< "$dry_out")"
assert "rome-total-framegen --dry-run must reflect pinning" test -n "$(grep '0-3' <<< "$dry_out")"

# ==============================================================================
# 2. Hardware CPU Controller: Dynamic Bounds & Multi-Vendor Turbo
# ==============================================================================

# 2.1 Help without side-effects
rc=0
cpu_help=$(bash "$CPU_SCRIPT" --help 2>&1) || rc=$?
assert "cpu --help must exit 0" test "$rc" -eq 0
assert "cpu --help must show usage" test -n "$(grep 'usage: cpu' <<< "$cpu_help")"

rc=0
bash "$CPU_SCRIPT" invalid-cmd >/dev/null 2>&1 || rc=$?
assert "cpu invalid command must exit nonzero" test "$rc" -ne 0

# 2.2 Dynamic bounds discovery with fixture sysfs (min=1.2GHz, max=3.6GHz)
MOCK_SYSFS="$TEMP_DIR/mock_sysfs"
mkdir -p "$MOCK_SYSFS/devices/system/cpu/cpu0/cpufreq"
mkdir -p "$MOCK_SYSFS/devices/system/cpu/cpufreq"
printf '1200000\n' > "$MOCK_SYSFS/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq"
printf '3600000\n' > "$MOCK_SYSFS/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
printf '2400000\n' > "$MOCK_SYSFS/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
printf '3600000\n' > "$MOCK_SYSFS/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"

# Under mock bounds: 0.8 GHz is below min (1.2 GHz) and must be rejected
rc=0
SYSFS_CPU_DIR="$MOCK_SYSFS/devices/system/cpu" bash "$CPU_SCRIPT" 0.8 >/dev/null 2>&1 || rc=$?
assert "cpu setting below discovered min frequency must be rejected" test "$rc" -ne 0

# 4.0 GHz is above max (3.6 GHz) and must be rejected
rc=0
SYSFS_CPU_DIR="$MOCK_SYSFS/devices/system/cpu" bash "$CPU_SCRIPT" 4.0 >/dev/null 2>&1 || rc=$?
assert "cpu setting above discovered max frequency must be rejected" test "$rc" -ne 0

# 2.3 AMD / Generic cpufreq boost turbo support
printf '0\n' > "$MOCK_SYSFS/devices/system/cpu/cpufreq/boost"
status_out=$(SYSFS_CPU_DIR="$MOCK_SYSFS/devices/system/cpu" bash "$CPU_SCRIPT" status 2>&1)
assert "cpu status with boost=0 must report turbo=off" test -n "$(grep 'turbo=off' <<< "$status_out")"

printf '1\n' > "$MOCK_SYSFS/devices/system/cpu/cpufreq/boost"
status_out=$(SYSFS_CPU_DIR="$MOCK_SYSFS/devices/system/cpu" bash "$CPU_SCRIPT" status 2>&1)
assert "cpu status with boost=1 must report turbo=on" test -n "$(grep 'turbo=on' <<< "$status_out")"

# 2.4 Unsupported turbo returns clear message and nonzero
rm -f "$MOCK_SYSFS/devices/system/cpu/cpufreq/boost"
rc=0
turbo_out=$(SYSFS_CPU_DIR="$MOCK_SYSFS/devices/system/cpu" TURBO_PATH="" bash "$CPU_SCRIPT" turbo on 2>&1) || rc=$?
assert "cpu turbo on without supported sysfs must exit nonzero" test "$rc" -ne 0
assert "cpu turbo on must explain lack of support" test -n "$(grep -i 'not supported' <<< "$turbo_out")"

# ==============================================================================
# 3. Hardware Undervolt Service: Fail Closed on Missing Parameters
# ==============================================================================

# 3.1 Help exits 0
rc=0
uv_help=$(bash "$UV_SCRIPT" help 2>&1) || rc=$?
assert "undervolt help must exit 0" test "$rc" -eq 0

# 3.2 Service apply and enable WITHOUT parameters must fail closed (exit nonzero)
rc=0
apply_err=$(bash "$UV_SCRIPT" service apply 2>&1) || rc=$?
assert "undervolt service apply without parameters must exit nonzero" test "$rc" -ne 0
assert "undervolt service apply without parameters must report required parameters" test -n "$(grep -i 'explicit parameters required' <<< "$apply_err")"

rc=0
enable_err=$(bash "$UV_SCRIPT" service enable 2>&1) || rc=$?
assert "undervolt service enable without parameters must exit nonzero" test "$rc" -ne 0
assert "undervolt service enable without parameters must report required parameters" test -n "$(grep -i 'explicit parameters required' <<< "$enable_err")"

# 3.3 Service unit generation WITH explicit parameters generates unit without laptop defaults
unit_file="$TEMP_DIR/generated_service.unit"
bash "$UV_SCRIPT" service unit -45 -45 40 50 3400000 300 1700 > "$unit_file"
assert_match "undervolt --core -45 --cache -45 -p1 40" "$unit_file"
assert_match "echo 3400000" "$unit_file"
assert_match "nvidia-smi -lgc 300,1700" "$unit_file"

# Ensure laptop hardcoded defaults (-60mV, 28/35W) are NOT in the output
assert "Unit must not contain hardcoded -60mV core" test -z "$(grep -- '--core -60' "$unit_file")"
assert "Unit must not contain hardcoded -60mV cache" test -z "$(grep -- '--cache -60' "$unit_file")"
assert "Unit must not contain hardcoded 28W PL1" test -z "$(grep -- '-p1 28 28' "$unit_file")"
assert "Unit must not contain hardcoded 35W PL2" test -z "$(grep -- '-p2 35 ' "$unit_file")"

# 3.4 Service unit generation with only undervolt/power (no optional GPU/freq) omits GPU/freq lines
unit_minimal="$TEMP_DIR/generated_minimal.unit"
bash "$UV_SCRIPT" service unit -30 -30 65 85 > "$unit_minimal"
assert_match "undervolt --core -30 --cache -30 -p1 65" "$unit_minimal"
assert "Minimal unit must not contain scaling_max_freq write" test -z "$(grep 'scaling_max_freq' "$unit_minimal")"
assert "Minimal unit must not contain nvidia-smi lock" test -z "$(grep 'nvidia-smi' "$unit_minimal")"

echo "PASS: test_hardware_generic.sh (all assertions passed cleanly)"

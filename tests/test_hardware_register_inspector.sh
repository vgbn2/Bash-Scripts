#!/usr/bin/env bash
# Unit tests for hardware-register-inspector.sh
# Tests MSR decoding, PCIe sysfs inspection, GPU NVML bitmasks, and DMAR fault detection.
#
# ponytail: assert-based self-check using mock environment overrides; zero external test runners.

set -euo pipefail

TOOL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
INSPECTOR="$TOOL_ROOT/hardware/hardware-register-inspector.sh"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_status() {
    local expected=$1
    shift
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    [ "$actual" -eq "$expected" ] || fail "expected status $expected, got $actual: $*"
}

assert_match() {
    local pattern=$1
    local text=$2
    if ! grep -Eq "$pattern" <<< "$text"; then
        fail "pattern '$pattern' not found in text: $text"
    fi
}

# 1. Test CLI arguments & help
test_cli_args() {
    assert_status 0 "$INSPECTOR" help
    assert_status 0 "$INSPECTOR" -h
    assert_status 0 "$INSPECTOR" --help
    assert_status 2 "$INSPECTOR" invalid_action
    assert_status 2 "$INSPECTOR" unknown_subcommand
}

# 2. Test MSR decoding via mock register values
test_msr_decoding() {
    local out

    # MSR 0x198: IA32_PERF_STATUS (32x multiplier, 8267 VID -> 1.0092V)
    out=$(MSR_OVERRIDE_0x198="0x0000204b00002000" "$INSPECTOR" msr 0x198)
    assert_match "MSR 0x198: IA32_PERF_STATUS" "$out"
    assert_match "Current Multiplier.*32x" "$out"
    assert_match "Effective Core Frequency.*3200.0 MHz" "$out"
    assert_match "Current Voltage VID Code.*0x204b" "$out"
    assert_match "Effective Core Voltage.*1.0092 V" "$out"

    # MSR 0x199: IA32_PERF_CTL (41x target ratio, Turbo enabled)
    out=$(MSR_OVERRIDE_0x199="0x0000000000002900" "$INSPECTOR" msr 0x199)
    assert_match "MSR 0x199: IA32_PERF_CTL" "$out"
    assert_match "Target Multiplier Request.*41x" "$out"
    assert_match "Turbo Disengage.*Turbo Enabled/Engaged" "$out"

    # MSR 0x1B0: IA32_ENERGY_PERF_BIAS (Performance = 0, Power = 15)
    out=$(MSR_OVERRIDE_0x1b0="0x0000000000000000" "$INSPECTOR" msr 0x1b0)
    assert_match "EPB Value.*0" "$out"
    assert_match "Maximum responsiveness" "$out"

    out=$(MSR_OVERRIDE_0x1b0="0x000000000000000f" "$INSPECTOR" msr 0x1b0)
    assert_match "EPB Value.*15" "$out"
    assert_match "Power Saver" "$out"

    # MSR 0x610: MSR_PKG_POWER_LIMIT (PL1 = 28W, PL2 = 35W)
    out=$(MSR_OVERRIDE_0x610="0x0042811800dd80e0" MSR_OVERRIDE_0x606="0x000a0e03" "$INSPECTOR" msr 0x610)
    assert_match "PL1 Sustained Power Limit.*28.0 W" "$out"
    assert_match "PL2 Burst Peak Power Limit.*35.0 W" "$out"
    assert_match "PL1 Time Window.*28.0000 seconds" "$out"
    assert_match "RAPL Configuration Lock.*0.*UNLOCKED" "$out"

    # MSR 0x150: OC Mailbox
    out=$(MSR_OVERRIDE_0x150="0x0000000000000000" "$INSPECTOR" msr 0x150)
    assert_match "Idle or Locked by Intel Undervolt Protection" "$out"

    # Arbitrary MSR
    out=$(MSR_OVERRIDE_0x1a0="0x0000000000850089" "$INSPECTOR" msr 0x1a0)
    assert_match "MSR 0x1a0: Custom Register Dump" "$out"
    assert_match "Decimal Value" "$out"
    assert_match "Binary \(64-bit\)" "$out"
}

# 3. Test PCIe config space and AER decoding via mock sysfs
test_pcie_mock() {
    local mock_sysfs="$TEMP_DIR/mock_sysfs"
    local dev_dir="$mock_sysfs/0000:01:00.0"
    mkdir -p "$dev_dir"

    printf '0x10de\n' > "$dev_dir/vendor"
    printf '0x25ec\n' > "$dev_dir/device"
    printf '16.0 GT/s PCIe\n' > "$dev_dir/current_link_speed"
    printf '16.0 GT/s PCIe\n' > "$dev_dir/max_link_speed"
    printf '8\n' > "$dev_dir/current_link_width"
    printf '16\n' > "$dev_dir/max_link_width"

    cat > "$dev_dir/aer_dev_correctable" <<'EOF'
RxErr 0
BadTLP 0
BadDLLP 0
Rollover 0
Timeout 0
NonFatalErr 0
CorrIntErr 0
HeaderOF 0
TOTAL_ERR_COR 0
EOF

    # Generate synthetic 64-byte Type 0 config header
    # Vendor 0x10DE, Device 0x25EC, Command 0x0407 (Mem+, IO+, BusMaster+), Status 0x0010 (CapList+)
    python3 -c "
with open('$dev_dir/config', 'wb') as f:
    hdr = bytearray(64)
    hdr[0:2] = (0x10de).to_bytes(2, 'little')
    hdr[2:4] = (0x25ec).to_bytes(2, 'little')
    hdr[4:6] = (0x0407).to_bytes(2, 'little')
    hdr[6:8] = (0x0010).to_bytes(2, 'little')
    hdr[8] = 0xa1 # Rev
    hdr[9] = 0x00 # ProgIF
    hdr[10] = 0x00 # SubClass
    hdr[11] = 0x03 # BaseClass (Display controller)
    f.write(hdr)
"

    local out
    out=$(MOCK_SYSFS_DIR="$mock_sysfs" "$INSPECTOR" pcie 01:00.0)
    assert_match "PCIe BDF Address.*0000:01:00.0" "$out"
    assert_match "Vendor ID.*0x10de" "$out"
    assert_match "Current Link Speed.*16.0 GT/s PCIe" "$out"
    assert_match "Current Link Width.*x8" "$out"
    assert_match "Theoretical Bandwidth.*15.75 GB/s" "$out"
    assert_match "Correctable Errors.*0" "$out"
    assert_match "Bus Master DMA Enable.*1" "$out"
}

# 4. Test GPU telemetry & throttle bitmask decode
test_gpu_mock() {
    local fake_bin="$TEMP_DIR/gpu_bin"
    mkdir -p "$fake_bin"

    # Mock nvidia-smi with active SW_POWER_CAP (0x0004) and HW_THERMAL_SLOWDOWN (0x0040)
    cat > "$fake_bin/nvidia-smi" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$*" =~ --query-gpu ]]; then
    # name,driver,pstate,gfx,sm,mem,vid,draw,limit,deflimit,gen_cur,gen_max,w_cur,w_max,throttle_reasons
    echo "NVIDIA RTX Test GPU, 550.54, P0, 1800 MHz, 1800 MHz, 7000 MHz, 1200 MHz, 60.00 W, 60.00 W, 60.00 W, 4, 4, 8, 16, 0x0000000000000044"
    exit 0
fi
exit 1
SCRIPT
    chmod +x "$fake_bin/nvidia-smi"

    local out
    out=$(PATH="$fake_bin:$PATH" "$INSPECTOR" gpu)
    assert_match "GPU: NVIDIA RTX Test GPU" "$out"
    assert_match "Operating Clocks" "$out"
    assert_match "Graphics Core Clock.*1800 MHz" "$out"
    assert_match "Raw Bitmask Register.*0x0000000000000044" "$out"
    assert_match "SW_POWER_CAP" "$out"
    assert_match "HW_THERMAL_SLOWDOWN" "$out"
}

# 5. Test DMAR & Xid kernel log scanner
test_dmar_mock() {
    local journal_mock="$TEMP_DIR/mock_journal.log"

    # Case A: Faults present (DMAR PTE violation + NVRM Xid 31 page fault)
    cat > "$journal_mock" <<'LOG'
Oct 07 10:00:00 host kernel: DMAR: [DMA Read] NO_PASID fault addr 0xdeadbeef000 [PTE Read access is not set]
Oct 07 10:00:01 host kernel: NVRM: Xid (PCI:0000:01:00.0): 31, pid=1234, name=cuda_app, page fault on VRAM
Oct 07 10:00:02 host kernel: mce: [Hardware Error]: Machine check events logged
LOG

    local out
    out=$(MOCK_JOURNAL_FILE="$journal_mock" "$INSPECTOR" dmar)
    assert_match "Detected 1 active VT-d DMAR memory faults" "$out"
    assert_match "PTE access violation" "$out"
    assert_match "Xid 31 -> GPU Memory Page Fault" "$out"
    assert_match "Machine Check Exceptions.*MCE.*logged" "$out"
    assert_match "STATUS: ATTENTION REQUIRED" "$out"

    # Case B: Clean journal
    cat > "$journal_mock" <<'LOG'
Oct 07 10:00:00 host kernel: DMAR: Intel(R) Virtualization Technology for Directed I/O
Oct 07 10:00:01 host kernel: NVRM: loading NVIDIA UNIX x86_64 Kernel Module
LOG

    out=$(MOCK_JOURNAL_FILE="$journal_mock" "$INSPECTOR" dmar)
    assert_match "No active VT-d DMAR DMA faults" "$out"
    assert_match "0 NVRM Xid GPU errors" "$out"
    assert_match "STATUS: HEALTHY" "$out"
}

# 6. Test educational "learn" modules
test_learn_modules() {
    local out
    out=$("$INSPECTOR" learn msr)
    assert_match "EDUCATIONAL MODULE 1: CPU Model-Specific Registers" "$out"
    assert_match "RDMSR" "$out"
    assert_match "Ring 0" "$out"

    out=$("$INSPECTOR" learn pcie)
    assert_match "EDUCATIONAL MODULE 2: PCIe Architecture" "$out"
    assert_match "Transaction Layer Packets" "$out"

    out=$("$INSPECTOR" learn dmar)
    assert_match "EDUCATIONAL MODULE 3: Kernel Page Tables" "$out"
    assert_match "IOMMU" "$out"

    out=$("$INSPECTOR" learn gpu)
    assert_match "EDUCATIONAL MODULE 4: GPU Performance States" "$out"
    assert_match "P-States" "$out"
}

# Run all test suites
test_cli_args
test_msr_decoding
test_pcie_mock
test_gpu_mock
test_dmar_mock
test_learn_modules

echo "PASS: test_hardware_register_inspector.sh completed successfully."

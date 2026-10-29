#!/usr/bin/env bash
# Hardware Register & Kernel Journal Inspector
# Educational Linux diagnostic tool for CPU MSRs, PCIe config space,
# NVIDIA GPU telemetry, and Intel VT-d DMAR / NVRM hardware event streams.
#
# ponytail: stdlib bash + python3 struct/sysfs first; no external pip or C compiler required.
# upgrade path: bind directly to libpci/libmsr C shared objects if microsecond latency needed.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Color codes (disabled if not connected to a terminal)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    BOLD=''
    DIM=''
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    RESET=''
fi

# Print banner & section helpers
print_header() {
    printf "${BOLD}${CYAN}=== %s ===${RESET}\n" "$1"
}

print_subheader() {
    printf "\n${BOLD}${BLUE}--- %s ---${RESET}\n" "$1"
}

print_field() {
    printf "  ${BOLD}%-28s${RESET} : %s\n" "$1" "$2"
}

print_warn() {
    printf "${YELLOW}[WARN] %s${RESET}\n" "$1" >&2
}

print_err() {
    printf "${RED}[ERROR] %s${RESET}\n" "$1" >&2
}

print_note() {
    printf "  ${DIM}%s${RESET}\n" "$1"
}

usage() {
    cat <<'EOF'
Usage: hardware-register-inspector.sh <command> [arguments]

Commands:
  msr [hex_register]   Safely read and decode Intel CPU Model-Specific Registers.
                       Known: 0x198 (PERF_STATUS), 0x199 (PERF_CTL), 0x1B0 (EPB),
                              0x610 (PKG_POWER_LIMIT), 0x150 (OC_MAILBOX).
                       Omit hex_register to inspect all key registers.
  pcie [bdf]           Read and decode PCIe configuration registers and AER errors.
                       Example: pcie 01:00.0 (defaults to primary GPU).
  gpu                  Query NVIDIA GPU clocks, power, PCIe link, and throttle bitmasks.
  dmar                 Scan journalctl -k for VT-d DMAR faults, PTE violations, and NVRM Xid errors.
  learn [topic]        Educational tutorial on CPU MSRs, PCIe TLPs, IOMMU, and GPU hardware.
                       Topics: msr, pcie, dmar, gpu, all.
  help, -h, --help     Show this help guide.

Environment Overrides (Testing & Emulation):
  MSR_OVERRIDE_0x...   Mock 64-bit hex value for MSR reading (e.g. MSR_OVERRIDE_0x198=0x20c300002000).
  MOCK_SYSFS_DIR       Mock directory simulating /sys/bus/pci/devices/<bdf>.
  MOCK_JOURNAL_FILE    Mock file simulating journalctl -k output.
EOF
}

# ------------------------------------------------------------------------------
# 1. CPU MSR Reading & Decoding Engine
# ------------------------------------------------------------------------------

# Safely read 64-bit MSR value.
# Priority:
#   1. Environment mock MSR_OVERRIDE_0x<HEX>
#   2. rdmsr (if installed and permitted)
#   3. Python 3 struct reader on /dev/cpu/<cpu>/msr (via sudo if permitted)
read_raw_msr() {
    local msr_hex=$1
    local cpu=${2:-0}
    local env_var="MSR_OVERRIDE_${msr_hex}"

    # Check mock override first (used for deterministic testing)
    if [ -n "${!env_var:-}" ]; then
        printf '%s\n' "${!env_var}"
        return 0
    fi

    # Check if rdmsr is available
    if command -v rdmsr >/dev/null 2>&1; then
        local val
        if val=$(rdmsr -x -p "$cpu" "$msr_hex" 2>/dev/null); then
            printf '0x%s\n' "$val"
            return 0
        elif [ "$(id -u)" -ne 0 ] && sudo -n true 2>/dev/null; then
            if val=$(sudo -n rdmsr -x -p "$cpu" "$msr_hex" 2>/dev/null); then
                printf '0x%s\n' "$val"
                return 0
            fi
        fi
    fi

    # Native Python 3 struct reader on /dev/cpu/<cpu>/msr
    local py_cmd="
import os, struct, sys
msr = int('$msr_hex', 16)
cpu = int('$cpu')
dev_path = f'/dev/cpu/{cpu}/msr'
try:
    fd = os.open(dev_path, os.O_RDONLY)
    os.lseek(fd, msr, os.SEEK_SET)
    raw = os.read(fd, 8)
    os.close(fd)
    if len(raw) == 8:
        val = struct.unpack('<Q', raw)[0]
        print(f'0x{val:016x}')
        sys.exit(0)
    sys.exit(1)
except PermissionError:
    sys.exit(13)
except FileNotFoundError:
    sys.exit(2)
except Exception:
    sys.exit(1)
"
    local out=""
    local ret=0
    if out=$(python3 -c "$py_cmd" 2>/dev/null); then
        printf '%s\n' "$out"
        return 0
    else
        ret=$?
    fi

    if [ "$ret" -eq 13 ] && [ "$(id -u)" -ne 0 ] && sudo -n true 2>/dev/null; then
        # Retry with passwordless sudo if available
        if out=$(sudo -n python3 -c "$py_cmd" 2>/dev/null); then
            printf '%s\n' "$out"
            return 0
        fi
    fi

    # Architectural failure explanation
    if [ "$ret" -eq 13 ]; then
        print_err "Permission denied accessing /dev/cpu/$cpu/msr."
        print_note "Architecture reason: CPU MSRs are privileged Ring 0 registers protected by kernel DAC (0600 root:root) and CAP_SYS_RAWIO."
        print_note "Run with sudo or grant CAP_SYS_RAWIO: sudo $0 msr $msr_hex"
        return 13
    elif [ "$ret" -eq 2 ]; then
        print_err "Device /dev/cpu/$cpu/msr not found. Kernel module 'msr' not loaded."
        print_note "Load the msr driver with: sudo modprobe msr"
        return 2
    fi

    return 1
}

decode_msr_0x198() {
    local raw_hex=$1
    print_subheader "MSR 0x198: IA32_PERF_STATUS (Current Performance & Voltage)"
    print_field "Raw Register Value" "$raw_hex"

    python3 - <<EOF
val = int('$raw_hex', 16)
# Low 32 bits: Bits 8..15 contain current core frequency multiplier (ratio)
ratio = (val >> 8) & 0xFF
freq_mhz = ratio * 100.0

# High 32 bits: Bits 32..47 contain current Voltage Identification (VID) code
vid_code = (val >> 32) & 0xFFFF
# On modern Intel processors (Alder Lake, Raptor Lake, Skylake), VID step is 1/8192 V
voltage_v = vid_code / 8192.0 if vid_code > 0 else 0.0

print(f"  Current Multiplier           : {ratio}x (Ratio = {ratio})")
print(f"  Effective Core Frequency     : {freq_mhz:.1f} MHz ({freq_mhz/1000.0:.2f} GHz)")
if vid_code > 0:
    print(f"  Current Voltage VID Code     : 0x{vid_code:04x} ({vid_code})")
    print(f"  Effective Core Voltage       : {voltage_v:.4f} V")
else:
    print(f"  Current Voltage VID Code     : 0x0000 (Autonomous Hardware P-State Mode)")
EOF
    print_note "Hardware note: Bus clock is 100 MHz. Core Freq = Bus Clock * Multiplier."
}

decode_msr_0x199() {
    local raw_hex=$1
    print_subheader "MSR 0x199: IA32_PERF_CTL (Target Performance Control Request)"
    print_field "Raw Register Value" "$raw_hex"

    python3 - <<EOF
val = int('$raw_hex', 16)
target_ratio = (val >> 8) & 0xFF
target_mhz = target_ratio * 100.0
turbo_disengage = (val >> 32) & 0x1

print(f"  Target Multiplier Request    : {target_ratio}x ({target_mhz:.1f} MHz)")
print(f"  Turbo Disengage (Bit 32)     : {turbo_disengage} ({'Turbo Disabled' if turbo_disengage else 'Turbo Enabled/Engaged'})")
EOF
    print_note "Software writes this register to request SpeedStep/P-State transitions."
}

decode_msr_0x1b0() {
    local raw_hex=$1
    print_subheader "MSR 0x1B0: IA32_ENERGY_PERF_BIAS (Energy Performance Bias - EPB)"
    print_field "Raw Register Value" "$raw_hex"

    python3 - <<EOF
val = int('$raw_hex', 16)
epb = val & 0x0F

epb_map = {
    0x0: "Performance (Maximum responsiveness, prioritize boost clocks over battery)",
    0x4: "Balanced-Performance (Responsive, moderate energy savings)",
    0x6: "Normal / Default (Balanced operation)",
    0x8: "Balanced-Power (Energy-saving bias, conservative turbo transitions)",
    0xF: "Power Saver (Maximum battery life, throttle high power states)"
}
desc = epb_map.get(epb, f"Custom Bias Level ({epb}/15)")
print(f"  EPB Value (Bits 3:0)         : {epb} (0x{epb:x})")
print(f"  Hardware Operating Profile   : {desc}")
EOF
    print_note "EPB informs autonomous hardware power management how aggressively to boost."
}

# ==============================================================================
# TODO(human): Collaborative Learning Exercise - Bitmask & Exponent Decoding
# ==============================================================================
# Challenge:
# Intel RAPL (Running Average Power Limit) registers encode time windows
# using a floating-point-like representation:
#   - Exponent Y = Bits [21:17] (5 bits)
#   - Fraction Z = Bits [23:22] (2 bits)
#   - Formula: Time = (2^Y) * (1.0 + Z / 4.0) * Time_Unit_Seconds
#
# Inspect the implementation below inside decode_msr_0x610.
# Try modifying or implementing a helper to decode the Secondary Power Limit (PL2)
# Time Window (Bits 49..55) or experimenting with different Y and Z values!
# ==============================================================================
decode_msr_0x610() {
    local raw_hex=$1
    local unit_hex=${2:-""}

    print_subheader "MSR 0x610: MSR_PKG_POWER_LIMIT (Package RAPL PL1 / PL2 Limits)"
    print_field "Raw Register Value" "$raw_hex"

    if [ -z "$unit_hex" ]; then
        unit_hex=$(read_raw_msr "0x606" 2>/dev/null || echo "0x000a0e03")
    fi

    python3 - <<EOF
val = int('$raw_hex', 16)
unit_val = int('$unit_hex', 16)

# MSR 0x606 RAPL_POWER_UNIT:
# Bits 0..3: Power Units = 1 / (2^PU) Watts
# Bits 16..19: Time Units = 1 / (2^TU) Seconds
pu = unit_val & 0x0F
tu = (unit_val >> 16) & 0x0F
p_unit = 1.0 / (2 ** pu)
t_unit = 1.0 / (2 ** tu)

# PL1 (Power Limit 1 - Long Term / Sustained)
pl1_raw = val & 0x7FFF
pl1_watts = pl1_raw * p_unit
pl1_enabled = (val >> 15) & 0x1
pl1_clamping = (val >> 16) & 0x1

# PL1 Time Window: Y in bits 17..21, Z in bits 22..23
y1 = (val >> 17) & 0x1F
z1 = (val >> 22) & 0x03
tw1 = (2 ** y1) * (1.0 + (z1 / 4.0)) * t_unit

# PL2 (Power Limit 2 - Short Term / Burst Peak)
pl2_raw = (val >> 32) & 0x7FFF
pl2_watts = pl2_raw * p_unit
pl2_enabled = (val >> 47) & 0x1
pl2_clamping = (val >> 48) & 0x1

# PL2 Time Window: Y2 in bits 49..53, Z2 in bits 54..55
y2 = (val >> 49) & 0x1F
z2 = (val >> 54) & 0x03
tw2 = (2 ** y2) * (1.0 + (z2 / 4.0)) * t_unit

pkg_locked = (val >> 63) & 0x1

print(f"  RAPL Units Base              : Power Unit = {p_unit:.4f} W, Time Unit = {t_unit:.6f} s")
print(f"  PL1 Sustained Power Limit    : {pl1_watts:.1f} W (Raw: {pl1_raw}, Enabled: {pl1_enabled}, Clamp: {pl1_clamping})")
print(f"  PL1 Time Window (Tau)        : {tw1:.4f} seconds (Y={y1}, Z={z1})")
print(f"  PL2 Burst Peak Power Limit   : {pl2_watts:.1f} W (Raw: {pl2_raw}, Enabled: {pl2_enabled}, Clamp: {pl2_clamping})")
print(f"  PL2 Time Window (Tau)        : {tw2:.6f} seconds (Y={y2}, Z={z2})")
print(f"  RAPL Configuration Lock      : {pkg_locked} ({'LOCKED by BIOS/Firmware' if pkg_locked else 'UNLOCKED - Runtime adjustable'})")
EOF
    print_note "RAPL enforces thermal design power (TDP) via running average electrical accounting."
}

decode_msr_0x150() {
    local raw_hex=$1
    print_subheader "MSR 0x150: MSR_OC_VOLTAGE_OFFSET (Overclocking & Undervolt Mailbox)"
    print_field "Raw Register Value" "$raw_hex"

    python3 - <<EOF
val = int('$raw_hex', 16)
print(f"  OC Mailbox Register          : 0x{val:016x}")
if val == 0:
    print(f"  Status                       : Idle or Locked by Intel Undervolt Protection (UVP)")
    print(f"  Hardware explanation         : On modern Intel 12th+ Gen (Alder Lake/Raptor Lake),")
    print(f"                                 BIOS Undervolt Protection locks write-back to prevent")
    print(f"                                 Plundervolt (CVE-2019-11157) fault-injection attacks.")
else:
    cmd = (val >> 32) & 0xFFFFFFFF
    data = val & 0xFFFFFFFF
    print(f"  Mailbox Command              : 0x{cmd:08x}")
    print(f"  Mailbox Data Payload         : 0x{data:08x}")
EOF
}

decode_arbitrary_msr() {
    local msr_hex=$1
    local raw_hex=$2
    print_subheader "MSR $msr_hex: Custom Register Dump"
    print_field "Hex Value" "$raw_hex"

    python3 - <<EOF
val = int('$raw_hex', 16)
print(f"  Decimal Value                : {val}")
print(f"  Binary (64-bit)              : {val:064b}")
print(f"  Low 32-bit DWORD             : 0x{(val & 0xFFFFFFFF):08x}")
print(f"  High 32-bit DWORD            : 0x{((val >> 32) & 0xFFFFFFFF):08x}")
EOF
}

cmd_msr() {
    local target_reg=${1:-""}

    print_header "Intel CPU Model-Specific Register (MSR) Inspector"
    print_note "MSRs provide direct hardware telemetry on voltage, multipliers, and power limits."

    if [ -n "$target_reg" ]; then
        # Normalize hex prefix
        if [[ ! "$target_reg" =~ ^0x ]]; then
            target_reg="0x$target_reg"
        fi

        local raw_val
        if ! raw_val=$(read_raw_msr "$target_reg"); then
            exit 1
        fi

        case "${target_reg,,}" in
            0x198) decode_msr_0x198 "$raw_val" ;;
            0x199) decode_msr_0x199 "$raw_val" ;;
            0x1b0) decode_msr_0x1b0 "$raw_val" ;;
            0x610) decode_msr_0x610 "$raw_val" ;;
            0x150) decode_msr_0x150 "$raw_val" ;;
            *)     decode_arbitrary_msr "$target_reg" "$raw_val" ;;
        esac
    else
        # Inspect all key registers
        local regs=("0x198" "0x199" "0x1b0" "0x610" "0x150")
        for reg in "${regs[@]}"; do
            local raw_val
            if raw_val=$(read_raw_msr "$reg" 2>/dev/null); then
                case "$reg" in
                    0x198) decode_msr_0x198 "$raw_val" ;;
                    0x199) decode_msr_0x199 "$raw_val" ;;
                    0x1b0) decode_msr_0x1b0 "$raw_val" ;;
                    0x610) decode_msr_0x610 "$raw_val" ;;
                    0x150) decode_msr_0x150 "$raw_val" ;;
                esac
            else
                print_warn "Could not read $reg (requires CAP_SYS_RAWIO or mock environment)."
            fi
        done
    fi
}

# ------------------------------------------------------------------------------
# 2. PCIe Configuration Space & AER Decoder Engine
# ------------------------------------------------------------------------------

# Normalize BDF format (e.g. "01:00.0" -> "0000:01:00.0")
normalize_bdf() {
    local input=$1
    if [[ "$input" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]$ ]]; then
        printf '%s\n' "$input"
    elif [[ "$input" =~ ^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]$ ]]; then
        printf '0000:%s\n' "$input"
    else
        printf '%s\n' "$input"
    fi
}

# Autodetect discrete or primary GPU PCIe BDF
find_default_pci_bdf() {
    if [ -n "${MOCK_SYSFS_DIR:-}" ]; then
        local first_dir
        first_dir=$(find "$MOCK_SYSFS_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)
        if [ -n "$first_dir" ]; then
            basename "$first_dir"
            return 0
        fi
    fi

    # Try detecting NVIDIA discrete GPU first
    local bdf
    bdf=$(lspci -D 2>/dev/null | grep -i 'NVIDIA' | grep -iE 'VGA|3D|Display' | awk '{print $1}' | head -n 1)
    if [ -n "$bdf" ]; then
        printf '%s\n' "$bdf"
        return 0
    fi

    # Fallback to any VGA/3D/Display controller
    bdf=$(lspci -D 2>/dev/null | grep -iE '(VGA|3D|Display)' | awk '{print $1}' | head -n 1)
    if [ -n "$bdf" ]; then
        printf '%s\n' "$bdf"
        return 0
    fi

    # Fallback default
    printf '0000:01:00.0\n'
}

cmd_pcie() {
    local target_bdf=${1:-""}
    if [ -z "$target_bdf" ]; then
        target_bdf=$(find_default_pci_bdf)
    fi
    target_bdf=$(normalize_bdf "$target_bdf")

    local sysfs_dir="${MOCK_SYSFS_DIR:-/sys/bus/pci/devices}/$target_bdf"

    print_header "PCIe Configuration Space & Link Inspector ($target_bdf)"
    print_note "PCIe devices communicate via Transaction Layer Packets (TLPs) over point-to-point serial links."

    if [ ! -d "$sysfs_dir" ]; then
        print_err "PCIe device $target_bdf not found in $sysfs_dir"
        exit 1
    fi

    # 1. Device identification
    local vendor="unknown" device_id="unknown"
    if [ -f "$sysfs_dir/vendor" ]; then vendor=$(cat "$sysfs_dir/vendor"); fi
    if [ -f "$sysfs_dir/device" ]; then device_id=$(cat "$sysfs_dir/device"); fi

    print_subheader "Device Identification"
    print_field "PCIe BDF Address" "$target_bdf"
    print_field "Vendor ID" "$vendor"
    print_field "Device ID" "$device_id"

    # 2. Link Speed & Width
    local cur_speed="unknown" max_speed="unknown"
    local cur_width="unknown" max_width="unknown"

    if [ -f "$sysfs_dir/current_link_speed" ]; then cur_speed=$(cat "$sysfs_dir/current_link_speed"); fi
    if [ -f "$sysfs_dir/max_link_speed" ]; then max_speed=$(cat "$sysfs_dir/max_link_speed"); fi
    if [ -f "$sysfs_dir/current_link_width" ]; then cur_width=$(cat "$sysfs_dir/current_link_width"); fi
    if [ -f "$sysfs_dir/max_link_width" ]; then max_width=$(cat "$sysfs_dir/max_link_width"); fi

    print_subheader "PCIe Link State & Negotiation"
    print_field "Current Link Speed" "$cur_speed"
    print_field "Max Supported Speed" "$max_speed"
    print_field "Current Link Width" "x$cur_width"
    print_field "Max Supported Width" "x$max_width"

    # Bandwidth calculation
    python3 - <<EOF
speed_str = "$cur_speed"
width_str = "$cur_width"
try:
    width = int(width_str)
    # Estimate raw bandwidth per lane:
    # Gen 1 (2.5 GT/s): ~250 MB/s per lane (8b/10b)
    # Gen 2 (5.0 GT/s): ~500 MB/s per lane (8b/10b)
    # Gen 3 (8.0 GT/s): ~985 MB/s per lane (128b/130b)
    # Gen 4 (16.0 GT/s): ~1969 MB/s per lane (128b/130b)
    # Gen 5 (32.0 GT/s): ~3938 MB/s per lane (128b/130b)
    gb_per_lane = 0.0
    if "2.5" in speed_str: gb_per_lane = 0.25
    elif "5.0" in speed_str: gb_per_lane = 0.50
    elif "8.0" in speed_str: gb_per_lane = 0.985
    elif "16.0" in speed_str: gb_per_lane = 1.969
    elif "32.0" in speed_str: gb_per_lane = 3.938

    if gb_per_lane > 0.0:
        total_bw = gb_per_lane * width
        print(f"  Theoretical Bandwidth        : {total_bw:.2f} GB/s (Simplex)")
        print(f"  Bidirectional Bandwidth      : {total_bw * 2.0:.2f} GB/s")
except (ValueError, TypeError) as err:
    sys.stderr.write(f"Bandwidth calculation skipped: {err}\n")
EOF

    # 3. AER (Advanced Error Reporting)
    print_subheader "AER (Advanced Error Reporting) Hardware Counters"
    local aer_corr_file="$sysfs_dir/aer_dev_correctable"
    local aer_fatal_file="$sysfs_dir/aer_dev_fatal"
    local aer_nonfatal_file="$sysfs_dir/aer_dev_nonfatal"

    local has_aer=0
    if [ -f "$aer_corr_file" ]; then
        has_aer=1
        local total_corr
        total_corr=$(grep -F 'TOTAL_ERR_COR' "$aer_corr_file" | awk '{print $2}' || echo "0")
        print_field "Correctable Errors (Total)" "$total_corr"
        if [ "$total_corr" != "0" ] && [ -n "$total_corr" ]; then
            print_warn "Correctable PCIe errors detected! Detailed breakdown:"
            while IFS= read -r line; do
                printf "    ${YELLOW}%s${RESET}\n" "$line"
            done < "$aer_corr_file"
        else
            print_note "Link Quality: EXCELLENT (0 packet transmission errors, 0 corrupted TLPs/DLLPs)"
        fi
    fi

    if [ -f "$aer_fatal_file" ]; then
        has_aer=1
        local total_fatal
        total_fatal=$(grep -F 'TOTAL_ERR_FATAL' "$aer_fatal_file" 2>/dev/null | awk '{print $2}' || cat "$aer_fatal_file" 2>/dev/null || echo "0")
        print_field "Fatal Errors (Total)" "$total_fatal"
    fi

    if [ -f "$aer_nonfatal_file" ]; then
        has_aer=1
        local total_nonfatal
        total_nonfatal=$(grep -F 'TOTAL_ERR_NONFATAL' "$aer_nonfatal_file" 2>/dev/null | awk '{print $2}' || cat "$aer_nonfatal_file" 2>/dev/null || echo "0")
        print_field "Non-Fatal Errors (Total)" "$total_nonfatal"
    fi

    if [ "$has_aer" -eq 0 ]; then
        print_note "AER sysfs node not exposed for this endpoint (device driver or BIOS _OSC may manage errors)."
    fi

    # 4. Binary Configuration Header (Type 0)
    local cfg_file="$sysfs_dir/config"
    if [ -f "$cfg_file" ]; then
        print_subheader "PCIe Type 0 Configuration Header (First 64 Bytes)"
        python3 - <<EOF
try:
    with open('$cfg_file', 'rb') as f:
        raw = f.read(64)
    if len(raw) >= 16:
        ven = int.from_bytes(raw[0:2], 'little')
        dev = int.from_bytes(raw[2:4], 'little')
        cmd = int.from_bytes(raw[4:6], 'little')
        sta = int.from_bytes(raw[6:8], 'little')
        rev = raw[8]
        prog_if = raw[9]
        sub_class = raw[10]
        base_class = raw[11]

        # Command register flags
        io_en = cmd & 1
        mem_en = (cmd >> 1) & 1
        bus_master = (cmd >> 2) & 1
        serr_en = (cmd >> 8) & 1
        int_dis = (cmd >> 10) & 1

        # Status register flags
        int_status = (sta >> 3) & 1
        cap_list = (sta >> 4) & 1

        print(f"  Command Register (0x04)      : 0x{cmd:04x}")
        print(f"    - I/O Space Enable         : {io_en}")
        print(f"    - Memory Space Enable      : {mem_en}")
        print(f"    - Bus Master DMA Enable    : {bus_master} (Required for high-speed device DMA)")
        print(f"    - SERR# System Error Enable: {serr_en}")
        print(f"    - Interrupt Disable        : {int_dis}")
        print(f"  Status Register (0x06)       : 0x{sta:04x}")
        print(f"    - Capabilities List        : {cap_list} (PCIe Extended Capabilities present)")
        print(f"    - Interrupt Status         : {int_status}")
        print(f"  Class Code (0x09..0x0B)      : Base 0x{base_class:02x}, Sub 0x{sub_class:02x}, Prog-IF 0x{prog_if:02x}")
except Exception as e:
    print(f"  Could not read config space  : {e}")
EOF
    fi
}

# ------------------------------------------------------------------------------
# 3. GPU Hardware Telemetry & Throttle Bitmask Decoder
# ------------------------------------------------------------------------------

cmd_gpu() {
    print_header "NVIDIA GPU Hardware Telemetry & Throttle Inspector"
    print_note "Queries NVML hardware registers for clocks, power envelopes, and throttle bitmasks."

    if ! command -v nvidia-smi >/dev/null 2>&1; then
        print_warn "nvidia-smi not found in PATH."
        print_note "Checking Linux Direct Rendering Manager (DRM) sysfs fallback..."
        if [ -d "/sys/class/drm/card0/device" ]; then
            print_field "DRM Primary Card" "$(cat /sys/class/drm/card0/device/uevent | grep -i 'driver' || echo 'Intel/AMD DRM')"
        fi
        return 0
    fi

    # Query NVML properties via nvidia-smi
    local query_out
    if ! query_out=$(nvidia-smi --query-gpu=name,driver_version,pstate,clocks.current.graphics,clocks.current.sm,clocks.current.memory,clocks.current.video,power.draw,power.limit,power.default_limit,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max,clocks_event_reasons.active --format=csv,noheader,nounits 2>/dev/null); then
        print_err "nvidia-smi query failed. NVIDIA driver may not be loaded or GPU is in deep sleep."
        return 1
    fi

    python3 - <<EOF
line = """$query_out""".strip().split('\n')[0]
parts = [p.strip() for p in line.split(',')]

name = parts[0] if len(parts) > 0 else "Unknown GPU"
driver = parts[1] if len(parts) > 1 else "Unknown"
pstate = parts[2] if len(parts) > 2 else "Unknown"
clk_gfx = parts[3] if len(parts) > 3 else "N/A"
clk_sm = parts[4] if len(parts) > 4 else "N/A"
clk_mem = parts[5] if len(parts) > 5 else "N/A"
clk_vid = parts[6] if len(parts) > 6 else "N/A"
pwr_draw = parts[7] if len(parts) > 7 else "N/A"
pwr_limit = parts[8] if len(parts) > 8 else "N/A"
pwr_def = parts[9] if len(parts) > 9 else "N/A"
pcie_gen_cur = parts[10] if len(parts) > 10 else "N/A"
pcie_gen_max = parts[11] if len(parts) > 11 else "N/A"
pcie_w_cur = parts[12] if len(parts) > 12 else "N/A"
pcie_w_max = parts[13] if len(parts) > 13 else "N/A"
throttle_raw = parts[14] if len(parts) > 14 else "0x0"

print(f"=== GPU: {name} ===")
print(f"  Driver Version               : {driver}")
print(f"  Performance State (P-State)  : {pstate} (P0=Max 3D Boost, P8=Idle/Video)")
print(f"")
print(f"--- Operating Clocks ---")
print(f"  Graphics Core Clock          : {clk_gfx} MHz")
print(f"  Streaming Multiprocessor (SM): {clk_sm} MHz")
print(f"  Memory Clock                 : {clk_mem} MHz")
print(f"  Video Decoder Clock          : {clk_vid} MHz")
print(f"")
print(f"--- Power Readings ---")
print(f"  Instantaneous Power Draw     : {pwr_draw} W")
print(f"  Active Power Limit           : {pwr_limit} W (Default: {pwr_def} W)")
print(f"")
print(f"--- PCIe Link Bus ---")
print(f"  PCIe Generation              : Gen{pcie_gen_cur} (Max supported: Gen{pcie_gen_max})")
print(f"  PCIe Link Width              : x{pcie_w_cur} (Max supported: x{pcie_w_max})")
print(f"")
print(f"--- Throttle Event Reasons Bitmask ---")
print(f"  Raw Bitmask Register         : {throttle_raw}")

try:
    mask = int(throttle_raw, 16)
except ValueError:
    mask = 0

# NVML Throttle Bits definition:
# 0x0001: gpuClocksEventReasonIdle
# 0x0002: gpuClocksEventReasonApplicationsClocksSetting
# 0x0004: gpuClocksEventReasonSwPowerCap
# 0x0008: gpuClocksEventReasonHwSlowdown
# 0x0010: gpuClocksEventReasonSyncBoost
# 0x0020: gpuClocksEventReasonSwThermalSlowdown
# 0x0040: gpuClocksEventReasonHwThermalSlowdown
# 0x0080: gpuClocksEventReasonHwPowerBrakeSlowdown
# 0x0100: gpuClocksEventReasonDisplayClockSetting

reasons = [
    (0x0001, "IDLE", "Clocks are at idle levels due to no active compute/render workload (Normal)"),
    (0x0002, "APPLICATION_CLOCKS_SETTING", "Clocks limited by application profile settings"),
    (0x0004, "SW_POWER_CAP", "Software power capping engaged: GPU reached power limit and scaled down"),
    (0x0008, "HW_SLOWDOWN", "Hardware slowdown engaged: Sensor line asserted clock reduction"),
    (0x0010, "SYNC_BOOST", "Multi-GPU synchronization boost active"),
    (0x0020, "SW_THERMAL_SLOWDOWN", "Software thermal throttling: Driver initiated clock reduction due to high temperature"),
    (0x0040, "HW_THERMAL_SLOWDOWN", "Hardware thermal trip: Critical junction temperature reached, emergency clock clamp active!"),
    (0x0080, "HW_POWER_BRAKE_SLOWDOWN", "Power brake line asserted: Power supply or battery cannot deliver required current!"),
    (0x0100, "DISPLAY_CLOCK_SETTING", "Clocks adjusted to satisfy display refresh rate constraints")
]

active_found = False
for bit, name, desc in reasons:
    is_active = (mask & bit) != 0
    status_str = "[ACTIVE]" if is_active else "[INACTIVE]"
    if is_active:
        active_found = True
        print(f"  * {status_str} Bit 0x{bit:04x} : {name}")
        print(f"      Operational impact: {desc}")

if not active_found:
    print("  * All throttle reasons inactive. GPU running at full unconstrained clocks!")
EOF
}

# ------------------------------------------------------------------------------
# 4. Kernel Event Stream & DMAR / NVRM Xid Scanner
# ------------------------------------------------------------------------------

cmd_dmar() {
    print_header "Kernel Hardware Event Stream & DMAR / NVRM Xid Diagnostic"
    print_note "Scans kernel ring buffer (journalctl -k / dmesg) for IOMMU faults, PTE violations, and GPU Xids."

    journal_stream() {
        if [ -n "${MOCK_JOURNAL_FILE:-}" ] && [ -f "$MOCK_JOURNAL_FILE" ]; then
            cat "$MOCK_JOURNAL_FILE"
        elif command -v journalctl >/dev/null 2>&1; then
            journalctl -k -b --no-pager 2>&1 || return 0
        elif [ -r /var/log/dmesg ]; then
            cat /var/log/dmesg
        else
            dmesg 2>/dev/null || return 0
        fi
    }

    local py_dmar_analyzer='
import sys, re

logs = sys.stdin.read()

print("--- 1. Intel VT-d DMAR / IOMMU Fault Analysis ---")
dmar_faults = re.findall(r"(DMAR:.*(?:fault|DRHD|NO_PASID|PTE|error).*)", logs, re.IGNORECASE)
dmar_critical = [l for l in dmar_faults if any(k in l.lower() for k in ["fault addr", "pte read", "pte write", "present bit"])]

if dmar_critical:
    print(f"  [CRITICAL] Detected {len(dmar_critical)} active VT-d DMAR memory faults:")
    for fault in dmar_critical[:8]:
        print(f"    * {fault}")
    print("")
    print("  Root-Cause Explanation:")
    print("    An endpoint device (PCIe peripheral) initiated Direct Memory Access (DMA)")
    print("    to a physical host address that is NOT mapped in the IOMMU page table,")
    print("    or lacked Read/Write permissions (PTE access violation).")
    print("    The Intel VT-d IOMMU intercepted and dropped the DMA transaction to prevent")
    print("    silent memory corruption. Common in virtualization, SRIOV, or buggy drivers.")
else:
    print("  [OK] No active VT-d DMAR DMA faults or PTE permission violations detected.")
    if dmar_faults:
        print(f"  Note: Found {len(dmar_faults)} informational DMAR initialization entries in kernel log.")

print("\n--- 2. NVIDIA NVRM Xid Error Analysis ---")
xid_matches = re.findall(r"NVRM:.*Xid.*\(PCI:([0-9a-fA-F:.]+)\):\s*(\d+)", logs)

# Comprehensive Xid dictionary with root-causes and solutions
xid_table = {
    13: ("Graphics Engine Exception", "Illegal instruction, unmapped shader resource, or out-of-bounds shader memory access."),
    31: ("GPU Memory Page Fault", "CUDA or graphics process accessed an invalid/unmapped VRAM or system memory page."),
    32: ("Corrupted PushBuffer", "Command buffer stream desynchronization between CPU host driver and GPU command processor."),
    43: ("GPU Stopped Processing", "TDR (Timeout Detection and Recovery) watchdog fired; kernel reset GPU engine."),
    45: ("Preemptive Cleanup", "Driver cleaned up GPU context after application hung or triggered unrecoverable trap."),
    61: ("Internal Micro-Controller Breakpoint", "Firmware micro-controller tripped internal debugging or safety assertion."),
    62: ("Internal Micro-Controller Halt", "GPU internal firmware engine halted execution due to hardware inconsistency."),
    79: ("GPU Fallen Off Bus", "PCIe link lost, power supply brownout, or fatal hardware bus disconnect!"),
    92: ("High Definition Audio Error", "Internal handshake failure between GPU display engine and HDMI/DP audio codec."),
    119: ("GSP Firmware Timeout / Crash", "GPU System Processor (GSP) RISC-V co-processor firmware crashed or timed out.")
}

if xid_matches:
    print(f"  [CRITICAL] Detected {len(xid_matches)} NVRM Xid hardware events:")
    for bdf, xid_str in xid_matches:
        xid = int(xid_str)
        info = xid_table.get(xid, ("Unknown Xid Code", "Consult NVIDIA driver documentation"))
        print(f"    * Device {bdf}: Xid {xid} -> {info[0]}")
        print(f"        Cause: {info[1]}")
else:
    print("  [OK] 0 NVRM Xid GPU errors found in current kernel boot session.")

print("\n--- 3. Machine Check Architecture (MCE) & AER Events ---")
mce_events = re.findall(r"(mce:.*\[Hardware Error\].*)", logs, re.IGNORECASE)
aer_events = re.findall(r"(AER:.*|PCIe Bus Error: severity=.*)", logs, re.IGNORECASE)

if mce_events:
    print(f"  [CRITICAL] Machine Check Exceptions (MCE) logged ({len(mce_events)} events):")
    for ev in mce_events[:5]:
        print(f"    * {ev}")
    print("  Root-Cause: CPU detected an internal hardware fault (cache parity error, interconnect timeout, ECC error).")
else:
    print("  [OK] 0 Machine Check Exceptions (MCE) detected.")

if aer_events:
    print(f"  [WARN] PCIe AER link error logs detected ({len(aer_events)} events):")
    for ev in aer_events[:5]:
        print(f"    * {ev}")
else:
    print("  [OK] 0 PCIe AER bus error events detected in kernel journal.")

print("\n--- Overall Hardware Event Stream Verdict ---")
fault_count = len(dmar_critical) + len(xid_matches) + len(mce_events)
if fault_count == 0:
    print("  STATUS: HEALTHY. Hardware register streams and kernel ring buffers are clean.")
else:
    print(f"  STATUS: ATTENTION REQUIRED. {fault_count} total hardware faults/exceptions detected.")
'

    journal_stream | python3 -c "$py_dmar_analyzer"
}

# ------------------------------------------------------------------------------
# 5. Educational Tutorial Engine: "learn"
# ------------------------------------------------------------------------------

cmd_learn() {
    local topic=${1:-"all"}

    case "${topic,,}" in
        msr)
            cat <<'EOF'
================================================================================
EDUCATIONAL MODULE 1: CPU Model-Specific Registers (MSRs) & Ring 0 Isolation
================================================================================

1. What are MSRs?
   In the x86-64 architecture, Model-Specific Registers are control and status
   registers used to toggle CPU architectural features, query power limits,
   configure hardware performance monitoring counters, and tune voltage.

2. Why can't user-space processes (pure shell, regular programs) read MSRs?
   - MSRs are read using the privileged RDMSR assembly opcode (0x0F 0x32)
     and written using WRMSR (0x0F 0x30).
   - Executing RDMSR or WRMSR from Ring 3 (user space) triggers a General
     Protection Fault (#GP), causing the CPU to raise an immediate SIGSEGV.
   - To inspect MSRs from user space on Linux, you must interface with the
     kernel character device driver /dev/cpu/<cpu_id>/msr.
   - This device node is strictly permission-locked (0600 root:root) and requires
     CAP_SYS_RAWIO to prevent unprivileged software from disabling security
     mitigations or overclocking/overvolting the silicon.

3. Key Intel MSRs:
   - 0x198 (IA32_PERF_STATUS)     : Reports current core multiplier and VID voltage.
   - 0x199 (IA32_PERF_CTL)        : Target performance multiplier request.
   - 0x1B0 (IA32_ENERGY_PERF_BIAS): Energy Performance Bias (0=Max Perf, 15=Power).
   - 0x610 (MSR_PKG_POWER_LIMIT)  : RAPL Package PL1 (sustained) and PL2 (burst) limits.
   - 0x150 (MSR_OC_VOLTAGE_OFFSET): Overclocking mailbox interface for undervolting.
================================================================================
EOF
            ;;
        pcie)
            cat <<'EOF'
================================================================================
EDUCATIONAL MODULE 2: PCIe Architecture, Configuration Space, & TLPs
================================================================================

1. PCIe Point-to-Point Architecture:
   Unlike legacy PCI, which was a shared parallel multi-drop bus, PCI Express
   (PCIe) is a high-speed point-to-point packetized serial network. Devices
   communicate across 1 to 16 lanes using differential signaling.

2. Configuration Space:
   - Every PCIe function has a 4096-byte Configuration Space.
   - The first 64 bytes form the standardized Type 0 Header:
     * Offset 0x00: Vendor ID (e.g. 0x10DE = NVIDIA, 0x8086 = Intel)
     * Offset 0x02: Device ID
     * Offset 0x04: Command Register (Bus Master enable, Memory space enable)
     * Offset 0x06: Status Register (Capabilities pointer present)
     * Offset 0x10: Base Address Registers (BAR0..BAR5) for memory mapping
   - The remaining space (0x100..0xFFF) holds PCIe Extended Capabilities,
     including AER (Advanced Error Reporting) and Resizable BAR.
   - On Linux, this space is memory-mapped into sysfs at:
     /sys/bus/pci/devices/<domain>:<bus>:<slot>.<func>/config

3. Transaction Layer Packets (TLPs) vs DLLPs:
   - TLPs carry memory read/write requests and interrupts (MSI-X).
   - DLLPs (Data Link Layer Packets) handle link management, ACK/NAK
     flow control, and power management (ASPM L0s, L1).
   - Correctable errors (BadDLLP, BadTLP) are retransmitted automatically
     by hardware. If counters increment rapidly, physical lane degradation
     or electrical impedance mismatch is present.
================================================================================
EOF
            ;;
        dmar)
            cat <<'EOF'
================================================================================
EDUCATIONAL MODULE 3: Kernel Page Tables, IOMMU (VT-d), & DMAR Faults
================================================================================

1. Virtual Memory & Physical Memory:
   The CPU MMU translates Virtual Addresses (VA) to Physical Addresses (PA)
   using hierarchical page tables (PML4 / PML5 on x86-64).
   Each Page Table Entry (PTE) contains control bits:
     * Bit 0: Present (P) - page is in physical RAM
     * Bit 1: Read/Write (R/W) - write permission enabled
     * Bit 2: User/Supervisor (U/S) - accessible to user space

2. What is an IOMMU (Intel VT-d / AMD-Vi)?
   - When a PCIe peripheral (such as a GPU or 10GbE NIC) performs DMA,
     it traditionally used direct physical addresses.
   - A rogue or buggy device could overwrite kernel data structures or
     steal cryptographic keys (DMA attack).
   - The IOMMU sits between the PCIe root complex and system DRAM, providing
     hardware address translation and memory isolation for I/O devices.

3. Anatomy of a DMAR Fault:
   - When a device initiates DMA to an address that has no valid IOMMU
     page table entry, the IOMMU blocks the transaction and logs:
     "DMAR: [DMA Read/Write] ... fault addr ... [PTE Read/Write access not set]"
   - Fault status registers (FSTS) trigger a hardware interrupt, alerting
     the kernel to record the violation in journalctl/dmesg.
================================================================================
EOF
            ;;
        gpu)
            cat <<'EOF'
================================================================================
EDUCATIONAL MODULE 4: GPU Performance States & Throttle Mechanics
================================================================================

1. NVIDIA P-States:
   NVIDIA GPUs dynamically transition through performance states (P-States):
     * P0 / P1 : Maximum 3D compute and graphics clocks (highest voltage/frequency)
     * P2 / P3 : Compute workload / CUDA default state
     * P8      : Video playback and desktop composition (low power)
     * P15     : Deep sleep / lowest power state

2. Hardware vs Software Throttling:
   - SW Power Cap (0x04): The GPU reached its configured electrical power
     limit (TDP). The firmware power management loop trims boost frequency
     smoothly to keep consumption at or below the target wattage.
   - SW Thermal (0x20): The driver begins reducing clocks as the GPU approaches
     its target temperature limit (e.g. 83°C).
   - HW Thermal (0x40): Critical junction threshold tripped (e.g. 95°C-100°C).
     Silicon safety circuitry forces an immediate clock reduction (often to 210 MHz)
     to avoid thermal runaway.
   - HW Power Brake (0x80): An external hardware GPIO line (e.g. PROCHOT / BDPROCHOT)
     is asserted by the motherboard VRM or battery controller, forcing the GPU
     to throttle immediately due to an external power supply bottleneck.
================================================================================
EOF
            ;;
        all|*)
            cmd_learn msr
            printf "\n"
            cmd_learn pcie
            printf "\n"
            cmd_learn dmar
            printf "\n"
            cmd_learn gpu
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Main CLI Dispatcher
# ------------------------------------------------------------------------------

main() {
    local cmd=${1:-"help"}
    [ $# -gt 0 ] && shift

    case "${cmd,,}" in
        msr)
            cmd_msr "$@"
            ;;
        pcie)
            cmd_pcie "$@"
            ;;
        gpu)
            cmd_gpu "$@"
            ;;
        dmar)
            cmd_dmar "$@"
            ;;
        learn)
            cmd_learn "$@"
            ;;
        help|-h|--help)
            usage
            exit 0
            ;;
        *)
            print_err "Unknown command: $cmd"
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"

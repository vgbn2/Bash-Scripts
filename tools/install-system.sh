#!/usr/bin/env bash
# Audit or install the native commands used by this Linux toolkit.
#
# Package and link changes are deliberately separate. Nothing is installed
# unless the requested action includes --yes.

set -euo pipefail

TOOL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${SYSTEM_INSTALL_BIN_DIR:-$HOME/.local/bin}"

CORE_PACKAGES=(
    bash
    coreutils
    curl
    iproute2
    iputils-ping
    lm-sensors
    nvme-cli
    openssh-client
    pciutils
    procps
    rsync
    smartmontools
    usbutils
    util-linux
)

OPTIONAL_PACKAGES=(
    bind9-dnsutils
    bluez
    brightnessctl
    ddcutil
    dmidecode
    edid-decode
    efibootmgr
    ethtool
    evtest
    fancontrol
    fwupd
    iftop
    iperf3
    iw
    joystick
    libinput-tools
    mokutil
    nethogs
    network-manager
    sysstat
    vulkan-tools
    x11-xserver-utils
)

COMMAND_LINKS=(
    "system:system/system"
    "cpu:hardware/cpu"
    "system-health:maintenance/system-health"
    "system-repair:maintenance/system-repair"
    "gaming:gaming/gaming"
    "ai:ai/ai"
)

usage() {
    cat <<'HELP'
Usage: install-system.sh <command> [arguments]

Commands:
  status                  Audit commands, native packages, sudo, and links.
  install --yes           Create user command links and install core packages.
  links --yes             Create user command links in ~/.local/bin.
  packages core --yes     Install the native baseline with apt-get and sudo.
  packages all --yes      Install the baseline and optional feature tools.
  help                    Show this help.

Environment:
  SYSTEM_INSTALL_BIN_DIR  Override the user command-link directory.

The installer supports Debian/Ubuntu APT hosts. `install --yes` is the
recommended first-time setup command; it creates user command links before
requesting sudo for core packages. It does not enable services, change
firmware, apply network shaping, or install OpenRGB. Existing regular files
in the command-link directory are never overwritten.
HELP
}

has_package() {
    dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null |
        grep -q '^ii '
}

show_command_status() {
    local label=$1 command_name=$2 importance=$3

    if command -v "$command_name" >/dev/null 2>&1; then
        printf '  OK      %-16s %s\n' "$label" "$(command -v "$command_name")"
        return 0
    fi

    printf '  MISSING %-16s %s\n' "$label" "$importance"
    return 1
}

show_package_group() {
    local title=$1
    shift
    local package
    local missing=0

    printf '\n%s\n' "$title"
    for package in "$@"; do
        if has_package "$package"; then
            printf '  OK      %s\n' "$package"
        else
            printf '  MISSING %s\n' "$package"
            missing=$((missing + 1))
        fi
    done
    printf '  Missing: %s\n' "$missing"
}

link_target() {
    readlink -f -- "$1" 2>/dev/null || true
}

is_compatibility_launcher() {
    local launcher=$1 source=$2

    [ -f "$launcher" ] &&
        grep -Fqx "exec $source \"\$@\"" "$launcher" 2>/dev/null
}

show_link_status() {
    local entry name relative source destination actual

    printf '\nUser command links (%s)\n' "$BIN_DIR"
    for entry in "${COMMAND_LINKS[@]}"; do
        name=${entry%%:*}
        relative=${entry#*:}
        source="$TOOL_ROOT/$relative"
        destination="$BIN_DIR/$name"
        actual=$(link_target "$destination")

        if [ "$actual" = "$source" ]; then
            printf '  OK      %-16s -> %s\n' "$name" "$relative"
        elif is_compatibility_launcher "$actual" "$source"; then
            printf '  WRAPPER %-16s -> %s -> %s\n' "$name" \
                "$(readlink -- "$destination" 2>/dev/null || echo "$destination")" \
                "$relative"
        elif [ -e "$destination" ] || [ -L "$destination" ]; then
            printf '  OTHER   %-16s -> %s\n' "$name" \
                "$(readlink -- "$destination" 2>/dev/null || echo 'regular file')"
        else
            printf '  MISSING %-16s -> %s\n' "$name" "$relative"
        fi
    done
}

status() {
    local missing_core=0

    echo "System toolkit setup audit"
    printf 'Source: %s\n' "$TOOL_ROOT"
    printf 'Platform: '
    if [ -r /etc/os-release ]; then
        (
            # shellcheck disable=SC1091
            source /etc/os-release
            printf '%s\n' "${PRETTY_NAME:-unknown Linux}"
        )
    else
        echo "unknown Linux"
    fi

    printf '\nCore runtime commands\n'
    show_command_status "ip" ip "package: iproute2" || missing_core=1
    show_command_status "ping" ping "package: iputils-ping" || missing_core=1
    show_command_status "curl" curl "package: curl" || missing_core=1
    show_command_status "sensors" sensors "package: lm-sensors" || missing_core=1
    show_command_status "nvme" nvme "package: nvme-cli" || missing_core=1
    show_command_status "smartctl" smartctl "package: smartmontools" || missing_core=1
    show_command_status "lspci" lspci "package: pciutils" || missing_core=1
    show_command_status "lsusb" lsusb "package: usbutils" || missing_core=1
    show_command_status "rsync" rsync "package: rsync" || missing_core=1
    show_command_status "flock" flock "package: util-linux" || missing_core=1
    show_command_status "ssh" ssh "package: openssh-client" || missing_core=1

    printf '\nOptional feature commands\n'
    show_command_status "iostat" iostat "monitor disk; package: sysstat" || true
    show_command_status "nethogs" nethogs "network processes; package: nethogs" || true
    show_command_status "iftop" iftop "network peers; package: iftop" || true
    show_command_status "ddcutil" ddcutil "external displays; package: ddcutil" || true
    show_command_status "brightnessctl" brightnessctl "backlights; package: brightnessctl" || true
    show_command_status "fwupdmgr" fwupdmgr "firmware; package: fwupd" || true
    show_command_status "jstest" jstest "controllers; package: joystick" || true
    show_command_status "vulkaninfo" vulkaninfo "GPU diagnostics; package: vulkan-tools" || true
    show_command_status "xrandr" xrandr "displays; package: x11-xserver-utils" || true
    show_command_status "bluetoothctl" bluetoothctl "Bluetooth inventory; package: bluez" || true

    printf '\nPrivilege helper\n'
    if command -v sudo >/dev/null 2>&1; then
        printf '  OK      sudo             %s\n' "$(command -v sudo)"
    else
        echo "  MISSING sudo             required only for privileged actions"
        missing_core=1
    fi

    show_package_group "Core native packages" "${CORE_PACKAGES[@]}"
    show_package_group "Optional feature packages" "${OPTIONAL_PACKAGES[@]}"
    show_link_status

    if [ "$missing_core" -ne 0 ]; then
        printf '\nCore runtime gaps found. Install with:\n'
        echo "  $TOOL_ROOT/tools/install-system.sh packages core --yes"
        return 1
    fi

    echo
    echo "Core runtime commands are available."
}

install_links() {
    local confirmation=${1:-}
    local entry name relative source destination actual

    if [ "$confirmation" != "--yes" ]; then
        echo "This creates command links in: $BIN_DIR" >&2
        echo "Run: $TOOL_ROOT/tools/install-system.sh links --yes" >&2
        return 2
    fi

    mkdir -p "$BIN_DIR"
    for entry in "${COMMAND_LINKS[@]}"; do
        name=${entry%%:*}
        relative=${entry#*:}
        source="$TOOL_ROOT/$relative"
        destination="$BIN_DIR/$name"
        actual=$(link_target "$destination")

        if [ ! -x "$source" ]; then
            echo "Source command is not executable: $source" >&2
            return 1
        fi
        if [ "$actual" = "$source" ]; then
            printf 'Unchanged: %s\n' "$destination"
            continue
        fi
        if [ -e "$destination" ] && [ ! -L "$destination" ]; then
            echo "Refusing to overwrite regular file: $destination" >&2
            return 1
        fi

        ln -sfn -- "$source" "$destination"
        printf 'Linked: %s -> %s\n' "$destination" "$source"
    done

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *)
            printf '\nAdd this directory to PATH, then open a new shell:\n'
            printf '  export PATH="%s:$PATH"\n' "$BIN_DIR"
            ;;
    esac
}

install_packages() {
    local group=${1:-}
    local confirmation=${2:-}
    local -a packages

    case "$group" in
        core) packages=("${CORE_PACKAGES[@]}") ;;
        all) packages=("${CORE_PACKAGES[@]}" "${OPTIONAL_PACKAGES[@]}") ;;
        *)
            echo "Package group must be: core or all." >&2
            return 2
            ;;
    esac

    if [ "$confirmation" != "--yes" ]; then
        echo "This runs apt-get update and installs the '$group' native package group." >&2
        echo "Run: $TOOL_ROOT/tools/install-system.sh packages $group --yes" >&2
        return 2
    fi
    if ! command -v apt-get >/dev/null 2>&1 ||
        ! command -v dpkg-query >/dev/null 2>&1; then
        echo "This installer requires a Debian/Ubuntu APT host." >&2
        return 1
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "sudo is required to install native packages." >&2
        return 127
    fi

    printf 'Installing %s native package group (%s packages).\n' \
        "$group" "${#packages[@]}"
    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
}

install() {
    local confirmation=${1:-}

    if [ "$confirmation" != "--yes" ]; then
        echo "This creates user command links and installs core native packages." >&2
        echo "Run: $TOOL_ROOT/tools/install-system.sh install --yes" >&2
        return 2
    fi

    install_links --yes
    install_packages core --yes
}

case "${1:-status}" in
    status|check|doctor) status ;;
    install) install "${2:-}" ;;
    links) install_links "${2:-}" ;;
    packages) install_packages "${2:-}" "${3:-}" ;;
    help|-h|--help) usage ;;
    *)
        echo "Unknown setup command: ${1:-}" >&2
        usage >&2
        exit 2
        ;;
esac

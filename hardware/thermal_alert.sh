#!/usr/bin/env bash
# Foreground thermal watcher with validated telemetry and alert cooldown.

set -u

threshold="${THERMAL_ALERT_THRESHOLD:-73}"
interval="${THERMAL_ALERT_INTERVAL:-10}"
cooldown="${THERMAL_ALERT_COOLDOWN:-300}"
once=0
last_alert=0

usage() {
    cat <<'HELP'
Usage: thermal_alert.sh [--once] [--threshold C] [--interval seconds]

Options:
  --once          Read one snapshot and exit.
  --threshold C   Alert temperature, 40-110 C (default: 73).
  --interval N    Poll interval, 1-3600 seconds (default: 10).

THERMAL_ALERT_COOLDOWN controls repeated-alert spacing in seconds
(default: 300). The watcher never changes CPU, GPU, or fan settings.
HELP
}

valid_integer_range() {
    local value=$1 minimum=$2 maximum=$3
    [[ "$value" =~ ^[0-9]+$ ]] &&
        [ "$value" -ge "$minimum" ] &&
        [ "$value" -le "$maximum" ]
}

read_gpu_temp() {
    command -v nvidia-smi >/dev/null 2>&1 || return
    nvidia-smi --query-gpu=temperature.gpu \
        --format=csv,noheader,nounits 2>/dev/null |
        awk '/^[0-9]+$/ {if (!found || $1 > maximum) maximum=$1; found=1}
            END {if (found) print maximum}'
}

read_cpu_temp() {
    command -v sensors >/dev/null 2>&1 || return
    sensors 2>/dev/null |
        awk '/Package id 0:|Tctl:|CPU Temperature:/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^\+[0-9]+(\.[0-9]+)?°C$/) {
                    gsub(/[+°C]/, "", $i)
                    printf "%d\n", $i
                    exit
                }
            }
        }'
}

read_hottest_temp() {
    local gpu cpu

    gpu=$(read_gpu_temp)
    cpu=$(read_cpu_temp)
    if [[ "$gpu" =~ ^[0-9]+$ ]] && [[ "$cpu" =~ ^[0-9]+$ ]]; then
        if [ "$gpu" -ge "$cpu" ]; then
            printf '%s gpu\n' "$gpu"
        else
            printf '%s cpu\n' "$cpu"
        fi
    elif [[ "$gpu" =~ ^[0-9]+$ ]]; then
        printf '%s gpu\n' "$gpu"
    elif [[ "$cpu" =~ ^[0-9]+$ ]]; then
        printf '%s cpu\n' "$cpu"
    else
        return 1
    fi
}

send_alert() {
    local temperature=$1 source=$2

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical "Hardware thermal alert" \
            "$source temperature is ${temperature}°C (threshold ${threshold}°C)." \
            2>/dev/null || true
    fi
    if command -v paplay >/dev/null 2>&1 &&
        [ -r /usr/share/sounds/sound-theme-freedesktop/stereo/alarm-clock-elapsed.oga ]; then
        paplay /usr/share/sounds/sound-theme-freedesktop/stereo/alarm-clock-elapsed.oga \
            2>/dev/null || true
    fi
}

check_once() {
    local reading temperature source now

    if ! reading=$(read_hottest_temp); then
        echo "Temperature telemetry is unavailable." >&2
        return 2
    fi
    read -r temperature source <<<"$reading"
    printf 'temperature=%sC source=%s threshold=%sC\n' \
        "$temperature" "$source" "$threshold"

    if [ "$temperature" -lt "$threshold" ]; then
        return 0
    fi

    now=$(date +%s)
    if [ $((now - last_alert)) -ge "$cooldown" ]; then
        send_alert "$temperature" "$source"
        last_alert=$now
    fi
    return 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --once) once=1; shift ;;
        --threshold)
            [ "$#" -ge 2 ] || { echo "--threshold requires a value." >&2; exit 2; }
            threshold=$2
            shift 2
            ;;
        --interval)
            [ "$#" -ge 2 ] || { echo "--interval requires a value." >&2; exit 2; }
            interval=$2
            shift 2
            ;;
        help|-h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

valid_integer_range "$threshold" 40 110 || {
    echo "Threshold must be a whole number from 40 to 110 C." >&2
    exit 2
}
valid_integer_range "$interval" 1 3600 || {
    echo "Interval must be a whole number from 1 to 3600 seconds." >&2
    exit 2
}
valid_integer_range "$cooldown" 0 86400 || {
    echo "THERMAL_ALERT_COOLDOWN must be from 0 to 86400 seconds." >&2
    exit 2
}

if [ "$once" -eq 1 ]; then
    check_once
    exit $?
fi

echo "Thermal watcher started: threshold=${threshold}C interval=${interval}s cooldown=${cooldown}s"
while true; do
    check_once || true
    sleep "$interval"
done

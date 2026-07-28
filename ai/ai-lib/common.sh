# Shared helpers for the ai command.

AI_PROBE_SECONDS=5

print_section() {
    printf '\n=== %s ===\n' "$1"
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

run_bounded() {
    local seconds=$1
    shift

    if has_command timeout; then
        timeout "${seconds}s" "$@"
    else
        "$@"
    fi
}

memory_kib() {
    local key=$1

    awk -v key="$key:" '$1 == key {print $2; found=1; exit}
        END {if (!found) print 0}' /proc/meminfo
}

kib_to_gib() {
    awk -v kib="$1" 'BEGIN {printf "%.1f", kib / 1048576}'
}

show_memory_summary() {
    local total_kib
    local available_kib
    local swap_total_kib
    local swap_free_kib

    total_kib=$(memory_kib MemTotal)
    available_kib=$(memory_kib MemAvailable)
    swap_total_kib=$(memory_kib SwapTotal)
    swap_free_kib=$(memory_kib SwapFree)

    printf 'RAM: %s GiB total, %s GiB currently available\n' \
        "$(kib_to_gib "$total_kib")" "$(kib_to_gib "$available_kib")"
    printf 'Swap: %s GiB total, %s GiB free\n' \
        "$(kib_to_gib "$swap_total_kib")" "$(kib_to_gib "$swap_free_kib")"
}

require_ollama() {
    if has_command ollama; then
        return 0
    fi

    echo "Ollama is not installed or is not in PATH." >&2
    return 127
}

capture_ollama() {
    local output
    local status

    has_command ollama || return 127

    output=$(run_bounded "$AI_PROBE_SECONDS" ollama "$@" 2>&1)
    status=$?
    printf '%s' "$output"
    return "$status"
}

explain_probe_failure() {
    local status=$1
    local output=${2:-}

    if [ "$status" -eq 127 ]; then
        echo "Ollama is not installed or is not in PATH."
        return
    elif [ "$status" -eq 124 ]; then
        echo "Ollama did not answer within ${AI_PROBE_SECONDS} seconds."
    elif [ -n "$output" ]; then
        printf '%s\n' "$output"
    else
        echo "Ollama is installed, but its local service did not answer."
    fi

    echo "Check the service with: systemctl status ollama --no-pager"
}

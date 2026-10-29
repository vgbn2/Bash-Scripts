# Shared helpers for security and pentest auditing.

SECURITY_PROBE_SECONDS=10
TMPFS_DIR="/dev/shm"

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

status_tag() {
    local status=$1
    local text=$2
    case "$status" in
        ok|pass)   printf '[ \033[32mOK\033[0m ] %s\n' "$text" ;;
        warn)      printf '[\033[33mWARN\033[0m] %s\n' "$text" ;;
        fail|risk) printf '[\033[31mFAIL\033[0m] %s\n' "$text" ;;
        info)      printf '[ \033[34mINFO\033[0m ] %s\n' "$text" ;;
        *)         printf '[%s] %s\n' "$status" "$text" ;;
    esac
}

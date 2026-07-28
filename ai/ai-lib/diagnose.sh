# Bounded diagnostics for Ollama, GPU fallback, and recent OOM evidence.

show_recent_ai_events() {
    local output

    print_section "Recent AI, GPU, and memory events"

    if ! has_command journalctl; then
        echo "journalctl is not installed."
        return
    fi

    output=$(run_bounded "$AI_PROBE_SECONDS" journalctl -b --no-pager \
        -k -n 600 2>/dev/null | \
        grep -Ei 'out of memory|oom-kill|killed process|ollama|llama-server|NVRM|Xid' | \
        tail -n 25)

    if [ -n "$output" ]; then
        printf '%s\n' "$output"
    else
        echo "No matching events found in the readable current-boot kernel log."
        echo "Older boots or restricted journal entries are not included."
    fi
}

show_ollama_service_hint() {
    local state

    print_section "Service state"

    if ! has_command systemctl; then
        echo "systemctl is not available."
        return
    fi

    state=$(run_bounded "$AI_PROBE_SECONDS" systemctl is-active ollama \
        2>/dev/null || true)

    case "$state" in
        active)
            echo "ollama.service: active"
            ;;
        inactive|failed|activating|deactivating)
            printf 'ollama.service: %s\n' "$state"
            echo "Inspect it with: systemctl status ollama --no-pager"
            ;;
        *)
            echo "ollama.service state could not be read."
            echo "It may be user-managed, containerized, or restricted here."
            ;;
    esac
}

diagnose_ai() {
    print_section "Memory headroom"
    show_memory_summary
    show_ai_gpu
    show_ollama_service_hint
    show_ollama_runtime
    show_all_model_risks
    show_recent_ai_events
}

# Runtime, GPU, and memory status.

show_ollama_runtime() {
    local output
    local status

    print_section "Ollama runtime"

    if ! has_command ollama; then
        echo "Ollama: not installed"
        return
    fi

    printf 'Command: %s\n' "$(command -v ollama)"
    output=$(capture_ollama ps)
    status=$?

    if [ "$status" -eq 0 ]; then
        if [ -n "$output" ]; then
            printf '%s\n' "$output"
        else
            echo "Ollama answered; no model is currently loaded."
        fi
    else
        explain_probe_failure "$status" "$output"
    fi
}

show_ai_gpu() {
    local output
    local status

    print_section "AI accelerator"

    if ! has_command nvidia-smi; then
        echo "nvidia-smi is not installed. NVIDIA CUDA status is unavailable."
        return
    fi

    output=$(run_bounded "$AI_PROBE_SECONDS" nvidia-smi \
        --query-gpu=name,memory.total,memory.used,temperature.gpu \
        --format=csv,noheader 2>&1)
    status=$?

    if [ "$status" -eq 0 ]; then
        printf 'GPU, VRAM total, VRAM used, temperature:\n%s\n' "$output"
    else
        echo "NVIDIA GPU is not currently usable."
        [ -n "$output" ] && printf '%s\n' "$output"
        echo "Ollama may fall back to CPU and system RAM."
    fi
}

show_ai_status() {
    print_section "Memory headroom"
    show_memory_summary
    show_ai_gpu
    show_ollama_runtime
}

# Explicit state-changing local-model actions.

valid_model_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]]
}

stop_model() {
    local model=${1:-}
    local output
    local status

    if [ -z "$model" ]; then
        echo "Usage: ai stop <model>" >&2
        return 2
    fi

    if ! valid_model_name "$model"; then
        echo "Invalid model name: $model" >&2
        echo "Allowed: letters, numbers, dot, underscore, colon, slash, hyphen." >&2
        return 2
    fi

    require_ollama || return

    output=$(run_bounded 15 ollama stop "$model" 2>&1)
    status=$?
    if [ "$status" -eq 0 ]; then
        printf '%s\n' "${output:-Stopped: $model}"
    elif [ "$status" -eq 124 ]; then
        echo "Timed out while stopping: $model" >&2
        return 124
    else
        printf '%s\n' "$output" >&2
        return "$status"
    fi
}

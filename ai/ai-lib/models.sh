# Installed-model listing and approximate memory-risk checks.

size_to_mib() {
    local value=$1
    local unit=${2^^}

    awk -v value="$value" -v unit="$unit" 'BEGIN {
        if (unit == "TB" || unit == "TIB") {
            printf "%.0f", value * 1048576
        } else if (unit == "GB" || unit == "GIB") {
            printf "%.0f", value * 1024
        } else if (unit == "MB" || unit == "MIB") {
            printf "%.0f", value
        } else if (unit == "KB" || unit == "KIB") {
            printf "%.0f", value / 1024
        } else {
            print 0
        }
    }'
}

get_model_list() {
    local output
    local status

    output=$(capture_ollama list)
    status=$?

    if [ "$status" -ne 0 ]; then
        explain_probe_failure "$status" "$output" >&2
        return "$status"
    fi

    printf '%s\n' "$output"
}

show_models() {
    local output

    print_section "Installed Ollama models"
    output=$(get_model_list) || return

    if [ -n "$output" ]; then
        printf '%s\n' "$output"
    else
        echo "No installed models were reported."
    fi
}

model_row() {
    local model=$1
    local list=$2

    awk -v model="$model" 'NR > 1 && $1 == model {print; exit}' <<<"$list"
}

model_risk_label() {
    local model_mib=$1
    local total_mib=$2
    local available_mib=$3
    local swap_free_mib=$4
    local usable_mib=$((available_mib + swap_free_mib))

    if [ "$model_mib" -ge $((total_mib * 75 / 100)) ]; then
        echo "HIGH"
    elif [ "$model_mib" -ge $((usable_mib * 80 / 100)) ]; then
        echo "HIGH"
    elif [ "$model_mib" -ge $((available_mib * 60 / 100)) ]; then
        echo "MEDIUM"
    else
        echo "LOWER"
    fi
}

check_model_fit() {
    local model=$1
    local list
    local row
    local size_value
    local size_unit
    local model_mib
    local total_mib
    local available_mib
    local swap_free_mib
    local risk

    if [ -z "$model" ]; then
        echo "Usage: ai check <model>" >&2
        return 2
    fi

    list=$(get_model_list) || return
    row=$(model_row "$model" "$list")

    if [ -z "$row" ]; then
        echo "Installed model not found: $model" >&2
        echo "Run: ai models" >&2
        return 1
    fi

    size_value=$(awk '{print $3}' <<<"$row")
    size_unit=$(awk '{print $4}' <<<"$row")
    model_mib=$(size_to_mib "$size_value" "$size_unit")
    total_mib=$(( $(memory_kib MemTotal) / 1024 ))
    available_mib=$(( $(memory_kib MemAvailable) / 1024 ))
    swap_free_mib=$(( $(memory_kib SwapFree) / 1024 ))
    risk=$(model_risk_label "$model_mib" "$total_mib" \
        "$available_mib" "$swap_free_mib")

    print_section "Model resource check"
    printf 'Model: %s\n' "$model"
    printf 'Stored package size: %s %s\n' "$size_value" "$size_unit"
    show_memory_summary
    printf 'Memory-pressure risk: %s\n' "$risk"
    echo
    echo "This is a conservative warning based on package size and current"
    echo "headroom. Exact runtime use also depends on quantization, context"
    echo "length, KV cache, GPU offload, and concurrent applications."

    case "$risk" in
        HIGH)
            echo "Recommendation: close heavy apps, use a smaller context/model,"
            echo "and watch RAM and swap. An OOM kill is plausible."
            ;;
        MEDIUM)
            echo "Recommendation: avoid running other memory-heavy workloads."
            ;;
        LOWER)
            echo "The package size fits current headroom, but monitor first use."
            ;;
    esac
}

show_all_model_risks() {
    local list
    local row
    local model
    local size_value
    local size_unit
    local model_mib
    local total_mib
    local available_mib
    local swap_free_mib

    print_section "Installed-model pressure estimate"
    list=$(get_model_list) || return
    total_mib=$(( $(memory_kib MemTotal) / 1024 ))
    available_mib=$(( $(memory_kib MemAvailable) / 1024 ))
    swap_free_mib=$(( $(memory_kib SwapFree) / 1024 ))

    if [ "$(awk 'END {print NR}' <<<"$list")" -le 1 ]; then
        echo "No installed models were reported."
        return
    fi

    tail -n +2 <<<"$list" | while IFS= read -r row; do
        [ -n "$row" ] || continue
        model=$(awk '{print $1}' <<<"$row")
        size_value=$(awk '{print $3}' <<<"$row")
        size_unit=$(awk '{print $4}' <<<"$row")
        model_mib=$(size_to_mib "$size_value" "$size_unit")

        printf '%-32s %8s %-3s  risk: %s\n' \
            "$model" "$size_value" "$size_unit" \
            "$(model_risk_label "$model_mib" "$total_mib" \
                "$available_mib" "$swap_free_mib")"
    done

    echo
    echo "Use 'ai check <model>' for an explanation."
}

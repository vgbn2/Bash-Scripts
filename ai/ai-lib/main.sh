# Help text and command routing.

show_ai_help() {
    cat <<'HELP'
Usage: ai <command> [arguments]

CHECKS (read-only)
  ai status
      Show RAM, swap, NVIDIA, Ollama, and loaded-model status.

  ai models
      List models already installed in Ollama.

  ai check <model>
      Estimate memory-pressure risk before manually running a model.

  ai diagnose
      Combine runtime, model-risk, GPU, service, and OOM checks.

  ai logs
      Show recent current-boot AI, GPU, and out-of-memory events.

CHANGES (explicit)
  ai stop <model>
      Ask Ollama to unload one model from memory.

This tool does not download, launch, delete, or update models.
HELP
}

command_name=${1:-help}

case "$command_name" in
    help|-h|--help)
        show_ai_help
        ;;
    status)
        show_ai_status
        ;;
    models)
        show_models
        ;;
    check)
        check_model_fit "${2:-}"
        ;;
    diagnose)
        diagnose_ai
        ;;
    logs)
        show_recent_ai_events
        ;;
    stop)
        stop_model "${2:-}"
        ;;
    *)
        echo "Unknown ai command: $command_name" >&2
        show_ai_help >&2
        exit 2
        ;;
esac

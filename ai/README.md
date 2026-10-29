# Local AI Diagnostics

The `ai` command provides bounded, read-only inspection of Ollama, memory,
swap, GPU availability, loaded models, and recent OOM/GPU events. It does not
automatically start services or load, download, update, or delete models.

## Commands

```bash
ai status
ai models
ai check qwen3.6:latest
ai diagnose
ai logs
```

`ai check` compares an installed model package size with current RAM and swap
headroom. This is a conservative capacity warning, not an exact runtime-memory
prediction; context length, KV cache, quantization, GPU offload, and concurrent
workloads materially affect memory use.

The only state-changing command is explicit:

```bash
ai stop qwen3.6:latest
```

It asks Ollama to unload one model, validates the model identifier, uses a
bounded command execution, and never invokes `eval`.

## Architecture

- `ai` — entry point and module loader
- `ai-lib/common.sh` — bounded probes and memory helpers
- `ai-lib/status.sh` — Ollama, GPU, RAM, and swap status
- `ai-lib/models.sh` — model inventory and pressure estimates
- `ai-lib/diagnose.sh` — service, journal, OOM, and GPU diagnostics
- `ai-lib/actions.sh` — explicit model-unload action
- `ai-lib/main.sh` — help and command routing

Downloaded models, datasets, service configuration, and chat history are
runtime data and must remain outside this repository.

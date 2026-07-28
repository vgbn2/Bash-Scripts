# Local AI helpers

The `ai` command provides local Ollama, memory, GPU, and OOM diagnostics without
automatically starting large models.

## Read-only commands

```bash
ai status
ai models
ai check qwen3.6:latest
ai diagnose
ai logs
```

`ai check` compares the installed model package size with current RAM and swap.
It is a warning estimate, not an exact runtime-memory prediction: context
length, KV cache, quantization, GPU offload, and other applications also matter.

## Explicit action

```bash
ai stop qwen3.6:latest
```

This asks Ollama to unload that model from memory. The command rejects malformed
model names and never uses `eval`.

The helpers do not download, launch, update, or delete models. Downloaded
models, datasets, and chat history remain outside this source folder.

## Files

- `ai` - small entry point
- `ai-lib/common.sh` - bounded probes and memory helpers
- `ai-lib/status.sh` - Ollama, GPU, RAM, and swap status
- `ai-lib/models.sh` - model listing and pressure estimates
- `ai-lib/diagnose.sh` - service and recent OOM diagnostics
- `ai-lib/actions.sh` - explicit unload action
- `ai-lib/main.sh` - help and routing

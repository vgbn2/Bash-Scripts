# Hardware Operations

This directory contains standalone CPU, GPU, and thermal utilities used by the
`system` command.

- `cpu` inspects and explicitly changes supported CPU frequency, turbo, and
  firmware profile controls.
- `check_gpu.sh` performs a cron-friendly NVIDIA/Vulkan health check and writes
  a truthful `OK`, `INCOMPLETE`, or `CRITICAL` result.
- `thermal_alert.sh` monitors the hotter available CPU/GPU reading and applies
  a configurable notification cooldown without changing hardware policy.

Examples:

```bash
system cpu status
system gpu health
system thermals once 80
system thermals watch 80 10
```

CPU policy changes require sudo because they write kernel sysfs controls.
GPU and thermal diagnostics are observational; missing telemetry is reported
as unavailable or incomplete.

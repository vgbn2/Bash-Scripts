# System Command Architecture

`system/system` is the canonical command-center entry point. It resolves its
own real path, loads the modules in `system-lib/`, and delegates standalone
tools through paths anchored at the repository root.

## Module responsibilities

- `header.sh` — top-level help and shared presentation helpers
- `section-shell.sh` — interactive command-center and scoped prompts
- `main.sh` — command routing and standalone-tool delegation
- `health.sh`, `hardware.sh`, `monitor.sh` — read-only system inspection
- `network.sh`, `ssh.sh` — connectivity and SSH inspection
- `input.sh`, `display.sh`, `controllers.sh` — peripheral inspection/control
- `firmware.sh`, `cooling.sh` — guarded platform operations
- `actions.sh` — explicit traffic-shaping actions

## Extension contract

When adding a command:

1. Put implementation in the module that owns the domain.
2. Add one dispatcher route in `main.sh`.
3. Update top-level and scoped help where applicable.
4. Document state changes and required privileges.
5. Add a source-level test that proves argument validation and safety gates.

Read-only status commands must not start services or install dependencies.
Mutating operations must use explicit verbs, validate their target, and state
their host impact. Package, repair, firmware, destructive-mirror, and cleanup
operations must also require explicit confirmation.

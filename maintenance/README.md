# Guarded Maintenance

Maintenance commands separate inspection from state-changing repair and
cleanup operations.

## Health reports

```bash
system health run
system health summary
system health latest
```

Reports are written beneath `${XDG_STATE_HOME:-~/.local/state}/system-health`
and are not repository artifacts.

## Repairs

```bash
system repair suggest
system repair thermal --yes
system repair gpu --yes
system repair desktop --yes
```

Every state-changing repair requires confirmation at the canonical
`system-repair` entry point.

## Archival and cleanup

```bash
HDD_BASE=/mounted/archive system archive preview
HDD_BASE=/mounted/archive system archive archive --yes
system archive cleanup --yes
```

Archival validates the destination filesystem, rejects source/target overlap,
retains source-relative paths, and never overwrites existing destination files.
An absent source is reported and skipped without blocking another configured
source. Cleanup is independently guarded because it changes Flatpak, journal,
and APT cache state.

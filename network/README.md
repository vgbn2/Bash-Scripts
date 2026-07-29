# Network Diagnostics and Traffic Control

Network functionality is exposed through `system network`; this directory is
reserved for future standalone network helpers.

## Read-only diagnostics

```bash
system network status
system network processes
system network connections
system wifi status
system internet test
```

Live per-process and per-peer views require optional native tools:

```bash
system network install-tools --yes
```

## Traffic shaping

```bash
system network limit-download <percent> <max-mbps>
system network limit-upload <percent> <max-mbps>
system network clear-download
system network clear-upload
```

Download shaping redirects ingress traffic through IFB. Upload shaping
replaces the active interface's root queue discipline and therefore affects
all outgoing traffic, including SSH and synchronization. Prefer an
application-specific limit such as `rsync --bwlimit` when only one transfer
should be constrained.

All shaping commands are explicit, require sudo through the underlying native
tools, and remain active until cleared or superseded.

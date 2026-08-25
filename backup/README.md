# Backup Integration Boundary

This directory is reserved for reviewed backup and restore helpers. Backup
payloads, credentials, encryption keys, snapshots, and generated manifests
must remain outside the source repository.

No general-purpose backup or restore implementation is currently provided
here. The archival helper under `maintenance/` is a guarded file-migration
workflow, not a substitute for a versioned, restorable backup.

Any future backup implementation should provide:

- preview and explicit apply modes
- destination and mount validation
- collision and partial-failure handling
- integrity verification
- documented retention and recovery procedures
- a tested restore path

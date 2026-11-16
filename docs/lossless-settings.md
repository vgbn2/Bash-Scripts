# Lossless Scaling settings safety

`profile` and `tune` validate their arguments and parse the existing Settings.xml
before changing it. Missing, malformed or profile-free settings return nonzero;
launch Lossless Scaling normally to initialize a missing profile. FPS is a
nonnegative integer (0 selects FIXED mode); multipliers are 2, 3 or 4.

Paths are passed as arguments, not interpolated Python. Successful updates replace
the XML atomically in the same directory and preserve permission bits and symlink
targets. Concurrent independent editors remain last-writer-wins; no shared-editor
or power-loss durability guarantee is claimed. Existing custom XML comments and
formatting are subject to ElementTree serialization, as before.

## 1. Inspection

```bash
git diff -- gaming/lossless-scaling.sh # inspect the source changes before installation
```

## 2. Action

No installed scripts, game process or boot service is changed by source verification.
Invoke `profile` only when deliberately changing your existing game configuration.

## 3. Verification

```bash
bash tests/test_lossless_settings.sh # pure shell test harness using isolated /tmp/opencode homes
```

The check runs the real CLI/parser with malformed, missing and empty XML, invalid
parameters, valid profiles, symlink targets and a home path containing an apostrophe.

## 4. Rollback

No installed configuration needs rollback after this fixture-only check. Before a
real profile update, retain a copy of your Settings.xml if its prior values matter.

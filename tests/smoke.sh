#!/usr/bin/env bash
# Source-level smoke checks. These do not install packages or change the host.

set -euo pipefail

TOOL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT

while IFS= read -r script; do
    bash -n "$script"
done < <(
    find "$TOOL_ROOT" -type f \
        \( -name '*.sh' -o -perm -u+x \) \
        ! -path "$TOOL_ROOT/.git/*" \
        -print
)

"$TOOL_ROOT/system/system" help >/dev/null
"$TOOL_ROOT/system/system" setup help >/dev/null
"$TOOL_ROOT/tools/install-system.sh" help >/dev/null

if "$TOOL_ROOT/tools/install-system.sh" links >/dev/null 2>&1; then
    echo "Unguarded link installation unexpectedly succeeded." >&2
    exit 1
fi
if "$TOOL_ROOT/tools/install-system.sh" packages core >/dev/null 2>&1; then
    echo "Unguarded package installation unexpectedly succeeded." >&2
    exit 1
fi

SYSTEM_INSTALL_BIN_DIR="$TEMP_DIR/bin" \
    "$TOOL_ROOT/tools/install-system.sh" links --yes >/dev/null

for command_name in system cpu system-health system-repair gaming ai; do
    test -L "$TEMP_DIR/bin/$command_name"
    test -x "$TEMP_DIR/bin/$command_name"
done

"$TEMP_DIR/bin/system" help >/dev/null
"$TOOL_ROOT/tests/safety.sh"
echo "Smoke checks passed."

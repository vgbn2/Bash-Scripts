#!/usr/bin/env bash
# Unit test for Lossless Scaling framegen profile switcher
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
LS_SCRIPT="$TOOL_ROOT/gaming/lossless-scaling.sh"
SETTINGS="$HOME/.local/share/Steam/steamapps/compatdata/993090/pfx/drive_c/users/steamuser/AppData/Local/Lossless Scaling/Settings.xml"

assert_match() {
    local pattern=$1
    local file=$2
    if ! grep -q "$pattern" "$file"; then
        echo "Assertion failed: pattern '$pattern' not found in $file" >&2
        exit 1
    fi
}

# 1. Invalid profile returns error code 1
ret=0
"$LS_SCRIPT" profile invalid >/dev/null 2>&1 || ret=$?
if [ "$ret" -ne 1 ]; then
    echo "Expected exit code 1 for invalid profile, got $ret" >&2
    exit 1
fi

# 2. Switch to 2x profile
"$LS_SCRIPT" profile 2x >/dev/null
assert_match "<LSFG3Multiplier>2</LSFG3Multiplier>" "$SETTINGS"
assert_match "<LSFG3Target>100</LSFG3Target>" "$SETTINGS"

# 3. Switch to 3x profile
"$LS_SCRIPT" profile 3x >/dev/null
assert_match "<LSFG3Multiplier>3</LSFG3Multiplier>" "$SETTINGS"
assert_match "<LSFG3Target>144</LSFG3Target>" "$SETTINGS"

# 4. Switch to 4x profile with custom FPS
"$LS_SCRIPT" profile 4x 160 >/dev/null
assert_match "<LSFG3Multiplier>4</LSFG3Multiplier>" "$SETTINGS"
assert_match "<LSFG3Target>160</LSFG3Target>" "$SETTINGS"

# 5. Restore 2x profile
"$LS_SCRIPT" profile 2x 100 >/dev/null
assert_match "<LSFG3Multiplier>2</LSFG3Multiplier>" "$SETTINGS"

echo "PASS: test_lossless_scaling_profiles.sh completed successfully."

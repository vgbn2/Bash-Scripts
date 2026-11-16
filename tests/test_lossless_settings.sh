#!/usr/bin/env bash
# Pure shell regression tests for Lossless Scaling Settings.xml updates.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
LS_SCRIPT="$REPO_ROOT/gaming/lossless-scaling.sh"

TEMP_DIR=$(mktemp -d /tmp/opencode/ls-test-XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM

assert() {
    local msg="$1"
    shift
    if ! "$@"; then
        echo "FAIL: $msg" >&2
        exit 1
    fi
}

assert_match() {
    local pattern="$1"
    local file="$2"
    if ! grep -q "$pattern" "$file"; then
        echo "FAIL: pattern '$pattern' not found in $file" >&2
        exit 1
    fi
}

SAMPLE_XML='<Settings><Profiles><Profile><FrameGeneration>OFF</FrameGeneration><LSFG3Multiplier>2</LSFG3Multiplier><LSFG3Mode1>FIXED</LSFG3Mode1><LSFG3Target>60</LSFG3Target><DrawFps>false</DrawFps><CaptureApi>GDI</CaptureApi></Profile></Profiles></Settings>'

# 1. Verify malformed XML rejection and file preservation
TEST_HOME="$TEMP_DIR/home_malformed"
SETTINGS_DIR="$TEST_HOME/.local/share/Steam/steamapps/compatdata/993090/pfx/drive_c/users/steamuser/AppData/Local/Lossless Scaling"
SETTINGS_FILE="$SETTINGS_DIR/Settings.xml"
mkdir -p "$SETTINGS_DIR"
printf '<Settings><broken>' > "$SETTINGS_FILE"

rc=0
OUTPUT=$(HOME="$TEST_HOME" bash "$LS_SCRIPT" profile 3x 2>&1) || rc=$?
assert "Expected nonzero exit code on malformed XML" test "$rc" -ne 0
assert "Falsely reported 'Profile set' on malformed XML" test -z "$(grep 'Profile set' <<< "$OUTPUT")"
assert "Malformed XML file content was mutated" test "$(cat "$SETTINGS_FILE")" = '<Settings><broken>'

# 2. Verify empty and profile-free XML rejection
printf '' > "$SETTINGS_FILE"
rc=0
HOME="$TEST_HOME" bash "$LS_SCRIPT" profile 3x >/dev/null 2>&1 || rc=$?
assert "Empty XML must be rejected" test "$rc" -ne 0

printf '<Settings/>' > "$SETTINGS_FILE"
rc=0
HOME="$TEST_HOME" bash "$LS_SCRIPT" profile 3x >/dev/null 2>&1 || rc=$?
assert "Profile-free XML must be rejected" test "$rc" -ne 0

# 3. Verify missing file rejection
rm -f "$SETTINGS_FILE"
rc=0
HOME="$TEST_HOME" bash "$LS_SCRIPT" profile 3x >/dev/null 2>&1 || rc=$?
assert "Missing settings file must be rejected" test "$rc" -ne 0

# 4. Verify invalid parameter rejection
printf '%s' "$SAMPLE_XML" > "$SETTINGS_FILE"
for bad_args in "bad 2" "-1 2" "1.5 2" "100 9" "100 0"; do
    rc=0
    HOME="$TEST_HOME" bash "$LS_SCRIPT" tune $bad_args >/dev/null 2>&1 || rc=$?
    assert "Invalid arguments ($bad_args) unexpectedly succeeded" test "$rc" -ne 0
done

# 5. Verify valid profile updates and atomic modification (supports paths with spaces and apostrophes)
SPACED_HOME="$TEMP_DIR/player's home"
SPACED_DIR="$SPACED_HOME/.local/share/Steam/steamapps/compatdata/993090/pfx/drive_c/users/steamuser/AppData/Local/Lossless Scaling"
SPACED_FILE="$SPACED_DIR/Settings.xml"
mkdir -p "$SPACED_DIR"
printf '%s' "$SAMPLE_XML" > "$SPACED_FILE"

# 2x profile
HOME="$SPACED_HOME" bash "$LS_SCRIPT" profile 2x >/dev/null
assert_match '<LSFG3Multiplier>2</LSFG3Multiplier>' "$SPACED_FILE"
assert_match '<LSFG3Target>100</LSFG3Target>' "$SPACED_FILE"
assert_match '<LSFG3Mode1>ADAPTIVE</LSFG3Mode1>' "$SPACED_FILE"

# 3x profile
HOME="$SPACED_HOME" bash "$LS_SCRIPT" profile 3x >/dev/null
assert_match '<LSFG3Multiplier>3</LSFG3Multiplier>' "$SPACED_FILE"
assert_match '<LSFG3Target>144</LSFG3Target>' "$SPACED_FILE"

# 4x profile with custom FPS
HOME="$SPACED_HOME" bash "$LS_SCRIPT" profile 4x 160 >/dev/null
assert_match '<LSFG3Multiplier>4</LSFG3Multiplier>' "$SPACED_FILE"
assert_match '<LSFG3Target>160</LSFG3Target>' "$SPACED_FILE"

# FIXED mode on target_fps=0
HOME="$SPACED_HOME" bash "$LS_SCRIPT" tune 0 2 >/dev/null
assert_match '<LSFG3Mode1>FIXED</LSFG3Mode1>' "$SPACED_FILE"

# 6. Symlink target preservation
SYMLINK_TARGET="$TEMP_DIR/real_settings.xml"
printf '%s' "$SAMPLE_XML" > "$SYMLINK_TARGET"
rm -f "$SPACED_FILE"
ln -s "$SYMLINK_TARGET" "$SPACED_FILE"

HOME="$SPACED_HOME" bash "$LS_SCRIPT" profile 2x >/dev/null
assert "Symlink was replaced with regular file" test -L "$SPACED_FILE"
assert_match '<LSFG3Multiplier>2</LSFG3Multiplier>' "$SYMLINK_TARGET"

echo "PASS: test_lossless_settings.sh (all pure shell assertions passed cleanly)"

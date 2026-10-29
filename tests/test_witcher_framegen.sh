#!/usr/bin/env bash
# Unit tests for Witcher 3 Lossless Scaling launcher and configuration optimizer
set -euo pipefail

TOOL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT

assert_status() {
    local expected=$1
    shift
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    [ "$actual" -eq "$expected" ] || {
        echo "Assertion failed: expected $expected, got $actual: $*" >&2
        exit 1
    }
}

assert_match() {
    local pattern=$1
    local text=$2
    if ! echo "$text" | grep -q "$pattern"; then
        echo "Assertion failed: pattern '$pattern' not found in:" >&2
        echo "$text" >&2
        exit 1
    fi
}

assert_no_match() {
    local pattern=$1
    local text=$2
    if echo "$text" | grep -q "$pattern"; then
        echo "Assertion failed: unexpected pattern '$pattern' found in:" >&2
        echo "$text" >&2
        exit 1
    fi
}

# 1. Test CLI help and invalid arguments
help_out=$("$TOOL_ROOT/gaming/witcher3-framegen.sh" help)
assert_match "Usage: witcher3-framegen.sh" "$help_out"
assert_match "FullScreenMode=1" "$help_out"
assert_match "P-Cores:" "$help_out"

assert_status 2 "$TOOL_ROOT/gaming/witcher3-framegen.sh" invalid_command

# 2. Test configuration optimization on mock dx12user.settings and user.settings
mock_docs="$TEMP_DIR/docs"
mock_ls="$TEMP_DIR/ls"
mkdir -p "$mock_docs" "$mock_ls"

cat > "$mock_docs/dx12user.settings" <<'EOF'
[Viewport]
VSync=true
Resolution="1920x1080"
FullScreenMode=2
ReflexMode=0

[Engine]
LimitFPS=144

[Rendering]
AllowReflex=false
EOF

cat > "$mock_docs/user.settings" <<'EOF'
[Viewport]
VSync=true
FullScreenMode=2

[Engine]
LimitFPS=144
EOF

cat > "$mock_ls/Settings.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<Settings>
  <GameProfiles>
    <Profile>
      <Title>Default</Title>
      <FrameGeneration>Off</FrameGeneration>
      <LSFG3Multiplier>1</LSFG3Multiplier>
      <LSFG3Mode1>FIXED</LSFG3Mode1>
      <LSFG3Target>60</LSFG3Target>
      <CaptureApi>GDI</CaptureApi>
      <DrawFps>false</DrawFps>
      <GsyncSupport>false</GsyncSupport>
      <MaxFrameLatency>3</MaxFrameLatency>
    </Profile>
  </GameProfiles>
</Settings>
EOF

opt_out=$(WITCHER_DOCS_OVERRIDE="$mock_docs" LS_CONFIG_DIR_OVERRIDE="$mock_ls" \
    "$TOOL_ROOT/gaming/witcher3-framegen.sh" optimize 60 144)

assert_match "FullScreenMode=1" "$opt_out"
assert_match "Frame Limiter capped at 60 FPS" "$opt_out"
assert_match "ReflexMode=1" "$opt_out"
assert_match "144 FPS target" "$opt_out"

# Verify actual modified files on disk
assert_match "FullScreenMode=1" "$(cat "$mock_docs/dx12user.settings")"
assert_match "VSync=false" "$(cat "$mock_docs/dx12user.settings")"
assert_match "ReflexMode=1" "$(cat "$mock_docs/dx12user.settings")"
assert_match "LimitFPS=60" "$(cat "$mock_docs/dx12user.settings")"
assert_match "AllowReflex=true" "$(cat "$mock_docs/dx12user.settings")"

assert_match "FullScreenMode=1" "$(cat "$mock_docs/user.settings")"
assert_match "LimitFPS=60" "$(cat "$mock_docs/user.settings")"

assert_match "<FrameGeneration>LSFG3</FrameGeneration>" "$(cat "$mock_ls/Settings.xml")"
assert_match "<LSFG3Target>144</LSFG3Target>" "$(cat "$mock_ls/Settings.xml")"
assert_match "<CaptureApi>DXGI</CaptureApi>" "$(cat "$mock_ls/Settings.xml")"
assert_match "<DrawFps>true</DrawFps>" "$(cat "$mock_ls/Settings.xml")"

# 3. Test status inspection report
status_out=$(WITCHER_DOCS_OVERRIDE="$mock_docs" LS_CONFIG_DIR_OVERRIDE="$mock_ls" \
    "$TOOL_ROOT/gaming/witcher3-framegen.sh" status)

assert_match "Borderless (OPTIMAL for Lossless Scaling)" "$status_out"
assert_match "In-Engine FPS: 60 FPS (OPTIMAL: 16.6ms steady pacing)" "$status_out"
assert_match "VSync:         false (OPTIMAL: lowest input latency)" "$status_out"
assert_match "NVIDIA Reflex: 1 (Active)" "$status_out"
assert_match "Target FPS:   144 FPS (2x ADAPTIVE)" "$status_out"

# 4. Test gaming dispatcher integration
dispatch_help=$("$TOOL_ROOT/gaming/gaming" framegen witcher help)
assert_match "Usage: witcher3-framegen.sh" "$dispatch_help"

dispatch_status=$(WITCHER_DOCS_OVERRIDE="$mock_docs" LS_CONFIG_DIR_OVERRIDE="$mock_ls" \
    "$TOOL_ROOT/gaming/gaming" framegen witcher status)
assert_match "The Witcher 3: Lossless Scaling & Graphics Audit" "$dispatch_status"

echo "PASS: test_witcher_framegen.sh completed successfully."

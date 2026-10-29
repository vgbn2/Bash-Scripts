#!/usr/bin/env bash
# Unit tests for SystemBash hardware undervolt persistence
set -euo pipefail

TOOL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

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
        echo "Assertion failed: pattern '$pattern' not found" >&2
        exit 1
    fi
}

# 1. Test invalid arguments return exit status 2
assert_status 2 "$TOOL_ROOT/hardware/undervolt" persist invalid
assert_status 2 "$TOOL_ROOT/hardware/undervolt" service invalid

# 2. Test systemd unit generation
unit_out=$("$TOOL_ROOT/hardware/undervolt" persist unit)
assert_match "\[Unit\]" "$unit_out"
assert_match "ExecStart=.*undervolt.*--core -60 --cache -60 -p1 28 28 -p2 35 0.0024" "$unit_out"
assert_match "3200000" "$unit_out"
assert_match "nvidia-smi -lgc 210,1600" "$unit_out"

echo "PASS: test_undervolt.sh completed successfully."

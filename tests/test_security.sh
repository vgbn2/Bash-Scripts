#!/usr/bin/env bash
# Unit and behavioral safety tests for the security and pentest toolkit.

set -euo pipefail

TOOL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

expect_status() {
    local expected=$1
    shift
    local actual=0

    "$@" >/dev/null 2>&1 || actual=$?
    [ "$actual" -eq "$expected" ] ||
        fail "expected status $expected, got $actual: $*"
}

# 1. Verify syntax of all security library files
echo "[*] Checking bash syntax on security tools..."
bash -n "$TOOL_ROOT/security/security"
for f in "$TOOL_ROOT/security/security-lib/"*.sh; do
    bash -n "$f"
done
bash -n "$TOOL_ROOT/system/system-lib/security.sh"

# 2. Help output verification
echo "[*] Verifying help commands..."
"$TOOL_ROOT/security/security" help | grep -q "Usage: security <command>" || fail "security help missing usage"
"$TOOL_ROOT/system/system" security help | grep -q "Usage: security <command>" || fail "system security help missing usage"

# 3. Invalid commands exit with status 2
echo "[*] Verifying invalid command exit status..."
expect_status 2 "$TOOL_ROOT/security/security" invalid_action
expect_status 2 "$TOOL_ROOT/security/security" audit invalid_target
expect_status 2 "$TOOL_ROOT/security/security" cheatsheet invalid_topic

# 4. Host hardening audit components (read-only)
echo "[*] Verifying host audits run cleanly..."
"$TOOL_ROOT/security/security" audit ports >"$TEMP_DIR/ports.log"
grep -q "Listening Services" "$TEMP_DIR/ports.log" || fail "audit ports output missing section header"

"$TOOL_ROOT/security/security" audit privs >"$TEMP_DIR/privs.log"
grep -q "Privileged Accounts" "$TEMP_DIR/privs.log" || fail "audit privs output missing section header"

"$TOOL_ROOT/security/security" audit firewall >"$TEMP_DIR/firewall.log"
grep -q "Firewall" "$TEMP_DIR/firewall.log" || fail "audit firewall output missing section header"

"$TOOL_ROOT/security/security" audit kernel >"$TEMP_DIR/kernel.log"
grep -q "Kernel Security Parameters" "$TEMP_DIR/kernel.log" || fail "audit kernel output missing section header"

# 5. Cheatsheets & Guides
echo "[*] Verifying cheatsheets and capacity guidelines..."
"$TOOL_ROOT/security/security" cheatsheet overview | grep -q "Available topics" || fail "cheatsheet overview missing"
"$TOOL_ROOT/security/security" cheatsheet capacity | grep -q "Capacity Testing vs DoS" || fail "capacity cheatsheet missing"
"$TOOL_ROOT/security/security" cheatsheet recon | grep -q "Network Discovery" || fail "recon cheatsheet missing"
"$TOOL_ROOT/security/security" cheatsheet web | grep -q "Web Application Security" || fail "web cheatsheet missing"

# 6. External Exposure Audit
echo "[*] Verifying external exposure audit..."
"$TOOL_ROOT/security/security" exposure >"$TEMP_DIR/exposure.log"
grep -q "External Attack Surface" "$TEMP_DIR/exposure.log" || fail "exposure missing header"

# 7. Local Server Capacity Benchmark Test
echo "[*] Testing capacity benchmark against mock local listener..."
MOCK_PORT=19876
python3 -m http.server "$MOCK_PORT" --directory "$TEMP_DIR" >/dev/null 2>&1 &
MOCK_PID=$!
sleep 0.5

"$TOOL_ROOT/security/security" capacity "http://127.0.0.1:$MOCK_PORT" 2 6 >"$TEMP_DIR/capacity.log"
kill -9 "$MOCK_PID"
grep -q -E "Capacity Benchmark Results|Requests per second" "$TEMP_DIR/capacity.log" || fail "capacity benchmark missing results header"

echo "[+] All security toolkit tests passed successfully."

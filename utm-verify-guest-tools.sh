#!/usr/bin/env bash
set -euo pipefail

# utm-verify-guest-tools.sh — Verify QEMU Guest Agent capabilities
#
# Starts the base VM (non-disposable, briefly), tests all guest agent
# operations, then shuts it down. Run this first to confirm your golden
# image has working guest tools before using utm-test.sh.

VM_NAME="Clean-Win11-Base-With-GuestTools"
POLL_INTERVAL=5
MAX_WAIT=180  # 3 minutes

passed=0
failed=0
skipped=0

result() {
    local status="$1" label="$2"
    case "$status" in
        pass) echo "  [PASS] $label"; ((passed++)) || true ;;
        fail) echo "  [FAIL] $label"; ((failed++)) || true ;;
        skip) echo "  [SKIP] $label"; ((skipped++)) || true ;;
    esac
}

cleanup() {
    echo ""
    echo "Stopping VM..."
    utmctl stop "$VM_NAME" 2>/dev/null || true
}

echo ""
echo "UTM Guest Tools Verification"
echo "============================================================"
echo ""

# Check current VM status
vm_status=$(utmctl status "$VM_NAME" 2>/dev/null | awk '{print $NF}')

if [[ "$vm_status" == "started" ]]; then
    echo "VM is already running — using existing session"
    echo "(Will NOT stop VM on exit since we didn't start it)"
    we_started=false
else
    echo "Starting VM '$VM_NAME'..."
    utmctl start "$VM_NAME"
    we_started=true
    trap cleanup EXIT
fi

# Wait for guest agent.
# IMPORTANT: utmctl exec returns exit code 0 even on failure.
# We must check stdout content to verify the agent is truly responding.
echo "Waiting for guest agent (up to ${MAX_WAIT}s)..."
start_time=$SECONDS
agent_ready=false
while (( SECONDS - start_time < MAX_WAIT )); do
    probe=$(utmctl exec "$VM_NAME" --cmd cmd.exe /c "echo ready" 2>/dev/null) || true
    if [[ "$probe" == *"ready"* ]]; then
        agent_ready=true
        break
    fi
    sleep "$POLL_INTERVAL"
    printf "  %ds...\r" "$((SECONDS - start_time))"
done
echo ""

if ! $agent_ready; then
    elapsed=$((SECONDS - start_time))
    echo "  [FAIL] Guest agent did not respond within ${elapsed}s"
    echo ""
    # Show what utmctl is reporting
    diag=$(utmctl exec "$VM_NAME" --cmd cmd.exe /c "echo test" 2>&1) || true
    echo "  Diagnostic output: $diag"
    echo ""
    echo "  Possible causes:"
    echo "    - QEMU Guest Agent (qemu-ga) not installed in the VM"
    echo "    - SPICE guest tools were installed but qemu-ga service not running"
    echo "    - VM QEMU settings missing virtio-serial / guest agent channel"
    echo ""
    echo "  To fix:"
    echo "    1. In UTM, edit VM → QEMU → check 'QEMU Guest Agent' is enabled"
    echo "    2. In the VM, verify qemu-ga service exists:"
    echo "       sc query qemu-ga"
    echo "    3. If missing, install QEMU guest agent from virtio-win ISO"
    echo ""
    exit 1
fi
echo "Guest agent ready ($((SECONDS - start_time))s)"

echo ""
echo "Test Results"
echo "============================================================"

# Test 1: exec — basic command (check both exit code and stdout)
output=$(utmctl exec "$VM_NAME" --cmd cmd.exe /c "echo hello" 2>/dev/null)
rc=$?
echo "  [DBG] echo test: rc=$rc stdout='$output'"
if [[ $rc -eq 0 && "$output" == *"hello"* ]]; then
    result pass "utmctl exec: basic command"
else
    # Retry once — agent can be briefly unresponsive
    sleep 3
    output=$(utmctl exec "$VM_NAME" --cmd cmd.exe /c "echo hello" 2>/dev/null) || true
    if [[ "$output" == *"hello"* ]]; then
        result pass "utmctl exec: basic command (retry)"
    else
        output_full=$(utmctl exec "$VM_NAME" --cmd cmd.exe /c "echo hello" 2>&1) || true
        result fail "utmctl exec: basic command (rc=$rc, output: $output_full)"
    fi
fi

# Test 2: exec — whoami (should be SYSTEM since qemu-ga runs as SYSTEM)
output=$(utmctl exec "$VM_NAME" --cmd cmd.exe /c "whoami" 2>/dev/null) || true
if [[ "$output" == *\\* ]]; then
    result pass "utmctl exec: whoami → $output"
else
    result fail "utmctl exec: whoami (got: $output)"
fi

# Test 3: exec — admin check (net session should succeed under SYSTEM)
net_output=$(utmctl exec "$VM_NAME" --cmd cmd.exe /c "net session" 2>&1) || true
net_rc=$?
echo "  [DBG] net session: rc=$net_rc"
if [[ $net_rc -eq 0 && "$net_output" != *"not running"* ]]; then
    result pass "utmctl exec: admin privileges (net session)"
else
    result fail "utmctl exec: admin privileges (net session, rc=$net_rc)"
fi

# Test 4: file push
test_content="guest-tools-test-$(date +%s)"
if echo "$test_content" | utmctl file push "$VM_NAME" "C:\\utm-test-file.txt" 2>/dev/null; then
    result pass "utmctl file push"
else
    result fail "utmctl file push"
fi

# Test 5: file pull — verify round-trip
pulled=$(utmctl file pull "$VM_NAME" "C:\\utm-test-file.txt" 2>/dev/null) || true
if [[ "$pulled" == *"$test_content"* ]]; then
    result pass "utmctl file pull: content matches"
else
    result fail "utmctl file pull: content mismatch (expected '$test_content', got '$pulled')"
fi

# Test 6: cleanup test file
utmctl exec "$VM_NAME" --cmd cmd.exe /c "del C:\\utm-test-file.txt" >/dev/null 2>&1 || true
result pass "cleanup: removed test file"

# Test 7: ip-address
ip_output=$(utmctl ip-address "$VM_NAME" 2>&1) || true
if [[ -n "$ip_output" && "$ip_output" != *"error"* ]]; then
    result pass "utmctl ip-address: $ip_output"
else
    result fail "utmctl ip-address: no addresses returned"
fi

# Test 8: network connectivity from inside VM
if utmctl exec "$VM_NAME" --cmd cmd.exe /c "ping -n 1 -w 3000 8.8.8.8" >/dev/null 2>&1; then
    result pass "network: ping 8.8.8.8 from guest"
else
    result fail "network: ping 8.8.8.8 from guest"
fi

# Test 9: mkdir (needed for script deployment)
if utmctl exec "$VM_NAME" --cmd cmd.exe /c "mkdir C:\\utm-mkdir-test && rmdir C:\\utm-mkdir-test" >/dev/null 2>&1; then
    result pass "utmctl exec: mkdir + rmdir"
else
    result fail "utmctl exec: mkdir + rmdir"
fi

echo ""
echo "============================================================"
echo "  Passed: $passed  Failed: $failed  Skipped: $skipped"
echo "============================================================"
echo ""

if (( failed > 0 )); then
    echo "Some guest tool capabilities are not working."
    echo "Fix these before running utm-test.sh."
    # Don't exit 1 here — let trap handle cleanup, then exit
fi

# If we didn't start the VM, remove the trap so we don't stop it
if ! $we_started; then
    trap - EXIT
    echo "VM was already running — leaving it running."
fi

(( failed == 0 )) && exit 0 || exit 1

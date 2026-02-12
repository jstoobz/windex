#!/usr/bin/env bash
set -euo pipefail

# utm-verify-guest-tools.sh — Verify SSH + VM connectivity
#
# Starts the base VM (non-disposable, briefly), tests SSH access and
# file transfer, then shuts it down. Run this after setting up OpenSSH
# Server in the golden image.

# Load shared configuration
source "$(dirname "$0")/utm.conf"

SSH_USER="${1:-}" # Pass Windows username as first arg

passed=0
failed=0

result() {
    local status="$1" label="$2"
    case "$status" in
        pass)
            echo "  [PASS] $label"
            ((passed++)) || true
            ;;
        fail)
            echo "  [FAIL] $label"
            ((failed++)) || true
            ;;
    esac
}

ssh_cmd() {
    ssh -F /dev/null -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
        -o LogLevel=ERROR "$SSH_USER@localhost" "$@"
}

cleanup() {
    echo ""
    echo "Stopping VM..."
    utmctl stop "$VM_NAME" 2> /dev/null || true
}

if [[ -z "$SSH_USER" ]]; then
    echo "Usage: utm-verify-guest-tools.sh <windows-username>"
    echo ""
    echo "The Windows username from the golden image (e.g. 'User')."
    exit 1
fi

echo ""
echo "UTM SSH Connectivity Verification"
echo "============================================================"
echo ""

# Prereqs
if [[ ! -f "$SSH_KEY" ]]; then
    echo "  [FAIL] SSH key not found: $SSH_KEY"
    echo "  Run: ssh-keygen -t ed25519 -f $SSH_KEY -N '' -C 'utm-vm-automation'"
    exit 1
fi

# Check current VM status
vm_status=$(utmctl status "$VM_NAME" 2> /dev/null | awk '{print $NF}')

if [[ "$vm_status" == "started" ]]; then
    echo "VM is already running — using existing session"
    echo "(Will NOT stop VM on exit since we didn't start it)"
    we_started=false
else
    echo "Starting VM '$VM_NAME' (disposable)..."
    utmctl start --disposable "$VM_NAME"
    we_started=true
    trap cleanup EXIT
fi

# Wait for SSH
echo "Waiting for SSH on localhost:$SSH_PORT (up to ${MAX_WAIT}s)..."
start_time=$SECONDS
ssh_ready=false
while ((SECONDS - start_time < MAX_WAIT)); do
    if ssh_cmd "echo ready" 2> /dev/null | grep -q "ready"; then
        ssh_ready=true
        break
    fi
    sleep "$POLL_INTERVAL"
    printf "  %ds...\r" "$((SECONDS - start_time))"
done
echo ""

if ! $ssh_ready; then
    elapsed=$((SECONDS - start_time))
    echo "  [FAIL] SSH did not respond within ${elapsed}s"
    echo ""
    echo "  Checklist:"
    echo "    1. OpenSSH Server installed in VM? (run setup-openssh-server.ps1)"
    echo "    2. Port forward configured? (host:2222 → guest:22)"
    echo "    3. SSH key authorized? (check administrators_authorized_keys)"
    echo "    4. Correct username? (you passed: '$SSH_USER')"
    echo ""
    echo "  Quick test from another terminal:"
    echo "    ssh -i $SSH_KEY -p $SSH_PORT -v $SSH_USER@localhost"
    echo ""
    exit 1
fi
echo "SSH ready ($((SECONDS - start_time))s)"

echo ""
echo "Test Results"
echo "============================================================"

# Test 1: basic command
output=$(ssh_cmd "echo hello" 2> /dev/null) || true
if [[ "$output" == *"hello"* ]]; then
    result pass "SSH exec: basic command"
else
    result fail "SSH exec: basic command (got: $output)"
fi

# Test 2: whoami
output=$(ssh_cmd "whoami" 2> /dev/null) || true
if [[ "$output" == *\\* || "$output" == *"$SSH_USER"* ]]; then
    result pass "SSH exec: whoami → $output"
else
    result fail "SSH exec: whoami (got: $output)"
fi

# Test 3: admin check
if ssh_cmd "net session" > /dev/null 2>&1; then
    result pass "SSH exec: admin privileges (net session)"
else
    result fail "SSH exec: admin privileges (net session — may need admin shell)"
fi

# Test 4: file transfer via scp (push)
test_content="ssh-test-$(date +%s)"
test_file=$(mktemp)
echo "$test_content" > "$test_file"
if scp -F /dev/null -i "$SSH_KEY" -P "$SSH_PORT" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "$test_file" "$SSH_USER@localhost:C:/utm-test-file.txt" 2> /dev/null; then
    result pass "SCP push"
else
    result fail "SCP push"
fi

# Test 5: file transfer via scp (pull + verify)
pull_file=$(mktemp)
if scp -F /dev/null -i "$SSH_KEY" -P "$SSH_PORT" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "$SSH_USER@localhost:C:/utm-test-file.txt" "$pull_file" 2> /dev/null; then
    pulled=$(cat "$pull_file")
    if [[ "$pulled" == *"$test_content"* ]]; then
        result pass "SCP pull: content matches"
    else
        result fail "SCP pull: content mismatch"
    fi
else
    result fail "SCP pull"
fi
rm -f "$test_file" "$pull_file"

# Test 6: cleanup
ssh_cmd "del C:\\utm-test-file.txt" > /dev/null 2>&1 || true
result pass "cleanup: removed test file"

# Test 7: network from inside VM
if ssh_cmd "ping -n 1 -w 3000 8.8.8.8" > /dev/null 2>&1; then
    result pass "network: ping 8.8.8.8 from guest"
else
    result fail "network: ping 8.8.8.8 from guest"
fi

# Test 8: mkdir (needed for script deployment)
if ssh_cmd "mkdir C:\\utm-mkdir-test && rmdir C:\\utm-mkdir-test" > /dev/null 2>&1; then
    result pass "SSH exec: mkdir + rmdir"
else
    result fail "SSH exec: mkdir + rmdir"
fi

echo ""
echo "============================================================"
echo "  Passed: $passed  Failed: $failed"
echo "============================================================"
echo ""

if ((failed > 0)); then
    echo "Some capabilities are not working."
    echo "Fix these before running utm-test.sh."
fi

# If we didn't start the VM, remove the trap so we don't stop it
if ! $we_started; then
    trap - EXIT
    echo "VM was already running — leaving it running."
fi

((failed == 0)) && exit 0 || exit 1

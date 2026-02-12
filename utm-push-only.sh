#!/usr/bin/env bash
set -euo pipefail

# utm-push-only.sh — Push scripts to an already-running VM via SCP
#
# Quick utility for when the VM is running (e.g. --keep-running from
# utm-test.sh) and you just want to update the scripts without restarting.
#
# Usage: utm-push-only.sh <windows-username> [vm-name]

# Load shared configuration
source "$(dirname "$0")/utm.conf"

SSH_USER="${1:-}"
# Allow overriding VM name as second arg
if [[ -n "${2:-}" ]]; then VM_NAME="$2"; fi

if [[ -z "$SSH_USER" ]]; then
    echo "Usage: utm-push-only.sh <windows-username> [vm-name]"
    exit 1
fi

# Verify VM is running
vm_status=$(utmctl status "$VM_NAME" 2>/dev/null | awk '{print $NF}')
if [[ "$vm_status" != "started" ]]; then
    echo "ERROR: VM '$VM_NAME' is not running (status: $vm_status)"
    echo "Start it first, or use utm-test.sh for a full test cycle."
    exit 1
fi

# Verify SSH is reachable
if ! ssh "${SSH_COMMON[@]}" -p "$SSH_PORT" "$SSH_USER@localhost" "echo ok" >/dev/null 2>&1; then
    echo "ERROR: Cannot SSH to $SSH_USER@localhost:$SSH_PORT"
    exit 1
fi

echo "Pushing scripts to '$VM_NAME' via SCP..."

# Ensure directories exist (backslashes for cmd.exe)
GUEST_DIR_WIN="${GUEST_DIR//\//\\}"
ssh "${SSH_COMMON[@]}" -p "$SSH_PORT" "$SSH_USER@localhost" \
    "cmd.exe /c mkdir ${GUEST_DIR_WIN}\\scripts\\lib" \
    >/dev/null 2>&1 || true

count=0

for f in "$SCRIPTS_DIR"/*.bat; do
    [[ -f "$f" ]] || continue
    fname=$(basename "$f")
    if scp "${SSH_COMMON[@]}" -P "$SSH_PORT" "$f" "$SSH_USER@localhost:$GUEST_SCRIPTS/$fname" 2>/dev/null; then
        echo "  → $fname"
        ((count++)) || true
    else
        echo "  ✗ $fname (failed)"
    fi
done

if scp "${SSH_COMMON[@]}" -P "$SSH_PORT" "$SCRIPTS_DIR/lib/config.bat" "$SSH_USER@localhost:$GUEST_LIB/config.bat" 2>/dev/null; then
    echo "  → lib/config.bat"
    ((count++)) || true
else
    echo "  ✗ lib/config.bat (failed)"
fi

echo ""
echo "Pushed $count files."

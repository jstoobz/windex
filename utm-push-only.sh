#!/usr/bin/env bash
set -euo pipefail

# utm-push-only.sh — Push scripts to an already-running VM via SCP
#
# Quick utility for when the VM is running (e.g. --keep-running from
# utm-test.sh) and you just want to update the scripts without restarting.
#
# Usage: utm-push-only.sh <windows-username> [vm-name]

SSH_USER="${1:-}"
VM_NAME="${2:-Win11-Golden}"
SSH_KEY="$HOME/.ssh/utm_vm"
SSH_PORT=2222
SCRIPTS_DIR="$HOME/utm/scripts"
GUEST_SCRIPTS="C:/mah-setup/scripts"
GUEST_LIB="$GUEST_SCRIPTS/lib"

SSH_OPTS=(-i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR)

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
if ! ssh "${SSH_OPTS[@]}" "$SSH_USER@localhost" "echo ok" >/dev/null 2>&1; then
    echo "ERROR: Cannot SSH to $SSH_USER@localhost:$SSH_PORT"
    exit 1
fi

echo "Pushing scripts to '$VM_NAME' via SCP..."

# Ensure directories exist
ssh "${SSH_OPTS[@]}" "$SSH_USER@localhost" \
    "cmd.exe /c \"if not exist $GUEST_SCRIPTS mkdir $GUEST_SCRIPTS & if not exist $GUEST_LIB mkdir $GUEST_LIB\"" \
    >/dev/null 2>&1 || true

count=0

for f in "$SCRIPTS_DIR"/*.bat; do
    [[ -f "$f" ]] || continue
    fname=$(basename "$f")
    if scp "${SSH_OPTS[@]}" -P "$SSH_PORT" "$f" "$SSH_USER@localhost:$GUEST_SCRIPTS/$fname" 2>/dev/null; then
        echo "  → $fname"
        ((count++)) || true
    else
        echo "  ✗ $fname (failed)"
    fi
done

if scp "${SSH_OPTS[@]}" -P "$SSH_PORT" "$SCRIPTS_DIR/lib/config.bat" "$SSH_USER@localhost:$GUEST_LIB/config.bat" 2>/dev/null; then
    echo "  → lib/config.bat"
    ((count++)) || true
else
    echo "  ✗ lib/config.bat (failed)"
fi

echo ""
echo "Pushed $count files."

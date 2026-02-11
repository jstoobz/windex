#!/usr/bin/env bash
set -euo pipefail

# utm-push-only.sh — Push scripts to an already-running VM
#
# Quick utility for when the VM is running (e.g. --keep-running from
# utm-test.sh) and you just want to update the scripts without restarting.
#
# Usage: utm-push-only.sh [vm-name]

VM_NAME="${1:-Clean-Win11-Base-With-GuestTools}"
SCRIPTS_DIR="$HOME/utm/scripts"
GUEST_SCRIPTS="C:\\mah-setup\\scripts"
GUEST_LIB="$GUEST_SCRIPTS\\lib"

# Verify VM is running
vm_status=$(utmctl status "$VM_NAME" 2>/dev/null | awk '{print $NF}')
if [[ "$vm_status" != "started" ]]; then
    echo "ERROR: VM '$VM_NAME' is not running (status: $vm_status)"
    echo "Start it first, or use utm-test.sh for a full test cycle."
    exit 1
fi

echo "Pushing scripts to '$VM_NAME'..."

# Ensure directories exist
utmctl exec "$VM_NAME" --cmd cmd.exe /c \
    "if not exist $GUEST_SCRIPTS mkdir $GUEST_SCRIPTS & if not exist $GUEST_LIB mkdir $GUEST_LIB" \
    >/dev/null 2>&1 || true

count=0

for f in "$SCRIPTS_DIR"/*.bat; do
    [[ -f "$f" ]] || continue
    fname=$(basename "$f")
    if cat "$f" | utmctl file push "$VM_NAME" "${GUEST_SCRIPTS}\\${fname}" 2>/dev/null; then
        echo "  → $fname"
        ((count++))
    else
        echo "  ✗ $fname (failed)"
    fi
done

if cat "$SCRIPTS_DIR/lib/config.bat" | utmctl file push "$VM_NAME" "${GUEST_LIB}\\config.bat" 2>/dev/null; then
    echo "  → lib/config.bat"
    ((count++))
else
    echo "  ✗ lib/config.bat (failed)"
fi

echo ""
echo "Pushed $count files."

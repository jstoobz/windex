#!/usr/bin/env bash
set -euo pipefail

# utm-env-check.sh — Verify environment prerequisites for UTM VM testing

# Load shared configuration
source "$(dirname "$0")/utm.conf"

MIN_DISK_GB=10

passed=0
failed=0

check() {
    local label="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo "  [PASS] $label"
        ((passed++)) || true
    else
        echo "  [FAIL] $label"
        ((failed++)) || true
    fi
}

echo ""
echo "UTM Environment Check"
echo "============================================================"
echo ""

# 1. utmctl accessible
check "utmctl is installed" command -v utmctl

# 2. UTM is running (launch if not)
if ! pgrep -xq "UTM"; then
    echo "  [....] UTM not running — launching..."
    open -a UTM
    sleep 3
fi
check "UTM is running" pgrep -xq "UTM"

# 3. Base VM exists
check "VM '$VM_NAME' exists" utmctl status "$VM_NAME"

# 4. Disk space
avail_gb=$(df -g "$HOME" | awk 'NR==2 {print $4}')
if ((avail_gb >= MIN_DISK_GB)); then
    echo "  [PASS] Disk space: ${avail_gb}GB available (need ${MIN_DISK_GB}GB)"
    ((passed++)) || true
else
    echo "  [FAIL] Disk space: ${avail_gb}GB available (need ${MIN_DISK_GB}GB)"
    ((failed++)) || true
fi

# 5. Scripts directory exists and has batch files
bat_count=$(find "$SCRIPTS_DIR" -maxdepth 1 -name "*.bat" 2> /dev/null | wc -l | tr -d ' ')
if ((bat_count > 0)); then
    echo "  [PASS] Scripts directory: $bat_count .bat files found"
    ((passed++)) || true
else
    echo "  [FAIL] Scripts directory: no .bat files in $SCRIPTS_DIR"
    ((failed++)) || true
fi

# 6. config.bat exists
check "lib/config.bat exists" test -f "$SCRIPTS_DIR/lib/config.bat"

# 7. test-results directory (create if missing)
mkdir -p "$RESULTS_DIR"
check "test-results directory exists" test -d "$RESULTS_DIR"

echo ""
echo "============================================================"
echo "  Passed: $passed  Failed: $failed"
echo "============================================================"
echo ""

((failed == 0)) && exit 0 || exit 1

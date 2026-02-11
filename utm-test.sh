#!/usr/bin/env bash
set -euo pipefail

# utm-test.sh — Main iteration script for testing provisioning scripts
#
# Starts the base VM in disposable mode, pushes scripts, executes the
# master setup, pulls logs back, and optionally leaves VM running for
# manual inspection. Disk changes are discarded on shutdown.
#
# Usage:
#   utm-test.sh --authkey=tskey-auth-xxx [--dry-run] [--keep-running] [--verbose]

VM_NAME="Clean-Win11-Base-With-GuestTools"
SCRIPTS_DIR="$HOME/utm/scripts"
RESULTS_DIR="$HOME/utm/test-results"
GUEST_BASE="C:\\mah-setup"
GUEST_SCRIPTS="$GUEST_BASE\\scripts"
GUEST_LIB="$GUEST_SCRIPTS\\lib"
GUEST_LOGS="$GUEST_BASE\\logs"
GUEST_OUTPUT="$GUEST_BASE\\output"
POLL_INTERVAL=5
MAX_WAIT=180

# Parse arguments
AUTHKEY=""
DRY_RUN=false
KEEP_RUNNING=false
VERBOSE=false

for arg in "$@"; do
    case "$arg" in
        --authkey=*) AUTHKEY="${arg#--authkey=}" ;;
        --dry-run)   DRY_RUN=true ;;
        --keep-running) KEEP_RUNNING=true ;;
        --verbose)   VERBOSE=true ;;
        --help|-h)
            echo "Usage: utm-test.sh --authkey=tskey-auth-xxx [--dry-run] [--keep-running] [--verbose]"
            echo ""
            echo "Options:"
            echo "  --authkey=KEY     Tailscale auth key (required unless --dry-run)"
            echo "  --dry-run         Push scripts and run master in dry-run mode"
            echo "  --keep-running    Leave VM running after test for manual inspection"
            echo "  --verbose         Enable verbose output"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

if [[ -z "$AUTHKEY" && "$DRY_RUN" == false ]]; then
    echo "ERROR: --authkey=KEY is required (or use --dry-run)"
    exit 1
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }
verbose() { $VERBOSE && log "$*" || true; }

# Setup results directory with timestamp
run_id=$(date +%Y%m%d_%H%M%S)
run_dir="$RESULTS_DIR/$run_id"
mkdir -p "$run_dir"

cleanup() {
    if $KEEP_RUNNING; then
        log "VM left running (--keep-running). Stop manually with:"
        log "  utmctl stop '$VM_NAME'"
        log "  (Disk changes will be discarded on stop)"
    else
        log "Stopping VM (discarding all changes)..."
        utmctl stop "$VM_NAME" 2>/dev/null || true
    fi
}

echo ""
echo "UTM Test Run"
echo "============================================================"
echo "  Run ID:     $run_id"
echo "  Dry-run:    $DRY_RUN"
echo "  Keep VM:    $KEEP_RUNNING"
echo "  Results:    $run_dir"
echo "============================================================"
echo ""

# ── Step 1: Start VM in disposable mode ──────────────────────────
log "Starting VM in disposable mode..."
vm_status=$(utmctl status "$VM_NAME" 2>/dev/null | awk '{print $NF}')
if [[ "$vm_status" == "started" ]]; then
    echo "ERROR: VM is already running. Stop it first:"
    echo "  utmctl stop '$VM_NAME'"
    echo ""
    echo "Cannot start in disposable mode while VM is already running."
    exit 1
fi

trap cleanup EXIT
utmctl start --disposable "$VM_NAME"

# ── Step 2: Wait for guest agent ─────────────────────────────────
# utmctl exec returns exit code 0 even on failure — check stdout content
log "Waiting for guest agent..."
start_time=$SECONDS
agent_ready=false
while (( SECONDS - start_time < MAX_WAIT )); do
    probe=$(utmctl exec "$VM_NAME" --cmd cmd.exe /c "echo ready" 2>/dev/null) || true
    if [[ "$probe" == *"ready"* ]]; then
        agent_ready=true
        break
    fi
    sleep "$POLL_INTERVAL"
    verbose "  $((SECONDS - start_time))s..."
done

elapsed=$((SECONDS - start_time))
if ! $agent_ready; then
    log "FAIL: Guest agent did not respond within ${MAX_WAIT}s"
    log "$(utmctl exec "$VM_NAME" --cmd cmd.exe /c "echo test" 2>&1 || true)"
    exit 1
fi
log "Guest agent ready (${elapsed}s)"

# ── Step 3: Create target directories on guest ───────────────────
log "Creating directories on guest..."
utmctl exec "$VM_NAME" --cmd cmd.exe /c \
    "if not exist $GUEST_SCRIPTS mkdir $GUEST_SCRIPTS & if not exist $GUEST_LIB mkdir $GUEST_LIB & if not exist $GUEST_LOGS mkdir $GUEST_LOGS & if not exist $GUEST_OUTPUT mkdir $GUEST_OUTPUT" \
    >/dev/null 2>&1 || true

# ── Step 4: Push scripts ─────────────────────────────────────────
log "Pushing scripts to VM..."
push_count=0

# Push all .bat files from scripts/
for f in "$SCRIPTS_DIR"/*.bat; do
    [[ -f "$f" ]] || continue
    fname=$(basename "$f")
    verbose "  → $fname"
    if cat "$f" | utmctl file push "$VM_NAME" "${GUEST_SCRIPTS}\\${fname}" 2>/dev/null; then
        ((push_count++)) || true
    else
        log "WARN: Failed to push $fname"
    fi
done

# Push lib/config.bat
if cat "$SCRIPTS_DIR/lib/config.bat" | utmctl file push "$VM_NAME" "${GUEST_LIB}\\config.bat" 2>/dev/null; then
    ((push_count++)) || true
    verbose "  → lib/config.bat"
else
    log "ERROR: Failed to push lib/config.bat"
    exit 1
fi

log "Pushed $push_count files"

# Verify files landed
verbose "Verifying files on guest..."
utmctl exec "$VM_NAME" --cmd cmd.exe /c "dir \"$GUEST_SCRIPTS\"\\*.bat" >/dev/null 2>&1 || {
    log "ERROR: Scripts not found on guest after push"
    exit 1
}

# ── Step 5: Execute master script ────────────────────────────────
log "Executing setup master..."

# Build command
master_cmd="\"${GUEST_SCRIPTS}\\00-setup-master.bat\" --force"
if [[ -n "$AUTHKEY" ]]; then
    master_cmd="$master_cmd --authkey=$AUTHKEY"
fi
if $DRY_RUN; then
    master_cmd="$master_cmd --dry-run"
fi
if $VERBOSE; then
    master_cmd="$master_cmd --verbose"
fi

log "CMD: $master_cmd"
echo ""

# Run and capture output (tee to both console and file)
exec_output="$run_dir/exec-output.txt"
set +e
utmctl exec "$VM_NAME" --cmd cmd.exe /c "$master_cmd" 2>&1 | tee "$exec_output"
exec_exit=$?
set -e

echo ""
log "Master script exit code: $exec_exit"

# ── Step 6: Pull logs ────────────────────────────────────────────
log "Pulling logs from VM..."

# List log files on guest
log_list=$(utmctl exec "$VM_NAME" --cmd cmd.exe /c "dir /b \"$GUEST_LOGS\"\\*.log" 2>/dev/null) || true

if [[ -n "$log_list" ]]; then
    while IFS= read -r logfile; do
        logfile=$(echo "$logfile" | tr -d '\r')
        [[ -z "$logfile" ]] && continue
        verbose "  ← $logfile"
        utmctl file pull "$VM_NAME" "${GUEST_LOGS}\\${logfile}" > "$run_dir/$logfile" 2>/dev/null || {
            log "WARN: Failed to pull $logfile"
        }
    done <<< "$log_list"
else
    log "  No log files found on guest"
fi

# ── Step 7: Pull credentials file if it exists ───────────────────
if utmctl exec "$VM_NAME" --cmd cmd.exe /c "if exist \"$GUEST_OUTPUT\\credentials.txt\" echo exists" 2>/dev/null | grep -q "exists"; then
    log "Pulling credentials file..."
    utmctl file pull "$VM_NAME" "${GUEST_OUTPUT}\\credentials.txt" > "$run_dir/credentials.txt" 2>/dev/null && \
        chmod 600 "$run_dir/credentials.txt" || {
        log "WARN: Failed to pull credentials.txt"
    }
fi

# ── Summary ──────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "Test Run Summary"
echo "============================================================"
echo ""
echo "  Run ID:        $run_id"
echo "  Exit code:     $exec_exit"
echo "  Results dir:   $run_dir"
echo ""

# List what we pulled
echo "  Artifacts:"
for f in "$run_dir"/*; do
    [[ -f "$f" ]] || continue
    size=$(wc -c < "$f" | tr -d ' ')
    echo "    $(basename "$f") (${size} bytes)"
done

echo ""
if (( exec_exit == 0 )); then
    echo "  Result: PASS"
else
    echo "  Result: FAIL (exit code $exec_exit)"
fi
echo ""
echo "============================================================"

exit $exec_exit

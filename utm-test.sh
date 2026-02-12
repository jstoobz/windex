#!/usr/bin/env bash
set -euo pipefail

# utm-test.sh — Main iteration script for testing provisioning scripts
#
# Starts the base VM in disposable mode, pushes scripts via SCP, executes
# the master setup via SSH, pulls logs back, and optionally leaves VM
# running for manual inspection. Disk changes are discarded on shutdown.
#
# Usage:
#   utm-test.sh --user=<winuser> --authkey=tskey-auth-xxx [--dry-run] [--keep-running] [--verbose]

# Load shared configuration
source "$(dirname "$0")/utm.conf"

# Parse arguments
SSH_USER=""
AUTHKEY=""
DRY_RUN=false
KEEP_RUNNING=false
VERBOSE=false

for arg in "$@"; do
    case "$arg" in
        --user=*)    SSH_USER="${arg#--user=}" ;;
        --authkey=*) AUTHKEY="${arg#--authkey=}" ;;
        --dry-run)   DRY_RUN=true ;;
        --keep-running) KEEP_RUNNING=true ;;
        --verbose)   VERBOSE=true ;;
        --help|-h)
            echo "Usage: utm-test.sh --user=<winuser> --authkey=tskey-auth-xxx [options]"
            echo ""
            echo "Required:"
            echo "  --user=USER       Windows username in the VM"
            echo "  --authkey=KEY     Tailscale auth key (required unless --dry-run)"
            echo ""
            echo "Options:"
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

if [[ -z "$SSH_USER" ]]; then
    echo "ERROR: --user=<winuser> is required"
    exit 1
fi
if [[ -z "$AUTHKEY" && "$DRY_RUN" == false ]]; then
    echo "ERROR: --authkey=KEY is required (or use --dry-run)"
    exit 1
fi
# Batch script requires authkey even in dry-run; use placeholder
if [[ -z "$AUTHKEY" && "$DRY_RUN" == true ]]; then
    AUTHKEY="tskey-auth-dry-run-placeholder"
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }
verbose() { $VERBOSE && log "$*" || true; }

ssh_cmd() {
    ssh "${SSH_COMMON[@]}" -p "$SSH_PORT" "$SSH_USER@localhost" "$@"
}

scp_push() {
    scp "${SSH_COMMON[@]}" -P "$SSH_PORT" "$1" "$SSH_USER@localhost:$2" 2>/dev/null
}

scp_pull() {
    scp "${SSH_COMMON[@]}" -P "$SSH_PORT" "$SSH_USER@localhost:$1" "$2" 2>/dev/null
}

# Setup results directory with timestamp
run_id=$(date +%Y%m%d_%H%M%S)
run_dir="$RESULTS_DIR/$run_id"
mkdir -p "$run_dir"

cleanup() {
    if $KEEP_RUNNING; then
        log "VM left running (--keep-running). Stop manually with:"
        log "  utmctl stop '$VM_NAME'"
        log "  (Disk changes will be discarded on stop)"
        log ""
        log "SSH in with:"
        log "  ssh ${SSH_COMMON[*]} -p $SSH_PORT $SSH_USER@localhost"
    else
        log "Stopping VM (discarding all changes)..."
        utmctl stop "$VM_NAME" 2>/dev/null || true
    fi
}

echo ""
echo "UTM Test Run"
echo "============================================================"
echo "  Run ID:     $run_id"
echo "  User:       $SSH_USER"
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

# ── Step 2: Wait for SSH ─────────────────────────────────────────
log "Waiting for SSH..."
start_time=$SECONDS
ssh_ready=false
while (( SECONDS - start_time < MAX_WAIT )); do
    if ssh_cmd "echo ready" 2>/dev/null | grep -q "ready"; then
        ssh_ready=true
        break
    fi
    sleep "$POLL_INTERVAL"
    verbose "  $((SECONDS - start_time))s..."
done

elapsed=$((SECONDS - start_time))
if ! $ssh_ready; then
    log "FAIL: SSH did not respond within ${MAX_WAIT}s"
    exit 1
fi
log "SSH ready (${elapsed}s)"

# ── Step 3: Create target directories on guest ───────────────────
log "Creating directories on guest..."
# Convert forward slashes to backslashes for cmd.exe
GUEST_DIR_WIN="${GUEST_DIR//\//\\}"
ssh_cmd "cmd.exe /c mkdir ${GUEST_DIR_WIN}\\scripts\\lib & mkdir ${GUEST_DIR_WIN}\\logs & mkdir ${GUEST_DIR_WIN}\\output" \
    >/dev/null 2>&1 || true

# ── Step 4: Push scripts via SCP ─────────────────────────────────
log "Pushing scripts to VM..."
push_count=0

# Push all .bat files from scripts/
for f in "$SCRIPTS_DIR"/*.bat; do
    [[ -f "$f" ]] || continue
    fname=$(basename "$f")
    verbose "  → $fname"
    if scp_push "$f" "$GUEST_SCRIPTS/$fname"; then
        ((push_count++)) || true
    else
        log "WARN: Failed to push $fname"
    fi
done

# Push lib/*.bat
for f in "$SCRIPTS_DIR"/lib/*.bat; do
    [[ -f "$f" ]] || continue
    fname=$(basename "$f")
    if scp_push "$f" "$GUEST_LIB/$fname"; then
        ((push_count++)) || true
        verbose "  → lib/$fname"
    else
        log "ERROR: Failed to push lib/$fname"
        exit 1
    fi
done

log "Pushed $push_count files"

# ── Step 5: Execute master script ────────────────────────────────
log "Executing setup master..."

# Build command — set authkey as env var (cmd.exe splits = in args through SSH)
master_cmd=""
if [[ -n "$AUTHKEY" ]]; then
    master_cmd="set TAILSCALE_AUTHKEY=$AUTHKEY & "
fi
master_cmd="${master_cmd}${GUEST_DIR_WIN}\\scripts\\00-setup-master.bat --force"
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
ssh_cmd "$master_cmd" 2>&1 | tee "$exec_output"
exec_exit=$?
set -e

echo ""
log "Master script exit code: $exec_exit"

# ── Step 6: Pull logs ────────────────────────────────────────────
log "Pulling logs from VM..."

# List log files on guest
log_list=$(ssh_cmd "dir /b ${GUEST_DIR_WIN}\\logs\\*.log" 2>/dev/null) || true

if [[ -n "$log_list" ]]; then
    while IFS= read -r logfile; do
        logfile=$(echo "$logfile" | tr -d '\r')
        [[ -z "$logfile" ]] && continue
        verbose "  ← $logfile"
        scp_pull "$GUEST_DIR/logs/$logfile" "$run_dir/$logfile" || {
            log "WARN: Failed to pull $logfile"
        }
    done <<< "$log_list"
else
    log "  No log files found on guest"
fi

# ── Step 7: Pull credentials file if it exists ───────────────────
if ssh_cmd "if exist ${GUEST_DIR_WIN}\\output\\credentials.txt echo exists" 2>/dev/null | grep -q "exists"; then
    log "Pulling credentials file..."
    scp_pull "$GUEST_DIR/output/credentials.txt" "$run_dir/credentials.txt" && \
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

#!/usr/bin/env bash
set -euo pipefail

# utm-install-usb.sh — Build a Windows 11 ARM64 install USB with OOBE bypass
#
# Two modes:
#   Full USB:           utm-install-usb.sh <iso> <device> [options]
#   Autounattend only:  utm-install-usb.sh --autounattend-only <output.img>
#
# The full USB creates a bootable FAT32 drive from a Win11 ARM64 ISO with
# an autounattend.xml that bypasses the Microsoft account requirement.
#
# The autounattend-only mode creates a small FAT32 image containing just
# the answer file — attach alongside an ISO in UTM for testing.

# ── Autounattend XML ─────────────────────────────────────────────────
generate_xml() {
    local username="$1"
    local outfile="$2"

    cat > "$outfile" << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="arm64"
               publicKeyToken="31bf3856ad364e35" language="neutral"
               versionScope="nonSxS">
      <UserData>
        <AcceptEula>true</AcceptEula>
      </UserData>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="arm64"
               publicKeyToken="31bf3856ad364e35" language="neutral"
               versionScope="nonSxS">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
XMLEOF

    # Inject UserAccounts block if username provided
    if [[ -n "$username" ]]; then
        cat >> "$outfile" << USEREOF
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>${username}</Name>
            <Group>Administrators</Group>
            <Password>
              <Value></Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <AutoLogon>
        <Username>${username}</Username>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
        <Password>
          <Value></Value>
          <PlainText>true</PlainText>
        </Password>
      </AutoLogon>
USEREOF
    fi

    cat >> "$outfile" << 'XMLEOF2'
    </component>
  </settings>
</unattend>
XMLEOF2
}

# ── Usage ─────────────────────────────────────────────────────────────
usage() {
    cat << 'EOF'
Usage: utm-install-usb.sh <iso> <device> [options]
       utm-install-usb.sh --autounattend-only <output.img>

Modes:
  <iso> <device>         Build a full bootable USB from a Win11 ARM64 ISO
  --autounattend-only    Create a small image with just autounattend.xml

Options:
  --force                Skip confirmation prompt (full USB mode)
  --username=NAME        Pre-configure local admin account name in answer file
  -h, --help             Show this help
EOF
}

# ── Parse arguments ───────────────────────────────────────────────────
ISO_PATH=""
DEVICE=""
AUTOUNATTEND_ONLY=""
FORCE=false
USERNAME=""

for arg in "$@"; do
    case "$arg" in
        --autounattend-only)
            AUTOUNATTEND_ONLY="__pending__"
            ;;
        --force)
            FORCE=true
            ;;
        --username=*)
            USERNAME="${arg#--username=}"
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        -*)
            echo "ERROR: Unknown option: $arg"
            exit 1
            ;;
        *)
            if [[ "$AUTOUNATTEND_ONLY" == "__pending__" ]]; then
                AUTOUNATTEND_ONLY="$arg"
            elif [[ -z "$ISO_PATH" ]]; then
                ISO_PATH="$arg"
            elif [[ -z "$DEVICE" ]]; then
                DEVICE="$arg"
            else
                echo "ERROR: Unexpected argument: $arg"
                exit 1
            fi
            ;;
    esac
done

# ── Validate ──────────────────────────────────────────────────────────
if [[ -n "$AUTOUNATTEND_ONLY" && "$AUTOUNATTEND_ONLY" != "__pending__" ]]; then
    # Autounattend-only mode
    MODE="autounattend"
    OUTPUT="$AUTOUNATTEND_ONLY"

    if [[ -e "$OUTPUT" && "$FORCE" != true ]]; then
        echo "ERROR: Output file already exists: $OUTPUT"
        echo "  Use --force to overwrite"
        exit 1
    fi
elif [[ -n "$ISO_PATH" && -n "$DEVICE" ]]; then
    # Full USB mode
    MODE="usb"

    if [[ ! -f "$ISO_PATH" ]]; then
        echo "ERROR: ISO file not found: $ISO_PATH"
        exit 1
    fi

    if [[ ! -e "$DEVICE" ]]; then
        echo "ERROR: Device not found: $DEVICE"
        exit 1
    fi

    # Safety: refuse to format the boot disk or an internal drive
    DEVICE_INFO=$(diskutil info "$DEVICE" 2>&1) || {
        echo "ERROR: Cannot read device info for $DEVICE"
        exit 1
    }

    if echo "$DEVICE_INFO" | grep -q "Internal:.*Yes"; then
        echo "ERROR: $DEVICE appears to be an internal disk — refusing to format"
        echo "  This script only formats removable/external drives."
        exit 1
    fi

    BOOT_DISK=$(diskutil info / | grep "Part of Whole:" | awk '{print $NF}')
    if [[ "$DEVICE" == *"$BOOT_DISK"* ]]; then
        echo "ERROR: $DEVICE is the boot disk — refusing to format"
        exit 1
    fi
elif [[ "$AUTOUNATTEND_ONLY" == "__pending__" ]]; then
    echo "ERROR: --autounattend-only requires an output path"
    echo "  Usage: utm-install-usb.sh --autounattend-only <output.img>"
    exit 1
else
    echo "ERROR: Missing arguments"
    usage
    exit 1
fi

# ── Check dependencies ────────────────────────────────────────────────
if [[ "$MODE" == "usb" ]]; then
    # wimlib is only required if install.wim > 4GB, but check now so we
    # can fail early rather than after formatting the drive
    if ! command -v wimlib-imagex &> /dev/null; then
        echo "WARNING: wimlib-imagex not found (brew install wimlib)"
        echo "  If install.wim > 4GB, the script will fail."
        echo "  Continuing anyway..."
        echo ""
    fi
fi

# ── Autounattend-only mode ────────────────────────────────────────────
if [[ "$MODE" == "autounattend" ]]; then
    echo "Creating autounattend-only image: $OUTPUT"

    TMPXML=$(mktemp)
    trap 'rm -f "$TMPXML"' EXIT

    generate_xml "$USERNAME" "$TMPXML"

    # Remove existing file if --force
    rm -f "$OUTPUT"

    # Create a small FAT32 disk image
    hdiutil create -size 2m -fs MS-DOS -volname OEMDRV "$OUTPUT" -quiet

    # Mount, copy XML, detach
    MOUNT_OUT=$(hdiutil attach "$OUTPUT" -nobrowse)
    MOUNT_POINT=$(echo "$MOUNT_OUT" | sed -n 's/.*\(\/Volumes\/.*\)/\1/p' | xargs)

    cp "$TMPXML" "$MOUNT_POINT/autounattend.xml"
    hdiutil detach "$MOUNT_POINT" -quiet

    echo ""
    echo "Done! Created: $OUTPUT"
    echo ""
    echo "  Volume name:  OEMDRV"
    echo "  Contents:     autounattend.xml"
    if [[ -n "$USERNAME" ]]; then
        echo "  Username:     $USERNAME (auto-created, blank password)"
    fi
    echo ""
    echo "  Attach this image alongside a Win11 ISO in UTM."
    echo "  Windows Setup will find autounattend.xml automatically."
    exit 0
fi

# ── Full USB mode ─────────────────────────────────────────────────────
echo ""
echo "Windows 11 ARM64 Install USB"
echo "============================================================"
echo "  ISO:     $ISO_PATH"
echo "  Device:  $DEVICE"
if [[ -n "$USERNAME" ]]; then
    echo "  User:    $USERNAME (auto-created, blank password)"
fi
echo "============================================================"
echo ""

# Show device details
echo "Target device:"
diskutil list "$DEVICE" 2> /dev/null | head -5
echo ""

if [[ "$FORCE" != true ]]; then
    echo "WARNING: This will ERASE ALL DATA on $DEVICE"
    read -rp "Type YES to continue: " confirm
    if [[ "$confirm" != "YES" ]]; then
        echo "Aborted."
        exit 1
    fi
    echo ""
fi

# Cleanup handler for ISO mount
ISO_MOUNT=""
cleanup() {
    if [[ -n "$ISO_MOUNT" ]]; then
        echo "Cleaning up: detaching ISO..."
        hdiutil detach "$ISO_MOUNT" -quiet 2> /dev/null || true
    fi
    rm -f "${TMPXML:-}"
}
trap cleanup EXIT

# Generate autounattend.xml
TMPXML=$(mktemp)
generate_xml "$USERNAME" "$TMPXML"

# Step 1: Unmount and format
echo "Formatting $DEVICE as FAT32 (WIN11)..."
diskutil unmountDisk "$DEVICE"
diskutil eraseDisk FAT32 WIN11 MBRFormat "$DEVICE"
echo ""

# Step 2: Mount the ISO
echo "Mounting ISO..."
ISO_MOUNT_OUT=$(hdiutil mount -nobrowse "$ISO_PATH")
ISO_MOUNT=$(echo "$ISO_MOUNT_OUT" | tail -1 | awk -F'\t' '{print $NF}' | sed 's/^ *//')
echo "  ISO mounted at: $ISO_MOUNT"
echo ""

# Step 3: Copy files (excluding install.wim which may need splitting)
echo "Copying install files (this may take a while)..."
rsync -ah --progress --exclude 'install.wim' "$ISO_MOUNT/" /Volumes/WIN11/
echo ""

# Step 4: Handle install.wim
WIM_PATH="$ISO_MOUNT/sources/install.wim"
if [[ -f "$WIM_PATH" ]]; then
    WIM_SIZE=$(stat -f%z "$WIM_PATH")
    FOUR_GB=$((4 * 1024 * 1024 * 1024))

    if [[ "$WIM_SIZE" -le "$FOUR_GB" ]]; then
        echo "Copying install.wim ($((WIM_SIZE / 1024 / 1024))MB — fits in FAT32)..."
        cp "$WIM_PATH" /Volumes/WIN11/sources/install.wim
    else
        echo "install.wim is $((WIM_SIZE / 1024 / 1024))MB — splitting for FAT32..."
        if ! command -v wimlib-imagex &> /dev/null; then
            echo "ERROR: wimlib-imagex required to split WIM > 4GB"
            echo "  Install with: brew install wimlib"
            exit 1
        fi
        wimlib-imagex split "$WIM_PATH" /Volumes/WIN11/sources/install.swm 3800
    fi
else
    echo "WARNING: install.wim not found in ISO — the ISO may use install.esd instead"
    echo "  Copying all remaining source files..."
    # install.esd or other format — just copy everything we skipped
    if [[ -f "$ISO_MOUNT/sources/install.esd" ]]; then
        cp "$ISO_MOUNT/sources/install.esd" /Volumes/WIN11/sources/install.esd
    fi
fi
echo ""

# Step 5: Inject autounattend.xml
echo "Injecting autounattend.xml..."
cp "$TMPXML" /Volumes/WIN11/autounattend.xml

# Step 6: Unmount
echo "Unmounting..."
hdiutil detach "$ISO_MOUNT" -quiet
ISO_MOUNT="" # prevent cleanup handler from double-detaching
diskutil eject "$DEVICE"

echo ""
echo "============================================================"
echo "Install USB ready!"
echo "============================================================"
echo ""
echo "  Volume:  WIN11"
echo "  Device:  $DEVICE"
if [[ -n "$USERNAME" ]]; then
    echo "  User:    $USERNAME (auto-created during OOBE, blank password)"
fi
echo ""
echo "  Boot from this USB to install Windows 11 ARM64."
echo "  OOBE will skip Microsoft account — creates a local account."
echo "============================================================"

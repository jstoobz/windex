# windex

Windows provisioning suite. One script, unattended, walk away.

Installs and configures remote access, security hardening, and essential apps on a fresh Windows 11 ARM64 machine. Built for family tech support — plug in USB or paste a one-liner and go get coffee.

## What It Does

| Step | Script | Description |
|------|--------|-------------|
| 1 | `10-install-tailscale.bat` | Tailscale VPN for remote access |
| 2 | `20-install-tightvnc.bat` | TightVNC server (screen sharing) |
| 3 | `30-configure-firewall.bat` | Lock VNC to Tailscale subnet only |
| 4 | `40-harden-system.bat` | Disable remote desktop, guest account, etc. |
| 5 | `45-configure-power.bat` | Prevent sleep, manage Windows Update |
| 6 | `60-install-apps.bat` | Chrome, iTunes, Malwarebytes |
| 7 | `65-configure-dns.bat` | Cloudflare Family DNS (malware/phishing filtering) |
| 8 | `70-harden-chrome.bat` | Safe browsing, uBlock Origin, disable dev tools |
| 9 | `75-customize-desktop.bat` | Clean up Start menu and taskbar |
| 10 | `80-create-standard-user.bat` | Non-admin daily-use account |
| 11 | `50-configure-services.bat` | Auto-start Tailscale and VNC |
| 12 | `90-verify-setup.bat` | Verify everything is working |

## Quick Start

Pick a method. All three produce the same result.

### Method 1: USB Drive

Build a bootable USB on macOS, plug it in, double-click.

```bash
# Clone and create .env with your Tailscale auth key
git clone https://github.com/jstoobz/windex.git
cd windex
echo 'TAILSCALE_AUTHKEY="tskey-auth-YOUR-KEY-HERE"' > .env

# Build the USB (prompts for username and password)
./utm-bundle.sh /Volumes/YOUR-USB-DRIVE
```

On the target machine: plug in USB, double-click `SETUP.bat`, click Yes on admin prompt, wait ~20 minutes.

### Method 2: PowerShell One-Liner

Paste into an admin PowerShell terminal on the target machine.

```powershell
# Download, extract, and run
$env:TAILSCALE_AUTHKEY="tskey-auth-YOUR-KEY-HERE"
$env:STANDARD_USERNAME="username"
$env:STANDARD_PASSWORD="password"

Invoke-WebRequest "https://github.com/jstoobz/windex/archive/refs/heads/main.zip" -OutFile "$env:TEMP\windex.zip"
Expand-Archive "$env:TEMP\windex.zip" "$env:TEMP\windex" -Force
$src = (Get-ChildItem "$env:TEMP\windex" -Directory)[0].FullName
New-Item -ItemType Directory -Path "C:\provision\scripts\lib" -Force | Out-Null
Copy-Item "$src\scripts\*" "C:\provision\scripts\" -Recurse -Force

cmd /c "C:\provision\scripts\00-setup-master.bat --force"
```

### Method 3: Remote Provisioning

Best for helping someone non-technical from another machine.

**Step 1 — Get a remote session** using one of:

| Tool | Helper (you) | Remote (them) | Notes |
|------|-------------|---------------|-------|
| **Quick Assist** | Windows only | Start → "Quick Assist" → **Get help** | Built into Win11, requires Microsoft account on helper side |
| **Chrome Remote Desktop** | Any OS | `remotedesktop.google.com/support` → **Share this screen** | Works from Mac/Linux, needs Chrome |

**Step 2 — Run provisioning** via Method 2 (paste the PowerShell block into an admin terminal).

**Step 3 — Install OpenSSH** before disconnecting. This gives you a persistent admin channel over Tailscale so you never need remote desktop again:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

**Step 4 — Disconnect remote desktop.** From now on, SSH in over Tailscale:

```bash
ssh -F /dev/null <user>@<tailscale-ip>
```

For screen sharing, tunnel VNC through SSH (avoids NAT/relay issues):

```bash
ssh -F /dev/null -L 5900:localhost:5900 <user>@<tailscale-ip>
# Then VNC to localhost:5900
```

> **Why OpenSSH?** Remote desktop tools (Quick Assist, Chrome Remote Desktop) depend on browser sessions and can be laggy over Tailscale's DERP relay. SSH handles relay gracefully and gives you a permanent, fast admin channel. Install it while you have remote desktop access — you won't need remote desktop again.

## Prerequisites

- **Tailscale auth key** — [Generate one here](https://login.tailscale.com/admin/settings/keys) (single-use, 1-hour expiry recommended)
- **Internet connection** on the target machine
- **Windows 11 ARM64** (built for Snapdragon, works on any Win11)

## Configuration

### Tailscale Auth Key

Create a `.env` file (never committed):

```bash
TAILSCALE_AUTHKEY="tskey-auth-YOUR-KEY-HERE"
```

Or pass directly:

```bash
./utm-bundle.sh /Volumes/USB --authkey=tskey-auth-YOUR-KEY-HERE
```

### Customize What Gets Installed

Skip any step with flags:

```cmd
00-setup-master.bat --force --skip-vnc --skip-apps --skip-dns
```

All flags: `--skip-tailscale`, `--skip-vnc`, `--skip-firewall`, `--skip-hardening`, `--skip-power`, `--skip-apps`, `--skip-dns`, `--skip-chrome`, `--skip-desktop`, `--skip-user`

### Password Restrictions

Passwords **cannot contain** `!` or `%` — these are special characters in cmd.exe (`EnableDelayedExpansion` and variable expansion).

## Project Structure

```
windex/
├── scripts/                    # Windows batch scripts (the provisioning suite)
│   ├── 00-setup-master.bat     # Orchestrator — runs everything in sequence
│   ├── 10-install-tailscale.bat
│   ├── ...                     # Steps 20-90
│   ├── 99-rollback.bat         # Undo everything
│   ├── helpers.ps1             # Reusable PowerShell snippets
│   ├── setup-openssh-server.ps1
│   └── lib/
│       ├── config.bat          # All paths, URLs, and defaults
│       ├── log.bat             # Logging utility
│       └── admin.bat           # Admin privilege check
├── utm-bundle.sh               # Build a provisioning USB drive
├── utm-test.sh                 # Test suite (runs in UTM VM)
├── utm.conf                    # Shared shell config
└── docs/                       # Architecture, security, troubleshooting
```

## Testing

The suite is tested in [UTM](https://mac.getutm.app/) with a disposable Windows 11 ARM64 VM. Disk changes are discarded after each run.

```bash
# Run full test (requires UTM + Win11 VM)
./utm-test.sh --user=your-vm-user --dry-run
```

## Rollback

If something goes wrong, undo everything:

```cmd
C:\provision\scripts\99-rollback.bat
```

## License

MIT

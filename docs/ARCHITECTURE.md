# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Target Windows 11 Machine                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────┐        ┌─────────────────┐                        │
│  │                 │        │                 │                        │
│  │   Tailscale     │◄──────►│   TightVNC      │                        │
│  │   Service       │        │   Server        │                        │
│  │                 │        │   (Port 5900)   │                        │
│  └────────┬────────┘        └────────┬────────┘                        │
│           │                          │                                  │
│           │                          │                                  │
│  ┌────────▼────────┐        ┌────────▼────────┐                        │
│  │   Tailscale     │        │   Windows       │                        │
│  │   Network       │        │   Firewall      │                        │
│  │   Interface     │        │   Rules         │                        │
│  │   (100.x.x.x)   │        │                 │                        │
│  └────────┬────────┘        └─────────────────┘                        │
│           │                                                             │
└───────────┼─────────────────────────────────────────────────────────────┘
            │
            │ Tailscale Mesh VPN (Encrypted)
            │
┌───────────▼─────────────────────────────────────────────────────────────┐
│                         Remote Admin Machine                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────┐        ┌─────────────────┐                        │
│  │                 │        │                 │                        │
│  │   Tailscale     │◄──────►│   VNC Viewer    │                        │
│  │   Client        │        │                 │                        │
│  │                 │        │                 │                        │
│  └─────────────────┘        └─────────────────┘                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Component Interaction

### Data Flow

1. **VNC Connection Request**
   - VNC Viewer on admin machine connects to Tailscale IP:5900
   - Request goes through Tailscale encrypted tunnel
   - Windows Firewall checks source IP (must be 100.64.0.0/10)
   - TightVNC Server authenticates with password

2. **Remote Desktop Stream**
   - TightVNC captures screen and sends to viewer
   - All traffic encrypted by Tailscale
   - Input events sent back through same tunnel

### Network Topology

```
Internet                    Tailscale Relay
    │                            │
    │                            │
    ▼                            ▼
┌───────┐                   ┌───────┐
│ NAT/  │                   │ Coord │
│Router │                   │Server │
└───┬───┘                   └───┬───┘
    │                           │
    │      Direct P2P or        │
    │      Relayed Traffic      │
    ▼           ◄──────►        ▼
┌───────┐                   ┌───────┐
│Target │                   │Remote │
│ PC    │                   │Admin  │
│100.x.x│                   │100.y.y│
└───────┘                   └───────┘
```

Tailscale automatically:
- Establishes direct peer-to-peer connections when possible
- Falls back to encrypted relay when direct connection fails
- Handles NAT traversal automatically

## Script Execution Flow

```
00-setup-master.bat
        │
        ├──► 10-install-tailscale.bat
        │           │
        │           ├── Download installer
        │           ├── Silent install
        │           ├── Apply auth key
        │           └── Verify connection
        │
        ├──► 20-install-tightvnc.bat
        │           │
        │           ├── Generate password
        │           ├── Download installer
        │           ├── Silent install with password
        │           ├── Save credentials
        │           └── Verify service
        │
        ├──► 30-configure-firewall.bat
        │           │
        │           ├── Enable Windows Firewall
        │           ├── Create allow rule (Tailscale)
        │           ├── Create block rule (others)
        │           └── Enable logging
        │
        ├──► 40-harden-system.bat
        │           │
        │           ├── Backup registry
        │           ├── Disable Remote Assistance
        │           ├── Reduce telemetry
        │           ├── Disable unnecessary services
        │           └── Verify Windows Defender
        │
        ├──► 50-configure-services.bat
        │           │
        │           ├── Set auto-start
        │           ├── Configure recovery
        │           └── Verify running
        │
        └──► 90-verify-setup.bat
                    │
                    ├── Check Tailscale
                    ├── Check TightVNC
                    ├── Check Firewall
                    ├── Check Services
                    └── Generate report
```

## File Locations

### Installation

| Component | Location |
|-----------|----------|
| Tailscale | `C:\Program Files\Tailscale\` |
| TightVNC | `C:\Program Files\TightVNC\` |
| Setup Scripts | User-provided location |

### Runtime

| Item | Location |
|------|----------|
| Log Files | `{script_dir}\logs\setup_YYYYMMDD_HHMM.log` |
| Credentials | `{script_dir}\output\credentials.txt` |
| Verification Report | `{script_dir}\output\verification-report.txt` |
| Registry Backup | `{script_dir}\output\registry-backup\` |

### Registry

| Key | Purpose |
|-----|---------|
| `HKLM\SOFTWARE\RemoteAccessSetup` | Installation state tracking |
| Values: `TailscaleInstalled`, `TightVNCInstalled`, etc. | Idempotency markers |

## Services

| Service | Display Name | Startup | Recovery |
|---------|--------------|---------|----------|
| Tailscale | Tailscale | Automatic | Restart after 60s (3x) |
| tvnserver | TightVNC Server | Automatic | Restart after 60s (3x) |

## Ports

| Port | Protocol | Purpose | Allowed From |
|------|----------|---------|--------------|
| 5900 | TCP | VNC | 100.64.0.0/10 only |
| 41641 | UDP | Tailscale | Any (encrypted) |

## Exit Codes

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | EXIT_SUCCESS | Success |
| 1 | EXIT_CANCELLED | User cancelled |
| 2 | EXIT_PREREQ_FAILED | Prerequisites not met |
| 3 | EXIT_EXECUTION_FAILED | Execution failed |
| 4 | EXIT_VERIFICATION_FAILED | Verification failed |
| 5 | EXIT_PARTIAL_SUCCESS | Partial success |

## Dependencies

### External Downloads

| Component | Source | Type |
|-----------|--------|------|
| Tailscale | pkgs.tailscale.com | EXE (NSIS) |
| TightVNC | tightvnc.com | MSI |

### System Requirements

- Windows 11 (Windows 10 may work)
- Administrator privileges
- Internet connection (for downloads)
- PowerShell 5.1+ (included with Windows)

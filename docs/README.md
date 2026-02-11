# Remote Access Automation Suite

Automated setup of secure remote access on Windows 11 using Tailscale mesh VPN and TightVNC.

## Quick Start

### Prerequisites

1. Windows 11 computer with administrator access
2. Internet connection
3. Tailscale account and auth key

### Get Your Tailscale Auth Key

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Click "Generate auth key"
3. Copy the key (starts with `tskey-auth-`)

### Run Setup

1. Copy the `scripts` folder to the target computer (e.g., via USB)
2. Right-click `00-setup-master.bat` and select "Run as administrator"
3. Enter your auth key when prompted, or run:

```batch
00-setup-master.bat --authkey=tskey-auth-YOUR-KEY-HERE
```

### Connect Remotely

After setup completes:

1. Install Tailscale on your remote computer
2. Log into the same Tailscale account
3. Use any VNC client to connect to the Tailscale IP shown after setup

## Installation Options

### Full Installation (Default)

```batch
00-setup-master.bat --authkey=YOUR_KEY
```

### Dry Run (Preview Changes)

```batch
00-setup-master.bat --authkey=YOUR_KEY --dry-run
```

### Skip Components

```batch
:: Skip system hardening
00-setup-master.bat --authkey=YOUR_KEY --skip-hardening

:: Skip firewall configuration
00-setup-master.bat --authkey=YOUR_KEY --skip-firewall
```

### Verbose Output

```batch
00-setup-master.bat --authkey=YOUR_KEY --verbose
```

## Individual Scripts

Each component can be run separately:

| Script | Purpose |
|--------|---------|
| `10-install-tailscale.bat` | Install and configure Tailscale VPN |
| `20-install-tightvnc.bat` | Install TightVNC with secure password |
| `30-configure-firewall.bat` | Restrict VNC to Tailscale network |
| `40-harden-system.bat` | Apply security hardening |
| `50-configure-services.bat` | Configure auto-start and recovery |
| `90-verify-setup.bat` | Verify installation |
| `99-rollback.bat` | Remove all components |

## After Installation

### Credentials

VNC password is saved to: `output/credentials.txt`

**Important:** Delete this file after noting the password.

### Verification

Run verification at any time:

```batch
90-verify-setup.bat
```

### Rollback

To remove all components:

```batch
99-rollback.bat
```

## Connecting from Another Computer

1. **Install Tailscale** on your remote computer
2. **Log in** to the same Tailscale account
3. **Verify connection**: Run `tailscale status` to see connected devices
4. **Connect via VNC**:
   - Open your VNC client (TightVNC Viewer, RealVNC, etc.)
   - Enter: `TAILSCALE_IP:5900` (IP shown after setup)
   - Enter the VNC password from credentials file

## Security

- VNC is only accessible via Tailscale network (100.64.0.0/10)
- All other VNC connections are blocked by firewall
- Traffic between devices is encrypted by Tailscale
- Services restart automatically on failure

See [SECURITY.md](SECURITY.md) for details.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues.

## Files

```
mah-automated-install/
├── scripts/
│   ├── 00-setup-master.bat      # Main entry point
│   ├── 10-install-tailscale.bat
│   ├── 20-install-tightvnc.bat
│   ├── 30-configure-firewall.bat
│   ├── 40-harden-system.bat
│   ├── 50-configure-services.bat
│   ├── 90-verify-setup.bat
│   ├── 99-rollback.bat
│   └── lib/
│       ├── config.bat
│       ├── utils-logging.bat
│       ├── utils-elevation.bat
│       └── utils-network.bat
├── docs/
│   ├── README.md
│   ├── ARCHITECTURE.md
│   ├── SECURITY.md
│   └── TROUBLESHOOTING.md
├── logs/                        # Created at runtime
└── output/                      # Credentials saved here
```

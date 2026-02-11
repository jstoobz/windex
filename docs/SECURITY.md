# Security Model

## Overview

This solution provides defense-in-depth for remote access:

1. **Network Layer**: Tailscale mesh VPN with WireGuard encryption
2. **Host Layer**: Windows Firewall restricts VNC to Tailscale subnet
3. **Application Layer**: VNC password authentication
4. **System Layer**: Hardening reduces attack surface

## Threat Model

### Threats Addressed

| Threat | Mitigation |
|--------|------------|
| VNC exposed to internet | Firewall blocks non-Tailscale sources |
| VNC password interception | Traffic encrypted by Tailscale |
| Unauthorized VNC access | VNC password + Tailscale auth required |
| Brute force attacks | Rate limiting by VNC, Tailscale auth |
| Man-in-the-middle | WireGuard encryption end-to-end |
| Unauthorized network access | Tailscale requires authenticated login |

### Threats NOT Addressed

| Threat | Notes |
|--------|-------|
| Malware on target machine | AV should handle; out of scope |
| Physical access attacks | Physical security is separate |
| Tailscale account compromise | Use strong password + 2FA |
| VNC client vulnerabilities | Keep VNC viewer updated |
| USB-based attacks during deployment | Verify USB contents |

## Security Controls

### 1. Tailscale Mesh VPN

**What it does:**
- Creates encrypted WireGuard tunnels between devices
- Authenticates devices via Tailscale account
- Assigns private IPs (100.64.0.0/10 CGNAT range)

**Why it's secure:**
- WireGuard uses modern cryptography (ChaCha20, Curve25519)
- No exposed ports on public internet
- NAT traversal without port forwarding
- Device authorization via admin console

### 2. Windows Firewall Rules

**Rules created:**

```
ALLOW: TCP 5900 from 100.64.0.0/10 (Tailscale subnet)
BLOCK: TCP 5900 from all other sources
```

**Why it works:**
- Only Tailscale-connected devices get 100.x.x.x IPs
- Even if attacker knows VNC port, connection blocked at firewall
- Firewall logging enabled for audit trail

### 3. VNC Password

**Configuration:**
- 16-character randomly generated password
- Mix of letters, numbers, special characters
- Stored in `output/credentials.txt`

**Recommendations:**
- Delete credentials file after noting password
- Store password in secure password manager
- Do not reuse password

### 4. System Hardening

**Changes applied:**

| Setting | Value | Rationale |
|---------|-------|-----------|
| Remote Assistance | Disabled | Reduces attack surface |
| RemoteRegistry service | Disabled | Prevents remote registry access |
| Telemetry | Reduced | Privacy, less network exposure |
| Autoplay | Disabled | Prevents USB-based attacks |

### 5. Service Configuration

**Automatic restart on failure:**
- Ensures service availability
- 60-second delay prevents rapid restart loops
- Three restart attempts before giving up

## Credential Handling

### VNC Password

**Storage:**
- Plain text in `output/credentials.txt`
- One-time use case (USB deployment)

**Best Practices:**
1. Copy password to secure password manager
2. Delete `credentials.txt` after use
3. Shred or overwrite if on USB drive

### Tailscale Auth Key

**Types:**
- **Reusable**: Can be used on multiple devices
- **Single-use**: One device only
- **Pre-authorized**: No admin approval needed

**Recommendations:**
1. Use single-use, pre-authorized keys
2. Set expiration (24 hours recommended)
3. Don't embed in scripts long-term
4. Rotate keys regularly

## Network Security

### Tailscale Subnet

```
100.64.0.0/10 = 100.64.0.0 - 100.127.255.255
```

This is the CGNAT range allocated to Tailscale. Only devices on your Tailscale network will have IPs in this range.

### Connection Flow

```
VNC Viewer ──► Tailscale (encryption) ──► Windows Firewall ──► VNC Server
     │                                           │
     └──────────── Must be 100.x.x.x ────────────┘
```

## Audit Trail

### Log Files

Location: `logs/setup_YYYYMMDD_HHMM.log`

Contains:
- All installation steps
- Configuration changes
- Error messages
- Verification results

### Windows Firewall Logs

Location: `%SystemRoot%\System32\LogFiles\Firewall\pfirewall.log`

Contains:
- Blocked connection attempts
- Useful for detecting attacks

### Registry Markers

Location: `HKLM\SOFTWARE\RemoteAccessSetup`

Tracks:
- Installation timestamps
- Component states
- Tailscale IP assigned

## Security Recommendations

### Before Deployment

1. **Verify USB contents** - Ensure no tampering
2. **Review scripts** - Understand what will be installed
3. **Test with --dry-run** - Preview changes
4. **Prepare auth key** - Short expiration, single-use

### After Deployment

1. **Delete credentials file** - Don't leave password on disk
2. **Verify firewall rules** - Run `90-verify-setup.bat`
3. **Test connection** - Ensure VNC works over Tailscale
4. **Check Tailscale admin** - Verify device appears correctly

### Ongoing

1. **Keep systems updated** - Windows Update, Tailscale, TightVNC
2. **Monitor Tailscale admin** - Review connected devices
3. **Rotate VNC password** - If compromise suspected
4. **Review firewall logs** - Check for attack attempts

## Rollback Security

When running `99-rollback.bat`:

1. Credentials file is overwritten before deletion
2. Registry markers are removed
3. Firewall rules are deleted
4. Services are uninstalled

**Note:** Log files are preserved for troubleshooting. Manually delete if needed.

## Comparison to Alternatives

| Approach | VNC over Tailscale | VNC with Port Forward | TeamViewer/AnyDesk |
|----------|-------------------|----------------------|-------------------|
| Exposure | Tailscale network only | Public internet | Cloud service |
| Encryption | WireGuard | None/TLS | Proprietary |
| Authentication | Tailscale + VNC | VNC only | Account + device |
| Self-hosted | Yes | Yes | No |
| Firewall bypass | No | Yes (opens port) | Uses relay |

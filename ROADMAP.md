# Provisioning Suite Roadmap

## Status Key
- [ ] Not started
- [x] Implemented
- [-] Decided against / N/A

## Implemented

- [x] Tailscale VPN installation (10)
- [x] TightVNC server installation (20)
- [x] Firewall configuration — VNC locked to Tailscale subnet (30)
- [x] System hardening — disable Remote Assistance, reduce telemetry, disable autoplay (40)
- [x] Service configuration — auto-start on boot (50)
- [x] Essential apps — Chrome, iTunes, Malwarebytes via winget (60)
- [x] Chrome hardening — uBlock Origin force-install, safe browsing policies (70)
- [x] Setup verification (90)
- [x] Rollback script (99)

## High Priority

### Verification gap
`90-verify-setup.bat` only checks Tailscale, VNC, firewall, and services. Needs checks for:
- Chrome executable exists
- iTunes executable exists
- Malwarebytes executable exists
- Chrome policy registry keys are set
- uBlock Origin force-install key present

### Power and sleep settings
Laptops default to sleep after 15 min on battery. Remote access (Tailscale+VNC) requires the machine to stay awake on AC power. Use `powercfg` to:
- Prevent sleep on AC
- Set reasonable battery sleep (30 min)
- Keep WiFi alive during sleep (for wake-on-LAN scenarios)

### Windows Update active hours
Set active hours via registry so updates don't reboot during the day:
- `HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings`
- ActiveHoursStart / ActiveHoursEnd (e.g., 8am–11pm)

### Standard user account
Running as admin day-to-day is a security risk. Create a standard (non-admin) user account for daily use. Keep the admin account for provisioning/maintenance only.

### DNS-level filtering
Set DNS to a filtering provider for extra protection against malware/phishing:
- Cloudflare Family: `1.1.1.3` / `1.0.0.3` (malware + adult content blocking)
- Or OpenDNS FamilyShield: `208.67.222.123` / `208.67.220.123`
- Apply via `netsh` or registry to all network adapters

### Taskbar and Start menu cleanup
Fresh Win11 has bloatware pinned (TikTok, Spotify, Disney+, etc.):
- Remove default pins from Start menu
- Pin essential apps (Chrome, iTunes) to taskbar
- Clean up desktop shortcuts

### Desktop shortcuts
Create desktop and/or taskbar shortcuts for Chrome and iTunes so they're easy to find.

## Medium Priority

### Default browser enforcement
Chrome policy `HomepageLocation` sets homepage but doesn't make Chrome the default browser. Win11 locked down programmatic default-browser setting. Options:
- `SetDefaultBrowser` Chrome policy (may work)
- `SetUserFTA` tool
- Accept the "make default" prompt on first launch

### Fix `wmic` deprecation in config.bat
`config.bat` line 40 uses `wmic os get localdatetime` for log timestamps. `wmic` is deprecated/removed in Windows 11. Replace with PowerShell equivalent:
```
for /f "tokens=*" %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmm"') do set "DATETIME=%%I"
```

## Low Priority / Future

### BitLocker / Device Encryption
Win11 Home doesn't have BitLocker but supports Device Encryption if TPM is present. Worth verifying it's enabled.

### Backup strategy
Consider OneDrive setup, File History, or other backup approach.

### Printer setup
Auto-discovery usually works on Win11 but may need manual configuration.

## Repo Genericization
- [ ] Audit all scripts for hardcoded personal information
- [ ] Make all user-specific values configurable via `lib/config.bat`
- [ ] Add a config template or setup wizard
- [ ] Ensure shell-side test scripts are parameterized
- [ ] Add README with setup instructions

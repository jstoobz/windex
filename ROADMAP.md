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
- [x] Power and sleep settings — prevent sleep on AC, active hours for Windows Update (45)
- [x] Service configuration — auto-start on boot (50)
- [x] Essential apps — Chrome, iTunes, Malwarebytes via winget (60)
- [x] DNS-level filtering — Cloudflare Family on all adapters (65)
- [x] Chrome hardening — uBlock Origin force-install, safe browsing policies (70)
- [x] Taskbar and Start menu cleanup — remove bloatware pins, pin essential apps (75)
- [x] Standard user account creation (80)
- [x] Setup verification — checks all installed components (90)
- [x] Rollback script (99)
- [x] USB bundle script — one-click provisioning USB drive (`utm-bundle.sh`)
- [x] Test harness — disposable VM testing via UTM (`utm-test.sh`)
- [x] README with deployment methods (USB, PowerShell, Quick Assist)
- [x] `wmic` deprecation fix — replaced with PowerShell `Get-Date` in config.bat

## Repo Genericization

- [x] Audit all scripts for hardcoded personal information
- [x] Make all user-specific values configurable via `lib/config.bat`
- [x] Ensure shell-side test scripts are parameterized
- [x] Add README with setup instructions
- [ ] Add a config template or setup wizard

## Medium Priority

### Default browser enforcement
Chrome policy `HomepageLocation` sets homepage but doesn't make Chrome the default browser. Win11 locked down programmatic default-browser setting. Options:
- `SetDefaultBrowser` Chrome policy (may work)
- `SetUserFTA` tool
- Accept the "make default" prompt on first launch

## Low Priority / Future

### BitLocker / Device Encryption
Win11 Home doesn't have BitLocker but supports Device Encryption if TPM is present. Worth verifying it's enabled.

### Backup strategy
Consider OneDrive setup, File History, or other backup approach.

### Printer setup
Auto-discovery usually works on Win11 but may need manual configuration.

### PowerShell bootstrap script
Standalone `bootstrap.ps1` for `irm | iex` style provisioning from a fresh PowerShell terminal. Currently documented as inline commands in README.

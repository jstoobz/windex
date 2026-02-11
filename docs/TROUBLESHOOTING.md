# Troubleshooting Guide

## Quick Diagnostics

Run the verification script:

```batch
90-verify-setup.bat
```

This checks all components and generates a report.

## Common Issues

### Tailscale Issues

#### "Tailscale auth key not provided"

**Cause:** No auth key specified

**Solution:**
```batch
00-setup-master.bat --authkey=tskey-auth-YOUR-KEY
```

Or set environment variable:
```batch
set TAILSCALE_AUTHKEY=tskey-auth-YOUR-KEY
00-setup-master.bat
```

#### "Failed to connect to Tailscale"

**Causes:**
- Invalid or expired auth key
- Network connectivity issues
- Tailscale service not running

**Solutions:**

1. Verify auth key is valid and not expired
   - Get a new key from [Tailscale Admin](https://login.tailscale.com/admin/settings/keys)

2. Check internet connectivity:
   ```batch
   ping 8.8.8.8
   ```

3. Check Tailscale service:
   ```batch
   sc query Tailscale
   net start Tailscale
   ```

4. Check Tailscale status:
   ```batch
   "C:\Program Files\Tailscale\tailscale.exe" status
   ```

#### "Tailscale IP not assigned"

**Cause:** Connection not established

**Solutions:**

1. Wait a few seconds and retry
2. Check Tailscale logs:
   ```batch
   "C:\Program Files\Tailscale\tailscale.exe" bugreport
   ```
3. Restart Tailscale service:
   ```batch
   net stop Tailscale
   net start Tailscale
   ```

### TightVNC Issues

#### "TightVNC port not listening"

**Cause:** Service not running or misconfigured

**Solutions:**

1. Check service status:
   ```batch
   sc query tvnserver
   ```

2. Start service:
   ```batch
   net start tvnserver
   ```

3. Check if port is in use:
   ```batch
   netstat -an | findstr 5900
   ```

4. If another program uses port 5900, check for conflicting VNC installations

#### "VNC connection refused"

**Causes:**
- TightVNC not running
- Firewall blocking connection
- Wrong IP address

**Solutions:**

1. Verify TightVNC is running (see above)

2. Check firewall rules exist:
   ```batch
   netsh advfirewall firewall show rule name="VNC-Tailscale-Allow"
   ```

3. Verify you're connecting via Tailscale IP (100.x.x.x), not local IP

4. Check Tailscale IP:
   ```batch
   "C:\Program Files\Tailscale\tailscale.exe" ip
   ```

#### "VNC authentication failed"

**Cause:** Wrong password

**Solutions:**

1. Check credentials file: `output\credentials.txt`
2. If file is missing, password may need to be reset via TightVNC settings

### Firewall Issues

#### "VNC rule not found"

**Cause:** Firewall rules not created

**Solution:**
```batch
30-configure-firewall.bat
```

#### "Windows Firewall is disabled"

**Cause:** Firewall was disabled manually or by policy

**Solution:**
```batch
netsh advfirewall set allprofiles state on
```

Then re-run firewall configuration:
```batch
30-configure-firewall.bat
```

#### "Connection blocked despite being on Tailscale"

**Causes:**
- Connecting via wrong interface
- Firewall rules misconfigured

**Solutions:**

1. Verify you're connecting from Tailscale IP:
   - On the connecting machine, check: `tailscale ip`
   - Ensure traffic routes through Tailscale

2. Check firewall rule details:
   ```batch
   netsh advfirewall firewall show rule name="VNC-Tailscale-Allow" verbose
   ```

3. Temporarily test with rule disabled (for diagnosis only):
   ```batch
   netsh advfirewall firewall set rule name="VNC-Block-All" new enable=no
   :: Test connection
   netsh advfirewall firewall set rule name="VNC-Block-All" new enable=yes
   ```

### Service Issues

#### "Service won't start"

**Causes:**
- Dependency service not running
- Service account issues
- Corrupted installation

**Solutions:**

1. Check service dependencies:
   ```batch
   sc qc tvnserver
   sc qc Tailscale
   ```

2. Check Windows Event Viewer for errors:
   - Open Event Viewer
   - Check Windows Logs > System
   - Look for errors from the service

3. Reinstall the problematic component:
   ```batch
   :: For TightVNC
   99-rollback.bat
   20-install-tightvnc.bat
   ```

#### "Service not set to auto-start"

**Cause:** Service configuration not applied

**Solution:**
```batch
50-configure-services.bat
```

Or manually:
```batch
sc config Tailscale start= auto
sc config tvnserver start= auto
```

### Installation Issues

#### "Download failed"

**Causes:**
- No internet connection
- URL changed
- Network restrictions

**Solutions:**

1. Test internet:
   ```batch
   ping google.com
   ```

2. Try manual download:
   - Tailscale: https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe
   - TightVNC: https://www.tightvnc.com/download.php

3. Check if corporate firewall blocks downloads

4. Update URLs in `lib\config.bat` if they've changed

#### "Access denied" or "Administrator required"

**Cause:** Script not running as administrator

**Solution:**
1. Right-click the batch file
2. Select "Run as administrator"

Or from elevated command prompt:
```batch
00-setup-master.bat --authkey=YOUR_KEY
```

#### "Script stops unexpectedly"

**Causes:**
- Critical error encountered
- `CONTINUE_ON_ERROR` not set

**Solutions:**

1. Check log file for last error: `logs\setup_*.log`

2. Run with continue-on-error:
   ```batch
   00-setup-master.bat --authkey=YOUR_KEY --continue-on-error
   ```

3. Run individual scripts to isolate the issue

## Diagnostic Commands

### Check All Components

```batch
:: Tailscale
"C:\Program Files\Tailscale\tailscale.exe" status
"C:\Program Files\Tailscale\tailscale.exe" ip

:: TightVNC
sc query tvnserver
netstat -an | findstr 5900

:: Firewall
netsh advfirewall show allprofiles state
netsh advfirewall firewall show rule name="VNC-Tailscale-Allow"
netsh advfirewall firewall show rule name="VNC-Block-All"

:: Services
sc qc Tailscale
sc qc tvnserver
```

### View Logs

```batch
:: Setup log (latest)
dir /b /o-d logs\*.log | head -1
type logs\setup_*.log

:: Windows Firewall log
type %SystemRoot%\System32\LogFiles\Firewall\pfirewall.log
```

### Reset and Retry

```batch
:: Full reset
99-rollback.bat --force

:: Fresh install
00-setup-master.bat --authkey=YOUR_KEY
```

## Log File Locations

| Log | Location |
|-----|----------|
| Setup log | `logs\setup_YYYYMMDD_HHMM.log` |
| Firewall log | `%SystemRoot%\System32\LogFiles\Firewall\pfirewall.log` |
| Tailscale log | Windows Event Viewer > Applications |
| TightVNC log | Windows Event Viewer > Applications |

## Exit Codes Reference

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | None needed |
| 1 | User cancelled | Re-run if needed |
| 2 | Prerequisites not met | Check requirements |
| 3 | Execution failed | Check logs |
| 4 | Verification failed | Run verification for details |
| 5 | Partial success | Some components may need attention |

## Getting Help

1. **Check this guide** for your specific error
2. **Review log files** for detailed error messages
3. **Run verification** to identify which component failed
4. **Try dry-run mode** to preview what would happen
5. **Run individual scripts** to isolate the issue

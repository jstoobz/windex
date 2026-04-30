#Requires -RunAsAdministrator
<#
  bootstrap-remote.ps1 — One-shot script to establish remote access.

  Installs Tailscale + TigerVNC, connects to tailnet, opens firewall.
  Designed to be run once by someone with physical access to the machine.

  Usage:
    $env:TS_AUTHKEY='tskey-auth-...'; irm <url> | iex
    # or
    .\bootstrap-remote.ps1 -TailscaleAuthKey 'tskey-auth-...'
#>
param(
    [string]$TailscaleAuthKey = $env:TS_AUTHKEY,
    [string]$VncPassword = $env:VNC_PASSWORD,
    [string]$StandardUsername = $env:STANDARD_USERNAME
)

$ErrorActionPreference = 'Stop'

# ── Config (from env with defaults — matches lib/config.bat) ────────
$TailscaleUrl      = if ($env:TAILSCALE_URL)      { $env:TAILSCALE_URL }      else { 'https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe' }
$TailscaleDir      = if ($env:TAILSCALE_DIR)       { $env:TAILSCALE_DIR }      else { 'C:\Program Files\Tailscale' }
$TailscaleExe      = "$TailscaleDir\tailscale.exe"
$VncDir            = if ($env:VNC_DIR)              { $env:VNC_DIR }            else { 'C:\Program Files\TigerVNC' }
$VncService        = if ($env:VNC_SERVICE)          { $env:VNC_SERVICE }        else { 'winvnc4' }
$VncPort           = if ($env:VNC_PORT)             { [int]$env:VNC_PORT }      else { 5900 }
$TailscaleSubnet   = if ($env:TAILSCALE_SUBNET)    { $env:TAILSCALE_SUBNET }   else { '100.64.0.0/10' }
$VncPasswordLength = if ($env:VNC_PASSWORD_LENGTH)  { [int]$env:VNC_PASSWORD_LENGTH } else { 16 }
$FwRuleVncAllow    = if ($env:FW_RULE_VNC_ALLOW)   { $env:FW_RULE_VNC_ALLOW }  else { 'VNC-Tailscale-Allow' }
$FwRuleVncBlock    = if ($env:FW_RULE_VNC_BLOCK)   { $env:FW_RULE_VNC_BLOCK }  else { 'VNC-Block-All' }
$FwRuleSshAllow    = if ($env:FW_RULE_SSH_ALLOW)   { $env:FW_RULE_SSH_ALLOW }  else { 'SSH-Tailscale-Allow' }

# ── Helpers ──────────────────────────────────────────────────────────
function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "   OK: $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "   WARN: $msg" -ForegroundColor Yellow }

function Wait-ForCondition {
    param([scriptblock]$Condition, [string]$Description, [int]$TimeoutSec = 90)
    $elapsed = 0
    while (-not (& $Condition)) {
        Start-Sleep -Seconds 3
        $elapsed += 3
        if ($elapsed -ge $TimeoutSec) {
            throw "Timeout waiting for: $Description"
        }
    }
}

# ── Validate ─────────────────────────────────────────────────────────
if (-not $TailscaleAuthKey) {
    Write-Host @"

  ERROR: Tailscale auth key required.

  Get one from: https://login.tailscale.com/admin/settings/keys
  Then run:
    `$env:TS_AUTHKEY='tskey-auth-...'; .\bootstrap-remote.ps1

"@ -ForegroundColor Red
    exit 1
}

# Generate VNC password if not provided
if (-not $VncPassword) {
    $chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789~_-+.'
    $VncPassword = -join ((1..$VncPasswordLength) | ForEach-Object {
        $chars[(Get-Random -Maximum $chars.Length)]
    })
}

Write-Host ""
Write-Host "======================================" -ForegroundColor White
Write-Host " Bootstrap Remote Access" -ForegroundColor White
Write-Host "======================================" -ForegroundColor White

# ── 1. Tailscale ─────────────────────────────────────────────────────
Write-Step "Installing Tailscale..."

$tsInstalled = Test-Path $TailscaleExe
if ($tsInstalled) {
    Write-Ok "Tailscale already installed"
} else {
    $installer = "$env:TEMP\tailscale-setup.exe"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $TailscaleUrl -OutFile $installer -UseBasicParsing
    Write-Ok "Downloaded installer"

    Start-Process -FilePath $installer -ArgumentList '/S' -Wait
    Wait-ForCondition { Test-Path $TailscaleExe } "Tailscale executable"
    Remove-Item $installer -ErrorAction SilentlyContinue
    Write-Ok "Tailscale installed"
}

Write-Step "Connecting to Tailscale..."

Wait-ForCondition {
    (Get-Service Tailscale -ErrorAction SilentlyContinue).Status -eq 'Running'
} "Tailscale service"
Write-Ok "Service running"

& $TailscaleExe set --unattended 2>$null
& $TailscaleExe up --authkey=$TailscaleAuthKey --unattended --timeout=60s
if ($LASTEXITCODE -ne 0) {
    throw "Tailscale authentication failed — check your auth key"
}

Start-Sleep -Seconds 3
$tsIp = & $TailscaleExe ip -4 2>$null
if (-not $tsIp) {
    Write-Warn "Could not retrieve Tailscale IP — check admin console"
} else {
    Write-Ok "Connected: $tsIp"
}

# ── 2. VNC Server (TigerVNC) ─────────────────────────────────────────
Write-Step "Installing TigerVNC..."

$vncInstalled = Test-Path "$VncDir\winvnc4.exe"
if ($vncInstalled) {
    Write-Ok "TigerVNC already installed"
} else {
    winget install TigerVNC.TigerVNC --silent --accept-package-agreements --accept-source-agreements | Out-Null
    Wait-ForCondition { Test-Path "$VncDir\winvnc4.exe" } "TigerVNC executable"
    Write-Ok "TigerVNC installed"
}

# Configure VNC password (DES encryption per RFB protocol)
$pwBytes = [byte[]]::new(8)
$rawPw = [Text.Encoding]::ASCII.GetBytes($VncPassword)
[Array]::Copy($rawPw, $pwBytes, [Math]::Min($rawPw.Length, 8))
$desKey = [byte[]](0xE8,0x4A,0xD6,0x60,0xC4,0x72,0x1A,0xE0)
$des = [Security.Cryptography.DES]::Create()
$des.Mode = 'ECB'; $des.Padding = 'None'; $des.Key = $desKey
$encrypted = $des.CreateEncryptor().TransformFinalBlock($pwBytes, 0, 8)
$hexPw = -join ($encrypted | ForEach-Object { '{0:x2}' -f $_ })

reg add 'HKLM\SOFTWARE\TigerVNC\Server' /v Password /t REG_BINARY /d $hexPw /f | Out-Null
reg add 'HKLM\SOFTWARE\TigerVNC\Server' /v ControlPassword /t REG_BINARY /d $hexPw /f | Out-Null
reg add 'HKLM\SOFTWARE\TigerVNC\Server' /v SecurityTypes /t REG_SZ /d 'VncAuth' /f | Out-Null
reg add 'HKLM\SOFTWARE\TigerVNC\Server' /v PortNumber /t REG_DWORD /d $VncPort /f | Out-Null
reg add 'HKLM\SOFTWARE\TigerVNC\Server' /v AllowLoopback /t REG_DWORD /d 1 /f | Out-Null

# Ensure service is registered and running
if (-not (Get-Service $VncService -ErrorAction SilentlyContinue)) {
    & "$VncDir\winvnc4.exe" -register
}
Wait-ForCondition {
    (Get-Service $VncService -ErrorAction SilentlyContinue) -ne $null
} "VNC service registration"

Restart-Service $VncService -ErrorAction SilentlyContinue
Wait-ForCondition {
    (Get-Service $VncService).Status -eq 'Running'
} "VNC service running"
Write-Ok "VNC server running on port $VncPort"

# ── 3. Firewall ──────────────────────────────────────────────────────
Write-Step "Configuring firewall..."

# Remove stale VNC rules
foreach ($name in @($FwRuleVncAllow, $FwRuleVncBlock)) {
    Remove-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
}

# Allow VNC only from Tailscale subnet
New-NetFirewallRule -Name $FwRuleVncAllow -DisplayName $FwRuleVncAllow `
    -Direction Inbound -Protocol TCP -LocalPort $VncPort `
    -RemoteAddress $TailscaleSubnet -Action Allow -Profile Any | Out-Null

# Block VNC from everywhere else
New-NetFirewallRule -Name $FwRuleVncBlock -DisplayName $FwRuleVncBlock `
    -Direction Inbound -Protocol TCP -LocalPort $VncPort `
    -Action Block -Profile Any | Out-Null

# Restrict SSH to Tailscale subnet (not left wide open)
$sshdRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($sshdRule) {
    Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile Any -RemoteAddress $TailscaleSubnet
    Write-Ok "SSH firewall rule restricted to Tailscale subnet"
}

Write-Ok "VNC allowed from Tailscale only ($TailscaleSubnet)"

# ── 4. Profile cleanup ──────────────────────────────────────────────
Write-Step "Checking for orphaned user profiles..."

$orphaned = $null
if ($StandardUsername) {
    $orphaned = Get-CimInstance Win32_UserProfile |
        Where-Object { $_.LocalPath -eq "C:\Users\$StandardUsername" -or $_.LocalPath -like "C:\Users\$StandardUsername.*" } |
        Where-Object { -not (Get-LocalUser -SID $_.SID -ErrorAction SilentlyContinue) }

    if ($orphaned) {
        $count = @($orphaned).Count
        Write-Warn "Found $count orphaned $StandardUsername profile(s) — removing..."
        $orphaned | Remove-CimInstance
        Write-Ok "Removed $count orphaned profile(s) — reboot to clear lock screen tiles"
    } else {
        Write-Ok "No orphaned profiles found"
    }
} else {
    Write-Ok "No standard username set — skipping profile cleanup"
}

# ── Done ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host " Remote Access Ready" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Tailscale IP:   $tsIp"
Write-Host "  VNC Port:       $VncPort"
Write-Host "  VNC Password:   $VncPassword"
Write-Host ""
Write-Host "  Connect from Mac:" -ForegroundColor White
Write-Host "    open vnc://${tsIp}:${VncPort}"
Write-Host ""
if ($orphaned) {
    Write-Host "  ** Reboot needed to clear duplicate lock screen tiles **" -ForegroundColor Yellow
    Write-Host ""
}
Write-Host "  SAVE THE VNC PASSWORD — it won't be shown again." -ForegroundColor Yellow
Write-Host ""

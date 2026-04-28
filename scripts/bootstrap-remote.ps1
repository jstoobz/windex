#Requires -RunAsAdministrator
<#
  bootstrap-remote.ps1 — One-shot script to establish remote access.

  Installs Tailscale + TightVNC, connects to tailnet, opens firewall.
  Designed to be run once by someone with physical access to the machine.

  Usage:
    $env:TS_AUTHKEY='tskey-auth-...'; irm <url> | iex
    # or
    .\bootstrap-remote.ps1 -TailscaleAuthKey 'tskey-auth-...'
#>
param(
    [string]$TailscaleAuthKey = $env:TS_AUTHKEY,
    [string]$VncPassword = $env:VNC_PASSWORD
)

$ErrorActionPreference = 'Stop'

# ── Config ───────────────────────────────────────────────────────────
$TailscaleUrl     = 'https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe'
$TailscaleExe     = 'C:\Program Files\Tailscale\tailscale.exe'
$TightVncUrl      = 'https://www.tightvnc.com/download/2.8.85/tightvnc-2.8.85-gpl-setup-64bit.msi'
$TightVncDir      = 'C:\Program Files\TightVNC'
$TightVncService  = 'tvnserver'
$VncPort          = 5900
$TailscaleSubnet  = '100.64.0.0/10'
$VncPasswordLength = 16

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

# ── 2. TightVNC ──────────────────────────────────────────────────────
Write-Step "Installing TightVNC..."

$vncInstalled = Test-Path "$TightVncDir\tvnserver.exe"
if ($vncInstalled) {
    Write-Ok "TightVNC already installed"
} else {
    $msi = "$env:TEMP\tightvnc-setup.msi"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $TightVncUrl -OutFile $msi -UseBasicParsing
    Write-Ok "Downloaded installer"

    $msiArgs = @(
        '/i', $msi,
        '/quiet', '/norestart',
        'ADDLOCAL=Server',
        'SET_USEVNCAUTHENTICATION=1', 'VALUE_OF_USEVNCAUTHENTICATION=1',
        "SET_PASSWORD=1", "VALUE_OF_PASSWORD=$VncPassword",
        "SET_USECONTROLAUTHENTICATION=1", "VALUE_OF_CONTROLPASSWORD=$VncPassword",
        'SET_ALLOWLOOPBACK=1', 'VALUE_OF_ALLOWLOOPBACK=1'
    )
    Start-Process msiexec -ArgumentList $msiArgs -Wait
    Wait-ForCondition {
        (Get-Service $TightVncService -ErrorAction SilentlyContinue) -ne $null
    } "TightVNC service registration"
    Remove-Item $msi -ErrorAction SilentlyContinue
    Write-Ok "TightVNC installed"
}

# Ensure service is running
$vncSvc = Get-Service $TightVncService -ErrorAction SilentlyContinue
if ($vncSvc -and $vncSvc.Status -ne 'Running') {
    Start-Service $TightVncService
}
Wait-ForCondition {
    (Get-Service $TightVncService).Status -eq 'Running'
} "TightVNC service running"
Write-Ok "VNC server running on port $VncPort"

# ── 3. Firewall ──────────────────────────────────────────────────────
Write-Step "Configuring firewall..."

# Remove stale rules
foreach ($name in @('VNC-Tailscale-Allow', 'VNC-Block-All')) {
    Remove-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
}

# Allow VNC only from Tailscale subnet
New-NetFirewallRule -DisplayName 'VNC-Tailscale-Allow' `
    -Direction Inbound -Protocol TCP -LocalPort $VncPort `
    -RemoteAddress $TailscaleSubnet -Action Allow -Profile Any | Out-Null

# Block VNC from everywhere else
New-NetFirewallRule -DisplayName 'VNC-Block-All' `
    -Direction Inbound -Protocol TCP -LocalPort $VncPort `
    -Action Block -Profile Any | Out-Null

# Fix OpenSSH rule if sshd exists (allow all profiles)
$sshdRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($sshdRule) {
    Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile Any
    Write-Ok "SSH firewall rule updated to all profiles"
}

Write-Ok "VNC allowed from Tailscale only ($TailscaleSubnet)"

# ── 4. Profile cleanup ──────────────────────────────────────────────
Write-Step "Checking for orphaned user profiles..."

$orphaned = Get-CimInstance Win32_UserProfile |
    Where-Object { $_.LocalPath -like 'C:\Users\User*' } |
    Where-Object { -not (Get-LocalUser -SID $_.SID -ErrorAction SilentlyContinue) }

if ($orphaned) {
    $count = @($orphaned).Count
    Write-Warn "Found $count orphaned User profile(s) — removing..."
    $orphaned | Remove-CimInstance
    Write-Ok "Removed $count orphaned profile(s) — reboot to clear lock screen tiles"
} else {
    Write-Ok "No orphaned profiles found"
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

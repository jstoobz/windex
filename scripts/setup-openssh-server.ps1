# setup-openssh-server.ps1 — Run this in the VM through UTM GUI (as Administrator)
#
# Sets up OpenSSH Server with key-based auth for automated access.
# After this, the golden image supports SSH from the host via:
#   ssh -i ~/.ssh/utm_vm -p 2222 <user>@localhost
#
# Run in an elevated PowerShell: Right-click PowerShell → Run as Administrator

$ErrorActionPreference = "Stop"

Write-Host "`n=== OpenSSH Server Setup ===" -ForegroundColor Cyan

# Step 1: Check if OpenSSH Server is already installed
$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

if ($sshCapability.State -eq 'Installed') {
    Write-Host "[OK] OpenSSH Server already installed" -ForegroundColor Green
} else {
    Write-Host "[....] Installing OpenSSH Server (requires internet)..."
    try {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        Write-Host "[OK] OpenSSH Server installed" -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] Installation failed: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "If you see 0x800f0954, the VM may not have internet access."
        Write-Host "Check: ping 8.8.8.8"
        Write-Host ""
        exit 1
    }
}

# Step 2: Start and enable sshd
Write-Host "[....] Configuring sshd service..."
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
Write-Host "[OK] sshd started and set to auto-start" -ForegroundColor Green

# Step 3: Verify firewall rule exists and allow all profiles
# Windows auto-creates a rule on install but restricts it to Private profile.
# QEMU SLIRP network is classified as Public, so SSH would be blocked.
$fwRule = Get-NetFirewallRule -Name *ssh* -ErrorAction SilentlyContinue
if ($fwRule) {
    Set-NetFirewallRule -Name $fwRule.Name -Profile Any
    Write-Host "[OK] Firewall rule exists: $($fwRule.Name) (set to all profiles)" -ForegroundColor Green
} else {
    Write-Host "[....] Creating firewall rule for SSH..."
    New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any
    Write-Host "[OK] Firewall rule created (all profiles)" -ForegroundColor Green
}

# Step 4: Set up key-based auth
$pubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK+ANVl7429UPEOO7C6y1a9Hn4Ycu05yoSVbRL6WgYbO utm-vm-automation"

# For admin users, Windows uses administrators_authorized_keys
$adminKeyFile = "C:\ProgramData\ssh\administrators_authorized_keys"
$userKeyFile = "$env:USERPROFILE\.ssh\authorized_keys"

# Ensure .ssh directory exists for current user
$sshDir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

# Add key to user's authorized_keys
if (Test-Path $userKeyFile) {
    $existing = Get-Content $userKeyFile -Raw
    if ($existing -match "utm-vm-automation") {
        Write-Host "[OK] Key already in $userKeyFile" -ForegroundColor Green
    } else {
        Add-Content -Path $userKeyFile -Value $pubKey
        Write-Host "[OK] Key added to $userKeyFile" -ForegroundColor Green
    }
} else {
    Set-Content -Path $userKeyFile -Value $pubKey
    Write-Host "[OK] Created $userKeyFile with key" -ForegroundColor Green
}

# Also add to administrators_authorized_keys (needed if user is admin)
$sshProgramData = "C:\ProgramData\ssh"
if (-not (Test-Path $sshProgramData)) {
    New-Item -ItemType Directory -Path $sshProgramData -Force | Out-Null
}

if (Test-Path $adminKeyFile) {
    $existing = Get-Content $adminKeyFile -Raw
    if ($existing -match "utm-vm-automation") {
        Write-Host "[OK] Key already in $adminKeyFile" -ForegroundColor Green
    } else {
        Add-Content -Path $adminKeyFile -Value $pubKey
        Write-Host "[OK] Key added to $adminKeyFile" -ForegroundColor Green
    }
} else {
    Set-Content -Path $adminKeyFile -Value $pubKey
    Write-Host "[OK] Created $adminKeyFile with key" -ForegroundColor Green
}

# Fix permissions on administrators_authorized_keys (Windows OpenSSH is picky)
$acl = Get-Acl $adminKeyFile
$acl.SetAccessRuleProtection($true, $false)
$adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Administrators", "FullControl", "Allow")
$systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "SYSTEM", "FullControl", "Allow")
$acl.SetAccessRule($adminRule)
$acl.SetAccessRule($systemRule)
Set-Acl -Path $adminKeyFile -AclObject $acl
Write-Host "[OK] Fixed permissions on $adminKeyFile" -ForegroundColor Green

# Step 5: Configure sshd for key auth (and optionally disable password auth)
$sshdConfig = "C:\ProgramData\ssh\sshd_config"
if (Test-Path $sshdConfig) {
    $config = Get-Content $sshdConfig -Raw

    # Ensure PubkeyAuthentication is enabled
    if ($config -match "^#?PubkeyAuthentication") {
        $config = $config -replace "^#?PubkeyAuthentication.*", "PubkeyAuthentication yes"
    }

    Set-Content -Path $sshdConfig -Value $config
    Write-Host "[OK] sshd_config updated" -ForegroundColor Green
}

# Restart sshd to pick up config changes
Restart-Service sshd
Write-Host "[OK] sshd restarted" -ForegroundColor Green

# Step 6: Verify
Write-Host "`n=== Verification ===" -ForegroundColor Cyan
$service = Get-Service sshd
Write-Host "  sshd status: $($service.Status)"
Write-Host "  sshd startup: $($service.StartType)"

$listener = Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    Write-Host "  Listening on port 22: YES" -ForegroundColor Green
} else {
    Write-Host "  Listening on port 22: NO" -ForegroundColor Red
}

Write-Host "`n  Username: $env:USERNAME"
Write-Host "  From Mac, connect with:"
Write-Host "    ssh -i ~/.ssh/utm_vm -p 2222 $env:USERNAME@localhost" -ForegroundColor Yellow

Write-Host "`n=== Done ===" -ForegroundColor Cyan
Write-Host ""

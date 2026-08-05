<#
  discover-machine.ps1 - Read-only inventory of everything windex touches.

  Run before a provisioning session to see what is already configured, and
  again afterward: the diff of the two reports is the receipt for the visit.
  Makes no changes. Secrets are reported as present/absent, never printed.

  Usage:
    .\discover-machine.ps1                      # writes .\windex-discovery-<host>-<stamp>.txt
    .\discover-machine.ps1 -OutFile C:\before.txt
#>
param(
    [string]$OutFile
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

if (-not $OutFile) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $OutFile = Join-Path (Get-Location) "windex-discovery-$env:COMPUTERNAME-$stamp.txt"
}

$lines = [Collections.Generic.List[string]]::new()
function Add-Line { param([string]$Text = '') $lines.Add($Text) }
function Add-Section { param([string]$Title) Add-Line; Add-Line ('=' * 70); Add-Line $Title; Add-Line ('=' * 70) }
function Add-Item {
    param([string]$Label, $Value)
    $text = if ($null -eq $Value -or "$Value" -eq '') { '(none)' } else { "$Value" }
    Add-Line ("  {0,-34} {1}" -f "$Label :", $text)
}
function Test-RegValue {
    param([string]$Path, [string]$Name)
    $v = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($v) { $v.$Name } else { $null }
}

Add-Line "windex machine discovery"
Add-Line "Host: $env:COMPUTERNAME    Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add-Line "Run as: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

# == Operating system =================================================
Add-Section 'OPERATING SYSTEM'
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
Add-Item 'Caption' $os.Caption
Add-Item 'Version / Build' "$($os.Version) ($((Test-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'DisplayVersion')))"
Add-Item 'Architecture' $env:PROCESSOR_ARCHITECTURE
Add-Item 'Model' "$($cs.Manufacturer) $($cs.Model)"
Add-Item 'Installed' $os.InstallDate
Add-Item 'Last boot' $os.LastBootUpTime
$sysDrive = Get-PSDrive C -ErrorAction SilentlyContinue
if ($sysDrive) { Add-Item 'C: free' ("{0:N1} GB of {1:N1} GB" -f ($sysDrive.Free/1GB), (($sysDrive.Free + $sysDrive.Used)/1GB)) }

# == Reboot pending ===================================================
Add-Section 'PENDING REBOOT'
$rebootReasons = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $rebootReasons += 'CBS RebootPending' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $rebootReasons += 'WindowsUpdate RebootRequired' }
if (Test-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations') { $rebootReasons += 'PendingFileRenameOperations' }
Add-Item 'Reboot pending' $(if ($rebootReasons) { $rebootReasons -join '; ' } else { 'no' })

# == windex provisioning markers ======================================
Add-Section 'WINDEX MARKERS (HKLM\SOFTWARE\RemoteAccessSetup)'
$markerKey = 'HKLM:\SOFTWARE\RemoteAccessSetup'
if (Test-Path $markerKey) {
    $props = Get-ItemProperty $markerKey
    $props.PSObject.Properties |
        Where-Object { $_.Name -notlike 'PS*' } |
        Sort-Object Name |
        ForEach-Object { Add-Item $_.Name $_.Value }
} else {
    Add-Item 'Key' 'absent - no windex run has completed on this machine'
}

# == Auto-logon (duplicate lock-screen tile bug) ======================
Add-Section 'AUTO-LOGON (dup lock-screen tile root cause)'
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Add-Item 'AutoAdminLogon' (Test-RegValue $winlogon 'AutoAdminLogon')
Add-Item 'DefaultUserName' (Test-RegValue $winlogon 'DefaultUserName')
Add-Item 'DefaultPassword' $(if (Test-RegValue $winlogon 'DefaultPassword') { 'PRESENT - scrub this' } else { 'absent' })
Add-Item 'DefaultDomainName' (Test-RegValue $winlogon 'DefaultDomainName')

# == Accounts and profiles ============================================
Add-Section 'LOCAL ACCOUNTS'
Get-LocalUser | Sort-Object Name | ForEach-Object {
    Add-Item $_.Name "enabled=$($_.Enabled)  lastlogon=$(if ($_.LastLogon) { $_.LastLogon.ToString('yyyy-MM-dd') } else { 'never' })"
}
Add-Line
Add-Line '  Administrators group:'
Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
    ForEach-Object { Add-Line "    - $($_.Name) [$($_.ObjectClass)]" }

Add-Section 'USER PROFILES (orphan = profile with no matching account)'
Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special } | ForEach-Object {
    $account = Get-LocalUser -SID $_.SID -ErrorAction SilentlyContinue
    $state = if ($account) { "account: $($account.Name)" } else { 'ORPHANED - no matching account' }
    Add-Item (Split-Path $_.LocalPath -Leaf) "$state  [$($_.LocalPath)]"
}

# == Remote access ====================================================
Add-Section 'TAILSCALE'
$tsExe = 'C:\Program Files\Tailscale\tailscale.exe'
if (Test-Path $tsExe) {
    Add-Item 'Installed' $tsExe
    Add-Item 'Version' ((& $tsExe version 2>$null) | Select-Object -First 1)
    Add-Item 'IPv4' ((& $tsExe ip -4 2>$null) | Select-Object -First 1)
    $svc = Get-Service Tailscale -ErrorAction SilentlyContinue
    Add-Item 'Service' $(if ($svc) { "$($svc.Status) / $($svc.StartType)" } else { 'not registered' })
    $status = (& $tsExe status 2>&1) -join "`n"
    Add-Item 'Awaiting approval' $(if ($status -match 'not yet approved|awaiting approval|To approve') { 'YES - data plane blocked' } else { 'no' })
    Add-Item 'Unattended mode' $(if ((& $tsExe debug prefs 2>$null) -join '' -match '"ForceDaemon"\s*:\s*true') { 'on' } else { 'OFF - daemon drops on logout' })
} else {
    Add-Item 'Installed' 'no'
}

Add-Section 'VNC SERVER'
$vncDir = 'C:\Program Files\TigerVNC server'
Add-Item 'TigerVNC server dir' $(if (Test-Path $vncDir) { $vncDir } else { 'absent' })
$vncSvc = Get-Service TigerVNC -ErrorAction SilentlyContinue
Add-Item 'Service' $(if ($vncSvc) { "$($vncSvc.Status) / $($vncSvc.StartType)" } else { 'not registered' })
Add-Item 'Password configured' $(if (Test-RegValue 'HKLM:\SOFTWARE\TigerVNC\WinVNC4' 'Password') { 'yes' } else { 'no' })
Add-Item 'Port 5900 listening' $(if (Get-NetTCPConnection -LocalPort 5900 -State Listen -ErrorAction SilentlyContinue) { 'yes' } else { 'no' })

Add-Section 'OPENSSH SERVER'
$sshCap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue
Add-Item 'Capability' $(if ($sshCap) { $sshCap.State } else { 'query failed' })
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
Add-Item 'sshd service' $(if ($sshd) { "$($sshd.Status) / $($sshd.StartType)" } else { 'not registered' })
Add-Item 'Port 22 listening' $(if (Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue) { 'yes' } else { 'no' })
Add-Item 'administrators_authorized_keys' $(if (Test-Path 'C:\ProgramData\ssh\administrators_authorized_keys') { 'present' } else { 'absent' })

Add-Section 'OTHER REMOTE-ACCESS TOOLS'
foreach ($tool in @(
    @{ Name = 'AnyDesk';      Path = 'C:\Program Files (x86)\AnyDesk\AnyDesk.exe' },
    @{ Name = 'AnyDesk (x64)';Path = 'C:\Program Files\AnyDesk\AnyDesk.exe' },
    @{ Name = 'TeamViewer';   Path = 'C:\Program Files\TeamViewer\TeamViewer.exe' },
    @{ Name = 'Quick Assist'; Path = "$env:LOCALAPPDATA\Microsoft\WindowsApps\quickassist.exe" }
)) { Add-Item $tool.Name $(if (Test-Path $tool.Path) { 'INSTALLED' } else { 'absent' }) }
Add-Item 'Remote Desktop (fDenyTSConnections)' (Test-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections')

# == Firewall =========================================================
Add-Section 'FIREWALL'
Get-NetFirewallProfile | ForEach-Object {
    $effective = if ($_.DefaultInboundAction -eq 'NotConfigured') { 'Block (Windows default)' } else { $_.DefaultInboundAction }
    Add-Item $_.Name "enabled=$($_.Enabled)  inbound=$effective"
}
Add-Line '  NB: inbound is default-deny, so a scoped allow rule needs no companion'
Add-Line '      block rule - and a catch-all block would out-prioritize the allow.'
Add-Line
Add-Line '  Rules on the VNC and SSH ports:'
foreach ($port in @(5900, 22)) {
    $rules = Get-NetFirewallPortFilter |
        Where-Object { $_.LocalPort -eq $port } |
        Get-NetFirewallRule |
        Where-Object Enabled -eq $true
    if (-not $rules) { Add-Line "    port ${port}: (no enabled rules)"; continue }
    foreach ($rule in $rules) {
        $scope = ($rule | Get-NetFirewallAddressFilter).RemoteAddress -join ','
        Add-Line "    port ${port}: $($rule.Name) [$($rule.Action)] from $scope"
    }
}

# == Debloat surface ==================================================
Add-Section 'APPX PACKAGES (windex debloat targets still present)'
$targets = @(
    'Microsoft.BingNews', 'Microsoft.BingSearch', 'Microsoft.BingWeather', 'Clipchamp.Clipchamp',
    'Microsoft.Copilot', 'Microsoft.GetHelp', 'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.MicrosoftStickyNotes', 'Microsoft.OutlookForWindows', 'MicrosoftCorporationII.MicrosoftFamily',
    'MSTeams', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub', 'Microsoft.Xbox.TCUI',
    'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.YourPhone', 'Microsoft.ZuneMusic'
)
$found = 0
foreach ($target in $targets) {
    $pkg = Get-AppxPackage -Name $target -AllUsers -ErrorAction SilentlyContinue
    if ($pkg) {
        $found++
        $installedFor = @($pkg.PackageUserInformation | Where-Object { $_.InstallState -eq 'Installed' }).Count
        $state = if ($installedFor -gt 0) { "installed for $installedFor user(s)" } else { 'staged only (invisible to users)' }
        Add-Item $target $state
    }
}
if ($found -eq 0) { Add-Item 'Debloat targets remaining' 'none' }
$provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $targets -contains $_.DisplayName })
Add-Item 'Still provisioned (new profiles inherit)' $(if ($provisioned) { ($provisioned.DisplayName | Sort-Object) -join ', ' } else { 'none' })

Add-Section 'ONEDRIVE'
Add-Item 'Per-user install' $(if (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") { 'PRESENT' } else { 'absent' })
Add-Item 'Machine-wide install' $(if ((Test-Path 'C:\Program Files\Microsoft OneDrive\OneDrive.exe') -or (Test-Path 'C:\Program Files (x86)\Microsoft OneDrive\OneDrive.exe')) { 'PRESENT' } else { 'absent' })
Add-Item 'Setup stub (System32/SysWOW64)' $(if ((Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") -or (Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe")) { 'PRESENT - reinstalls on new profiles' } else { 'absent' })
Add-Item 'Run key (current user)' (Test-RegValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'OneDrive')

Add-Section 'OEM / AV TRIALWARE'
$installed = @()
foreach ($hive in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
    $installed += Get-ItemProperty $hive -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match 'McAfee|Norton|Avast|AVG|Webroot|Dell (SupportAssist|Digital|Customer)|Dropbox|ExpressVPN' } |
        Select-Object -ExpandProperty DisplayName
}
if ($installed) { $installed | Sort-Object -Unique | ForEach-Object { Add-Item 'Found' $_ } }
else { Add-Item 'Trialware' 'none matched' }

# == Hardening state ==================================================
Add-Section 'HARDENING AND APPS'
$defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
Add-Item 'Defender real-time' $(if ($defender) { $defender.RealTimeProtectionEnabled } else { 'query failed' })
Add-Item 'Defender signatures' $(if ($defender) { $defender.AntivirusSignatureLastUpdated } else { '' })
Add-Item 'Telemetry (AllowTelemetry)' (Test-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry')
foreach ($svcName in @('RemoteRegistry', 'DiagTrack', 'dmwappushservice', 'RetailDemo')) {
    $svc = Get-Service $svcName -ErrorAction SilentlyContinue
    Add-Item "Service $svcName" $(if ($svc) { "$($svc.Status) / $($svc.StartType)" } else { 'absent' })
}
Add-Line
Add-Item 'Chrome installed' $(if ((Test-Path 'C:\Program Files\Google\Chrome\Application\chrome.exe') -or (Test-Path 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe')) { 'yes' } else { 'no' })
$extPolicy = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist' -ErrorAction SilentlyContinue
$forced = if ($extPolicy) { ($extPolicy.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { $_.Value }) -join '; ' } else { $null }
Add-Item 'Chrome forced extensions' $forced
Add-Item 'Malwarebytes' $(if (Test-Path 'C:\Program Files\Malwarebytes\Anti-Malware\mbam.exe') { 'installed' } else { 'absent' })
Add-Item 'Rufus' $(if (Get-ChildItem 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs' -Filter 'Rufus*' -ErrorAction SilentlyContinue) { 'installed' } else { 'absent' })

Add-Section 'NETWORK'
Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerAddresses } |
    ForEach-Object { Add-Item $_.InterfaceAlias ($_.ServerAddresses -join ', ') }
Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {
    $v6 = (Get-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue).Enabled
    Add-Item "Adapter $($_.Name)" "up  IPv6-bound=$v6"
}

# == Write ============================================================
Add-Line
Add-Line ('=' * 70)
Add-Line 'End of report'

$lines | Set-Content -Path $OutFile -Encoding UTF8
$lines | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "Report written to: $OutFile" -ForegroundColor Green
Write-Host "Run again after the session and diff the two files." -ForegroundColor Green

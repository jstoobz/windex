# helpers.ps1 — Reusable PowerShell snippets for Windows provisioning
#
# Not called by the provisioning suite directly. Source or copy-paste
# individual functions as needed.
#
# Usage: . C:\provision\scripts\helpers.ps1

# ── Display & Power ─────────────────────────────────────────────────

function Disable-ScreenTimeout {
    # Prevent display from turning off (AC power)
    powercfg /change monitor-timeout-ac 0
    powercfg /change standby-timeout-ac 0
    Write-Host "Display timeout and sleep disabled (AC)"
}

function Disable-LockScreen {
    # Disable lock screen via group policy registry key
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
    New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $path -Name NoLockScreen -Value 1 -Force
    Write-Host "Lock screen disabled"
}

function Enable-ScreenTimeout {
    # Restore defaults: 10 min display, 30 min sleep
    powercfg /change monitor-timeout-ac 10
    powercfg /change standby-timeout-ac 30
    Write-Host "Display timeout restored (10 min display, 30 min sleep)"
}

# ── Network ─────────────────────────────────────────────────────────

function Test-Internet {
    # Quick connectivity check
    $ping = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet
    if ($ping) { Write-Host "Internet: OK" }
    else { Write-Host "Internet: UNREACHABLE" }
    return $ping
}

function Get-PublicIP {
    (Invoke-RestMethod -Uri "https://api.ipify.org?format=json").ip
}

function Get-NetworkAdapters {
    # Show active adapters with IP info
    Get-NetAdapter | Where-Object Status -eq Up |
        ForEach-Object {
            $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
            [PSCustomObject]@{
                Name   = $_.Name
                Status = $_.Status
                IP     = $ip
                MAC    = $_.MacAddress
            }
        } | Format-Table -AutoSize
}

# ── System Info ─────────────────────────────────────────────────────

function Get-SystemSummary {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor
    [PSCustomObject]@{
        Hostname     = $env:COMPUTERNAME
        OS           = $os.Caption
        Build        = $os.BuildNumber
        Architecture = $env:PROCESSOR_ARCHITECTURE
        CPU          = $cpu.Name
        RAM          = "{0:N1} GB" -f ($os.TotalVisibleMemorySize / 1MB)
        Uptime       = (Get-Date) - $os.LastBootUpTime | ForEach-Object { "{0}d {1}h {2}m" -f $_.Days, $_.Hours, $_.Minutes }
    }
}

# ── Provisioning Helpers ────────────────────────────────────────────

function Test-AdminPrivilege {
    $current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TailscaleIP {
    if (Test-Path "C:\Program Files\Tailscale\tailscale.exe") {
        & "C:\Program Files\Tailscale\tailscale.exe" ip -4 2>$null
    }
    else {
        Write-Host "Tailscale not installed"
    }
}

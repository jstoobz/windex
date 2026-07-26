# debloat-apps.ps1 - Appx debloat, OneDrive removal, OEM/AV trialware sweep
# Called by 35-debloat-apps.bat. Keep this file pure ASCII (PS 5.1 reads
# BOM-less files via the ANSI codepage and smart quotes break parsing).
#
# Exit codes: 0 = success, 5 = partial success (warnings), 3 = failure

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$script:Warnings = 0
$script:Failures = 0

function Log([string]$Level, [string]$Message) {
    Write-Output ("[{0}] {1}" -f $Level.ToUpper(), $Message)
}

# ---------------------------------------------------------------------------
# Removal targets (exact package names; Name matching is ARM64-safe,
# arch-suffixed full names are not)
# ---------------------------------------------------------------------------
$targets = @(
    'Microsoft.549981C3F5F10'                  # Cortana app
    'Microsoft.BingNews'
    'Microsoft.BingSearch'
    'Microsoft.BingWeather'
    'Clipchamp.Clipchamp'
    'Microsoft.Copilot'
    'Microsoft.GamingApp'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.MicrosoftOfficeHub'             # Office upsell hub, NOT real Office
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MicrosoftStickyNotes'
    'Microsoft.OutlookForWindows'
    'Microsoft.People'
    'Microsoft.PowerAutomateDesktop'
    'MicrosoftCorporationII.MicrosoftFamily'
    'MicrosoftTeams'
    'MSTeams'
    'Microsoft.Todos'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'microsoft.windowscommunicationsapps'      # legacy Mail and Calendar
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.YourPhone'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
)

# ---------------------------------------------------------------------------
# DO-NOT-REMOVE guardrail. Any target matching one of these prefixes is
# skipped even if someone adds it to $targets later. Frameworks, Store,
# Defender UI, shell, codecs, kept inbox apps (Quick Assist stays: fallback
# remote channel), real Office (she uses Word), OEM driver appx.
# ---------------------------------------------------------------------------
$protected = @(
    'Microsoft.WindowsStore'
    'Microsoft.StorePurchaseApp'
    'Microsoft.DesktopAppInstaller'
    'Microsoft.WindowsAppRuntime'
    'Microsoft.UI.Xaml'
    'Microsoft.VCLibs'
    'Microsoft.NET.Native'
    'Microsoft.SecHealthUI'
    'MicrosoftWindows.Client'
    'Microsoft.Windows.CloudExperienceHost'
    'Microsoft.WindowsCalculator'
    'Microsoft.WindowsCamera'
    'Microsoft.WindowsNotepad'
    'Microsoft.Paint'
    'Microsoft.Windows.Photos'
    'Microsoft.ScreenSketch'
    'Microsoft.WindowsTerminal'
    'MicrosoftCorporationII.QuickAssist'
    'Microsoft.Office.Desktop'
    'Microsoft.HEVCVideoExtension'
    'Microsoft.HEIFImageExtension'
    'Microsoft.VP9VideoExtensions'
    'Microsoft.WebpImageExtension'
    'Microsoft.RawImageExtension'
    'Microsoft.WebMediaExtensions'
    'DolbyLaboratories'
    'RealtekSemiconductorCorp'
    'DellInc'
)

function Test-Protected([string]$Name) {
    foreach ($p in $protected) {
        if ($Name -like ($p + '*')) { return $true }
    }
    return $false
}

# Launch an uninstaller with a raw argument string (Start-Process -ArgumentList
# re-quotes arguments containing spaces and corrupts uninstall strings that
# carry their own quotes). Returns $false if it ran past the 10-minute cap -
# a stuck interactive dialog would otherwise hang a headless run forever.
function Invoke-Uninstall([string]$FileName, [string]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    if (-not $proc.WaitForExit(600000)) {
        try { $proc.Kill() } catch { }
        return $false
    }
    return $true
}

# ---------------------------------------------------------------------------
# Appx removal: per-user (-AllUsers) AND provisioned, so existing profiles
# are cleaned and new profiles never receive the package.
# ---------------------------------------------------------------------------
function Remove-TargetAppx {
    Log 'INFO' ("Processing {0} Appx targets..." -f $targets.Count)
    # Snapshot both package lists once - a full -AllUsers enumeration per
    # target costs seconds apiece on ARM64 hardware
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    $installed = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue

    foreach ($t in $targets) {
        if (Test-Protected $t) {
            Log 'WARN' ("Target '{0}' matches the protected list - skipping" -f $t)
            $script:Warnings++
            continue
        }

        $pkg = $installed | Where-Object { $_.Name -like $t }
        $prov = $provisioned | Where-Object { $_.DisplayName -like $t }
        if (-not $pkg -and -not $prov) { continue }

        if ($DryRun) {
            Log 'DRYRUN' ("Would remove Appx: {0}" -f $t)
            continue
        }

        # Two attempts: the AppX service intermittently fails rapid sequential
        # removals with 0x80070003, and Remove-AppxPackage throws TERMINATING
        # errors that SilentlyContinue does not suppress - one bad package
        # must not abort the whole sweep
        foreach ($attempt in 1, 2) {
            try {
                Get-AppxPackage -AllUsers -Name $t -ErrorAction SilentlyContinue |
                    Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like $t } |
                    ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
                break
            } catch {
                if ($attempt -eq 2) {
                    Log 'WARN' ("Removal of {0} failed: {1}" -f $t, $_.Exception.Message)
                    $script:Warnings++
                } else {
                    Start-Sleep -Seconds 2
                }
            }
        }

        # A package can survive as a STAGED zombie with no per-user installs
        # (Copilot does this - the Store re-stages it). Staged-only is
        # invisible to users and not inherited by new profiles: count it as
        # neutralized, only a remaining per-user install is a real failure.
        $remaining = @(Get-AppxPackage -AllUsers -Name $t -ErrorAction SilentlyContinue)
        $stillInstalled = $false
        foreach ($r in $remaining) {
            foreach ($ui in @($r.PackageUserInformation)) {
                if ("$($ui.InstallState)" -match 'Installed') { $stillInstalled = $true }
            }
        }
        if ($stillInstalled) {
            Log 'WARN' ("Still installed after removal attempt: {0}" -f $t)
            $script:Warnings++
        } elseif ($remaining.Count -gt 0) {
            Log 'OK' ("Neutralized (staged residue only, no user installs): {0}" -f $t)
        } else {
            Log 'OK' ("Removed: {0}" -f $t)
        }
    }
}

# ---------------------------------------------------------------------------
# OneDrive removal. Guard: if any profile's OneDrive folder contains files,
# skip removal entirely (OEM setup loves silently redirecting Documents -
# never strand her docs). Nag suppression in 37 covers the leftover surface.
# ---------------------------------------------------------------------------
function Remove-OneDrive {
    Log 'INFO' 'Checking OneDrive...'

    $folders = Get-ChildItem -Path 'C:\Users' -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ChildItem -Path $_.FullName -Directory -Filter 'OneDrive*' -Force -ErrorAction SilentlyContinue }
    foreach ($f in $folders) {
        # desktop.ini is shell metadata OneDrive stamps on an otherwise-empty
        # folder - it is never user data and must not block removal
        $firstFile = Get-ChildItem -Path $f.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'desktop.ini' } |
            Select-Object -First 1
        if ($firstFile) {
            Log 'WARN' ("OneDrive folder contains files: {0} - skipping OneDrive removal so no documents are stranded" -f $f.FullName)
            $script:Warnings++
            return
        }
    }

    $setups = @(
        (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
        (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDriveSetup.exe')
    )
    $found = $setups | Where-Object { Test-Path $_ }

    # 25H2 ships OneDrive per-machine under Program Files with its own setup
    # exe; the per-user binaries above leave it (and every new profile) intact
    $machineFound = Get-ChildItem -Path (Join-Path $env:ProgramFiles 'Microsoft OneDrive') `
        -Filter 'OneDriveSetup.exe' -Recurse -File -ErrorAction SilentlyContinue

    if (-not $found -and -not $machineFound) {
        Log 'INFO' 'OneDrive setup binary not found - nothing to remove'
        return
    }
    if ($DryRun) {
        Log 'DRYRUN' 'Would uninstall OneDrive (per-user and per-machine) and unpin it from the Explorer nav pane'
        return
    }

    Stop-Process -Name 'OneDrive' -Force -ErrorAction SilentlyContinue
    foreach ($setup in $found) {
        Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue
    }
    foreach ($setup in $machineFound) {
        Start-Process -FilePath $setup.FullName -ArgumentList '/uninstall', '/allusers' -Wait -ErrorAction SilentlyContinue
    }
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
        -Name 'OneDrive' -ErrorAction SilentlyContinue

    # Unpin from Explorer nav pane (keys may not exist post-uninstall; best-effort)
    foreach ($clsid in @(
        'Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
        'Registry::HKEY_CLASSES_ROOT\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
    )) {
        if (Test-Path $clsid) {
            Set-ItemProperty -Path $clsid -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -Type DWord -ErrorAction SilentlyContinue
        }
    }
    Log 'OK' 'OneDrive uninstalled'
}

# ---------------------------------------------------------------------------
# OEM/AV trialware sweep via the Uninstall registry (no winget dependency -
# fresh installs ship a broken winget source). Best-effort: quiet uninstall
# strings and msiexec product codes only; anything else is flagged manual.
# McAfee residue needs the official MCPR tool - flagged, not scripted.
# ---------------------------------------------------------------------------
function Remove-Trialware {
    Log 'INFO' 'Sweeping OEM/AV trialware...'

    $patterns = @('McAfee', 'Norton', 'SupportAssist', 'Dell Optimizer', 'Partner Promo', 'DellInc.PartnerPromo')
    $keep = @('Dell Command')   # legit BIOS/driver updater on real hardware

    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $entries = foreach ($root in $roots) {
        if (Test-Path $root) {
            Get-ChildItem $root -ErrorAction SilentlyContinue |
                ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue }
        }
    }

    $mcafeeSeen = $false
    foreach ($e in $entries) {
        $name = $e.DisplayName
        if (-not $name) { continue }

        $isTarget = $false
        foreach ($pat in $patterns) { if ($name -match [regex]::Escape($pat)) { $isTarget = $true; break } }
        if (-not $isTarget) { continue }

        $isKeep = $false
        foreach ($k in $keep) { if ($name -match [regex]::Escape($k)) { $isKeep = $true; break } }
        if ($isKeep) {
            Log 'INFO' ("Keeping (protected): {0}" -f $name)
            continue
        }

        if ($name -match 'McAfee') { $mcafeeSeen = $true }

        if ($DryRun) {
            Log 'DRYRUN' ("Would uninstall trialware: {0}" -f $name)
            continue
        }

        Log 'INFO' ("Uninstalling: {0}" -f $name)
        if ($e.QuietUninstallString) {
            # cmd /s /c with an outer quote pair executes uninstall strings
            # that contain their own quoted paths intact
            $ok = Invoke-Uninstall 'cmd.exe' ('/s /c "' + $e.QuietUninstallString + '"')
        } elseif ($e.UninstallString -match 'msiexec' -and $e.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') {
            $ok = Invoke-Uninstall 'msiexec.exe' ('/x ' + $e.PSChildName + ' /qn /norestart')
        } else {
            Log 'WARN' ("No quiet uninstall path for '{0}' - remove manually" -f $name)
            $script:Warnings++
            continue
        }
        if (-not $ok) {
            Log 'WARN' ("Uninstaller for '{0}' timed out after 10 minutes and was killed" -f $name)
            $script:Warnings++
        }
    }

    if ($mcafeeSeen -and -not $DryRun) {
        Log 'WARN' 'McAfee was present: run the official MCPR cleanup tool manually to clear residue'
        $script:Warnings++
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    Remove-TargetAppx
    Remove-OneDrive
    Remove-Trialware
} catch {
    Log 'ERROR' ("Unhandled failure: {0}" -f $_.Exception.Message)
    $script:Failures++
}

if ($script:Failures -gt 0) { exit 3 }
if ($script:Warnings -gt 0) { exit 5 }
exit 0

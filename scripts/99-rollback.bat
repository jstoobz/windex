@echo off
::==============================================================================
:: 99-rollback.bat - Rollback/Cleanup Script
::==============================================================================
:: Removes all components installed by the setup scripts.
::==============================================================================
setlocal EnableDelayedExpansion

:: Get script directory and load config
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

call "%SCRIPT_DIR%\lib\config.bat"
if errorlevel 1 (
    echo ERROR: Failed to load configuration
    exit /b 2
)

:: Parse command line arguments
:ParseArgs
if "%~1"=="" goto :ParseArgsDone
if /i "%~1"=="--dry-run" set "DRY_RUN=1"
if /i "%~1"=="--verbose" set "VERBOSE=1"
if /i "%~1"=="--force" set "FORCE=1"
if /i "%~1"=="-f" set "FORCE=1"
shift
goto :ParseArgs
:ParseArgsDone

:: ============================================================================
:: MAIN EXECUTION
:: ============================================================================
call "%LOG%" section "Rollback / Cleanup"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Confirmation prompt
if "%FORCE%"=="0" (
    if "%DRY_RUN%"=="0" (
        call :ConfirmRollback
        if errorlevel 1 (
            call "%LOG%" info "Rollback cancelled by user"
            exit /b %EXIT_CANCELLED%
        )
    )
)

:: Initialize counters
set "ROLLBACK_ERRORS=0"

call "%LOG%" info "Starting rollback process..."

:: Reverse order of installation (user-facing first, infra last)
call :RemoveStandardUser
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :RemoveChromePolicies
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :RevertDns
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :RevertPowerSettings
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :UninstallApps
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :RemoveDesktopShortcuts
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :RevertNagSuppression
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :NoteAppxDebloat

call :RemoveFirewallRules
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :UninstallVNC
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :UninstallOpenSSH
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :UninstallTailscale
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :RemoveSetupArtifacts
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :CleanupRegistry
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

:: Summary
echo.
echo ============================================================
echo Rollback Summary
echo ============================================================

if %ROLLBACK_ERRORS% GTR 0 (
    call "%LOG%" warn "Rollback completed with %ROLLBACK_ERRORS% issue(s)"
    call "%LOG%" info "Some components may require manual removal"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

call "%LOG%" success "Rollback completed successfully"
call "%LOG%" info "All components have been removed"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:ConfirmRollback
echo.
echo ============================================================
echo  WARNING: ROLLBACK CONFIRMATION
echo ============================================================
echo.
echo  This will REMOVE the following components:
echo    - Standard user account
echo    - Chrome policies, forced extensions
echo    - DNS filtering (revert to automatic)
echo    - Power settings (revert to Windows defaults)
echo    - Installed apps (Chrome, iTunes, Malwarebytes, Rufus)
echo    - Desktop shortcuts
echo    - Tailscale VPN (and disconnect from network)
echo    - VNC Server (remote access will be disabled)
echo    - OpenSSH Server
echo    - Firewall rules for VNC and SSH
echo    - Setup configuration and artifacts
echo.
echo  NOTE: Removed bloatware (TikTok, Solitaire, etc.) will NOT be
echo  reinstalled. Use the Microsoft Store to restore them if needed.
echo.
echo  This action cannot be easily undone.
echo.
set /p "CONFIRM=Are you sure you want to proceed? [y/N]: "
if /i "%CONFIRM%"=="y" exit /b 0
if /i "%CONFIRM%"=="yes" exit /b 0
exit /b 1

:RemoveStandardUser
call "%LOG%" info "Removing standard user account..."

:: Read the username from registry if available
set "STD_USER_NAME="
for /f "tokens=2*" %%A in ('reg query "%SETUP_REG_KEY%" /v "StandardUserName" 2^>nul ^| findstr "StandardUserName"') do set "STD_USER_NAME=%%B"

if not defined STD_USER_NAME (
    call "%LOG%" debug "No standard user recorded in registry, skipping"
    exit /b 0
)

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would delete user account and profile: %STD_USER_NAME%
    exit /b 0
)

:: Remove user profile first to avoid orphaned ProfileList entries
powershell -NoProfile -Command ^
    "Get-CimInstance Win32_UserProfile | " ^
    "Where-Object { $_.LocalPath -eq 'C:\Users\%STD_USER_NAME%' -or $_.LocalPath -like 'C:\Users\%STD_USER_NAME%.*' } | " ^
    "Remove-CimInstance" >nul 2>&1
call "%LOG%" debug "Cleaned up user profile for '%STD_USER_NAME%'"

:: Delete the user account
net user "%STD_USER_NAME%" /delete >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" success "User '%STD_USER_NAME%' deleted"
) else (
    call "%LOG%" warn "Could not delete user '%STD_USER_NAME%' [may not exist]"
)

exit /b 0

:RemoveChromePolicies
call "%LOG%" info "Removing Chrome policies and forced extensions..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would delete registry key: HKLM\SOFTWARE\Policies\Google\Chrome
    exit /b 0
)

:: Remove the entire Chrome policy tree (includes ExtensionInstallForcelist)
reg delete "HKLM\SOFTWARE\Policies\Google\Chrome" /f >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" success "Chrome policies removed"
) else (
    call "%LOG%" debug "No Chrome policies found"
)

exit /b 0

:RevertDns
call "%LOG%" info "Reverting DNS to automatic (DHCP)..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would reset DNS to DHCP on all network adapters
    exit /b 0
)

:: Reset all active adapters to DHCP DNS
powershell -NoProfile -Command ^
    "$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }; " ^
    "foreach ($a in $adapters) { " ^
    "  Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses; " ^
    "  Write-Host \"  Reset DNS on: $($a.Name)\"; " ^
    "}"
if errorlevel 1 (
    call "%LOG%" warn "Failed to reset DNS on some adapters"
    exit /b 1
)

call "%LOG%" success "DNS reverted to automatic (DHCP)"
exit /b 0

:RevertPowerSettings
call "%LOG%" info "Reverting power settings to Windows defaults..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would restore default power plan settings
    echo [DRY-RUN] Would remove Windows Update active hours override
    echo [DRY-RUN] Would remove auto-reboot prevention policy
    exit /b 0
)

:: Restore default power plan values
powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 15
powercfg /change monitor-timeout-ac 15
powercfg /change monitor-timeout-dc 5
powercfg /hibernate on
call "%LOG%" debug "Power plan restored to defaults"

:: Restore lid close action to sleep on AC
powercfg /setacvalueindex scheme_current sub_buttons lidaction 1
powercfg /setactive scheme_current
call "%LOG%" debug "Lid close action restored to sleep"

:: Remove active hours override (let Windows manage)
reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v "ActiveHoursStart" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v "ActiveHoursEnd" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v "IsActiveHoursEnabled" /f >nul 2>&1
call "%LOG%" debug "Windows Update active hours cleared"

:: Remove auto-reboot prevention policy
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoRebootWithLoggedOnUsers" /f >nul 2>&1
call "%LOG%" debug "Auto-reboot prevention policy removed"

call "%LOG%" success "Power settings reverted to defaults"
exit /b 0

:UninstallApps
call "%LOG%" info "Uninstalling provisioned applications..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would uninstall: Google Chrome, Apple iTunes, Malwarebytes, Rufus
    echo [DRY-RUN]   winget uninstall --id Google.Chrome --silent
    echo [DRY-RUN]   winget uninstall --id Apple.iTunes --silent
    echo [DRY-RUN]   winget uninstall --id Malwarebytes.Malwarebytes --silent
    echo [DRY-RUN]   winget uninstall --id Rufus.Rufus --silent
    exit /b 0
)

:: Uninstall each app via winget (gracefully skip if not installed)
for %%P in (Google.Chrome Apple.iTunes Malwarebytes.Malwarebytes Rufus.Rufus) do (
    call "%LOG%" debug "Uninstalling %%P..."
    winget uninstall --id %%P --silent >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        call "%LOG%" success "Uninstalled %%P"
    ) else (
        call "%LOG%" debug "%%P not found or already removed"
    )
)

exit /b 0

:RemoveDesktopShortcuts
call "%LOG%" info "Removing desktop shortcuts..."

set "PUBLIC_DESKTOP=C:\Users\Public\Desktop"

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove shortcuts from %PUBLIC_DESKTOP%
    exit /b 0
)

if exist "%PUBLIC_DESKTOP%\Google Chrome.lnk" (
    del "%PUBLIC_DESKTOP%\Google Chrome.lnk" 2>nul
    call "%LOG%" debug "Removed Chrome shortcut"
)

if exist "%PUBLIC_DESKTOP%\iTunes.lnk" (
    del "%PUBLIC_DESKTOP%\iTunes.lnk" 2>nul
    call "%LOG%" debug "Removed iTunes shortcut"
)

:: Rufus shortcut lives in the All-Users Start Menu, not the Public Desktop
if exist "%RUFUS_SHORTCUT%" (
    del "%RUFUS_SHORTCUT%" 2>nul
    call "%LOG%" debug "Removed Rufus Start Menu shortcut"
)

call "%LOG%" success "Desktop shortcuts removed"
exit /b 0

:: Reverts 37-suppress-nags: removes the HKLM policies the suite owns and the
:: Default-hive RunOnce hook. Seeded per-user preference values are left in
:: place - they are harmless prefs, not remote-access footprint.
:RevertNagSuppression
reg query "%SETUP_REG_KEY%" /v "NagsSuppressed" >nul 2>&1
if not %ERRORLEVEL% EQU 0 (
    call "%LOG%" debug "Nag suppression not applied, skipping"
    exit /b 0
)
call "%LOG%" info "Reverting nag suppression policies..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove Edge/Widgets/WindowsAI/OneDrive policy values and the Default-hive RunOnce hook
    exit /b 0
)
:: Delete only the values 37-suppress-nags.bat wrote - never whole keys,
:: which could carry policy set by tooling outside this suite
set "EDGE_POL=HKLM\SOFTWARE\Policies\Microsoft\Edge"
reg delete "%EDGE_POL%" /v "HideFirstRunExperience" /f >nul 2>&1
reg delete "%EDGE_POL%" /v "BrowserSignin" /f >nul 2>&1
reg delete "%EDGE_POL%" /v "SpotlightExperiencesAndRecommendationsEnabled" /f >nul 2>&1
reg delete "%EDGE_POL%" /v "ShowRecommendationsEnabled" /f >nul 2>&1
reg delete "%EDGE_POL%" /v "DefaultBrowserSettingEnabled" /f >nul 2>&1
reg delete "%EDGE_POL%" /v "StartupBoostEnabled" /f >nul 2>&1
reg delete "%EDGE_POL%" /v "BackgroundModeEnabled" /f >nul 2>&1
reg delete "%EDGE_POL%" /v "HubsSidebarEnabled" /f >nul 2>&1
reg delete "%EDGE_POL%" /v "NewTabPageContentEnabled" /f >nul 2>&1
reg delete "%EDGE_POL%" /v "EdgeShoppingAssistantEnabled" /f >nul 2>&1
reg delete "%EDGE_POL%" /v "PersonalizationReportingEnabled" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v "AllowNewsAndInterests" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v "HideRecommendedSection" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v "DisabledByGroupPolicy" /f >nul 2>&1
set "WINAI_POL=HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
reg delete "%WINAI_POL%" /v "AllowRecallEnablement" /f >nul 2>&1
reg delete "%WINAI_POL%" /v "DisableAIDataAnalysis" /f >nul 2>&1
reg delete "%WINAI_POL%" /v "DisableClickToDo" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v "TurnOffWindowsCopilot" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\OneDrive" /v "KFMBlockOptIn" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\OneDrive" /v "DisableFileSyncNGSC" /f >nul 2>&1

:: Per-user POLICY value - leaving it makes the Settings search toggle read
:: "managed by your organization". Plain preference values are left alone.
reg delete "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v "DisableSearchBoxSuggestions" /f >nul 2>&1

reg load HKU\DefUser "%SystemDrive%\Users\Default\NTUSER.DAT" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    reg delete "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "WindexNagSuppress" /f >nul 2>&1
    reg delete "HKU\DefUser\Software\Policies\Microsoft\Windows\Explorer" /v "DisableSearchBoxSuggestions" /f >nul 2>&1
    set "UNLOAD_OK=0"
    for /l %%R in (1,1,3) do (
        if "!UNLOAD_OK!"=="0" (
            reg unload HKU\DefUser >nul 2>&1
            if !ERRORLEVEL! EQU 0 (
                set "UNLOAD_OK=1"
            ) else (
                ping -n 3 127.0.0.1 >nul
            )
        )
    )
    if "!UNLOAD_OK!"=="0" call "%LOG%" warn "Failed to unload Default-User hive - a reboot will release it"
)
call "%LOG%" success "Nag suppression policies removed"
exit /b 0

:: 35-debloat-apps cannot be rolled back by script: removed Appx packages
:: come back via the Microsoft Store, OneDrive via OneDriveSetup.exe/winget.
:NoteAppxDebloat
reg query "%SETUP_REG_KEY%" /v "AppsDebloated" >nul 2>&1
if not %ERRORLEVEL% EQU 0 exit /b 0
call "%LOG%" info "App debloat is not reversible by rollback"
call "%LOG%" info "Reinstall removed apps from the Microsoft Store if needed"
exit /b 0

:RemoveFirewallRules
call "%LOG%" info "Removing firewall rules..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove firewall rules
    exit /b 0
)

netsh advfirewall firewall delete rule name="%FW_RULE_VNC_ALLOW%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" success "Removed rule: %FW_RULE_VNC_ALLOW%"
) else (
    call "%LOG%" debug "Rule not found: %FW_RULE_VNC_ALLOW%"
)

netsh advfirewall firewall delete rule name="%FW_RULE_VNC_BLOCK%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" success "Removed rule: %FW_RULE_VNC_BLOCK%"
) else (
    call "%LOG%" debug "Rule not found: %FW_RULE_VNC_BLOCK%"
)

netsh advfirewall firewall delete rule name="OpenSSH-Server-In-TCP" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" success "Removed rule: OpenSSH-Server-In-TCP"
) else (
    call "%LOG%" debug "Rule not found: OpenSSH-Server-In-TCP"
)

netsh advfirewall firewall delete rule name="sshd" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" success "Removed rule: sshd"
) else (
    call "%LOG%" debug "Rule not found: sshd"
)

exit /b 0

:UninstallVNC
call "%LOG%" info "Uninstalling VNC server..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would uninstall VNC server
    exit /b 0
)

sc query %VNC_SERVICE% >nul 2>&1
if errorlevel 1 (
    call "%LOG%" debug "VNC server not installed, skipping"
    exit /b 0
)

:: Stop the service first
call "%LOG%" debug "Stopping VNC service..."
net stop %VNC_SERVICE% >nul 2>&1

:: Try winget uninstall first (TigerVNC)
winget uninstall TigerVNC.TigerVNC --silent >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    ping -n 6 127.0.0.1 >nul
    call "%LOG%" success "VNC server uninstalled via winget"
    exit /b 0
)

:: Fall back to registry-based uninstall (handles TightVNC or other providers)
set "UNINSTALL_CMD="
for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "VNC" 2^>nul ^| findstr /i "UninstallString"') do (
    set "UNINSTALL_CMD=%%B"
)

if defined UNINSTALL_CMD (
    call "%LOG%" debug "Running uninstaller..."
    echo !UNINSTALL_CMD! | findstr /i "msiexec" >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        for /f "tokens=2 delims={}" %%G in ("!UNINSTALL_CMD!") do (
            msiexec /x {%%G} /quiet /norestart
        )
    ) else (
        !UNINSTALL_CMD! /S
    )
    ping -n 6 127.0.0.1 >nul
    call "%LOG%" success "VNC server uninstalled"
) else (
    call "%LOG%" warn "Could not find VNC uninstaller"
    exit /b 1
)

exit /b 0

:UninstallOpenSSH
call "%LOG%" info "Uninstalling OpenSSH Server..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would uninstall OpenSSH Server
    exit /b 0
)

sc query sshd >nul 2>&1
if errorlevel 1 (
    call "%LOG%" debug "OpenSSH Server not installed, skipping"
    exit /b 0
)

:: Stop sshd service
call "%LOG%" debug "Stopping sshd service..."
net stop sshd >nul 2>&1

:: Remove OpenSSH Server capability
call "%LOG%" debug "Removing OpenSSH Server capability..."
powershell -NoProfile -Command "Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" success "OpenSSH Server uninstalled"
) else (
    call "%LOG%" warn "Could not remove OpenSSH Server capability"
)

:: Clean up authorized_keys
if exist "C:\ProgramData\ssh\administrators_authorized_keys" (
    del "C:\ProgramData\ssh\administrators_authorized_keys" >nul 2>&1
    call "%LOG%" debug "Removed administrators_authorized_keys"
)

exit /b 0

:UninstallTailscale
call "%LOG%" info "Uninstalling Tailscale..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would uninstall Tailscale
    exit /b 0
)

if not exist "%TAILSCALE_EXE%" (
    call "%LOG%" debug "Tailscale not installed, skipping"
    exit /b 0
)

:: Disconnect and logout
call "%LOG%" debug "Disconnecting from Tailscale..."
"%TAILSCALE_EXE%" down >nul 2>&1
"%TAILSCALE_EXE%" logout >nul 2>&1

:: Stop the service
call "%LOG%" debug "Stopping Tailscale service..."
net stop Tailscale >nul 2>&1

:: Find uninstaller
for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "Tailscale" 2^>nul ^| findstr /i "UninstallString"') do (
    set "UNINSTALL_CMD=%%B"
)

if defined UNINSTALL_CMD (
    call "%LOG%" debug "Running uninstaller..."
    %UNINSTALL_CMD% /S
    ping -n 11 127.0.0.1 >nul
    call "%LOG%" success "Tailscale uninstalled"
) else if exist "C:\Program Files\Tailscale\uninstall.exe" (
    "C:\Program Files\Tailscale\uninstall.exe" /S
    ping -n 11 127.0.0.1 >nul
    call "%LOG%" success "Tailscale uninstalled"
) else (
    call "%LOG%" warn "Could not find Tailscale uninstaller"
    exit /b 1
)

exit /b 0

:RemoveSetupArtifacts
call "%LOG%" info "Removing setup artifacts..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove setup artifacts
    exit /b 0
)

if exist "%CREDENTIALS_FILE%" (
    call "%LOG%" debug "Removing credentials file..."
    echo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx > "%CREDENTIALS_FILE%"
    del "%CREDENTIALS_FILE%" 2>nul
    call "%LOG%" success "Credentials file removed"
)

if exist "%OUTPUT_DIR%\verification-report.txt" (
    del "%OUTPUT_DIR%\verification-report.txt" 2>nul
)

call "%LOG%" debug "Log files preserved for troubleshooting"
exit /b 0

:CleanupRegistry
call "%LOG%" info "Cleaning up registry..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove registry key: %SETUP_REG_KEY%
    exit /b 0
)

reg delete "%SETUP_REG_KEY%" /f >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" success "Setup registry keys removed"
) else (
    call "%LOG%" debug "No setup registry keys found"
)

exit /b 0

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

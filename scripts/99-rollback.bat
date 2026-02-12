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
call :LogSection "Rollback / Cleanup"

:: Check for admin privileges
call :CheckAdmin
if errorlevel 1 (
    call :LogError "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Confirmation prompt
if "%FORCE%"=="0" (
    if "%DRY_RUN%"=="0" (
        call :ConfirmRollback
        if errorlevel 1 (
            call :LogInfo "Rollback cancelled by user"
            exit /b %EXIT_CANCELLED%
        )
    )
)

:: Initialize counters
set "ROLLBACK_ERRORS=0"

call :LogInfo "Starting rollback process..."

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

call :RemoveFirewallRules
if errorlevel 1 set /a "ROLLBACK_ERRORS+=1"

call :UninstallTightVNC
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
    call :LogWarn "Rollback completed with %ROLLBACK_ERRORS% issue(s)"
    call :LogInfo "Some components may require manual removal"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

call :LogSuccess "Rollback completed successfully"
call :LogInfo "All components have been removed"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:LogSection
echo.
echo ============================================================
echo %~1
echo ============================================================
goto :eof

:LogInfo
echo [INFO] %~1
if defined LOG_FILE echo [%DATE% %TIME%] [INFO] %~1 >> "%LOG_FILE%"
goto :eof

:LogError
echo [ERROR] %~1
if defined LOG_FILE echo [%DATE% %TIME%] [ERROR] %~1 >> "%LOG_FILE%"
goto :eof

:LogSuccess
echo [OK] %~1
if defined LOG_FILE echo [%DATE% %TIME%] [OK] %~1 >> "%LOG_FILE%"
goto :eof

:LogDebug
if "%VERBOSE%"=="1" echo [DEBUG] %~1
if defined LOG_FILE echo [%DATE% %TIME%] [DEBUG] %~1 >> "%LOG_FILE%"
goto :eof

:LogWarn
echo [WARN] %~1
if defined LOG_FILE echo [%DATE% %TIME%] [WARN] %~1 >> "%LOG_FILE%"
goto :eof

:CheckAdmin
net session >nul 2>&1
if errorlevel 1 exit /b 1
exit /b 0

:ConfirmRollback
echo.
echo ============================================================
echo  WARNING: ROLLBACK CONFIRMATION
echo ============================================================
echo.
echo  This will REMOVE the following components:
echo    - Standard user account and auto-login
echo    - Chrome policies, forced extensions
echo    - DNS filtering (revert to automatic)
echo    - Power settings (revert to Windows defaults)
echo    - Installed apps (Chrome, iTunes, Malwarebytes)
echo    - Desktop shortcuts
echo    - Tailscale VPN (and disconnect from network)
echo    - TightVNC Server (remote access will be disabled)
echo    - Firewall rules for VNC
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
call :LogInfo "Removing standard user account..."

:: Read the username from registry if available
set "STD_USER_NAME="
for /f "tokens=2*" %%A in ('reg query "%SETUP_REG_KEY%" /v "StandardUserName" 2^>nul ^| findstr "StandardUserName"') do set "STD_USER_NAME=%%B"

if not defined STD_USER_NAME (
    call :LogDebug "No standard user recorded in registry, skipping"
    exit /b 0
)

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would delete user account: %STD_USER_NAME%
    echo [DRY-RUN] Would remove auto-login registry entries
    exit /b 0
)

:: Remove auto-login settings first
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "AutoAdminLogon" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultUserName" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultPassword" /f >nul 2>&1
call :LogDebug "Auto-login settings removed"

:: Delete the user account
net user "%STD_USER_NAME%" /delete >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogSuccess "User '%STD_USER_NAME%' deleted"
) else (
    call :LogWarn "Could not delete user '%STD_USER_NAME%' (may not exist)"
)

exit /b 0

:RemoveChromePolicies
call :LogInfo "Removing Chrome policies and forced extensions..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would delete registry key: HKLM\SOFTWARE\Policies\Google\Chrome
    exit /b 0
)

:: Remove the entire Chrome policy tree (includes ExtensionInstallForcelist)
reg delete "HKLM\SOFTWARE\Policies\Google\Chrome" /f >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogSuccess "Chrome policies removed"
) else (
    call :LogDebug "No Chrome policies found"
)

exit /b 0

:RevertDns
call :LogInfo "Reverting DNS to automatic (DHCP)..."

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
    call :LogWarn "Failed to reset DNS on some adapters"
    exit /b 1
)

call :LogSuccess "DNS reverted to automatic (DHCP)"
exit /b 0

:RevertPowerSettings
call :LogInfo "Reverting power settings to Windows defaults..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would restore default power plan settings
    echo [DRY-RUN] Would remove Windows Update active hours override
    exit /b 0
)

:: Restore default power plan values
powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 15
powercfg /change monitor-timeout-ac 15
powercfg /change monitor-timeout-dc 5
powercfg /hibernate on
call :LogDebug "Power plan restored to defaults"

:: Restore lid close action to sleep on AC
powercfg /setacvalueindex scheme_current sub_buttons lidaction 1
powercfg /setactive scheme_current
call :LogDebug "Lid close action restored to sleep"

:: Remove active hours override (let Windows manage)
reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v "ActiveHoursStart" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v "ActiveHoursEnd" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v "IsActiveHoursEnabled" /f >nul 2>&1
call :LogDebug "Windows Update active hours cleared"

call :LogSuccess "Power settings reverted to defaults"
exit /b 0

:UninstallApps
call :LogInfo "Uninstalling provisioned applications..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would uninstall: Google Chrome, Apple iTunes, Malwarebytes
    echo [DRY-RUN]   winget uninstall --id Google.Chrome --silent
    echo [DRY-RUN]   winget uninstall --id Apple.iTunes --silent
    echo [DRY-RUN]   winget uninstall --id Malwarebytes.Malwarebytes --silent
    exit /b 0
)

:: Uninstall each app via winget (gracefully skip if not installed)
for %%P in (Google.Chrome Apple.iTunes Malwarebytes.Malwarebytes) do (
    call :LogDebug "Uninstalling %%P..."
    winget uninstall --id %%P --silent >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        call :LogSuccess "Uninstalled %%P"
    ) else (
        call :LogDebug "%%P not found or already removed"
    )
)

exit /b 0

:RemoveDesktopShortcuts
call :LogInfo "Removing desktop shortcuts..."

set "PUBLIC_DESKTOP=C:\Users\Public\Desktop"

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove shortcuts from %PUBLIC_DESKTOP%
    exit /b 0
)

if exist "%PUBLIC_DESKTOP%\Google Chrome.lnk" (
    del "%PUBLIC_DESKTOP%\Google Chrome.lnk" 2>nul
    call :LogDebug "Removed Chrome shortcut"
)

if exist "%PUBLIC_DESKTOP%\iTunes.lnk" (
    del "%PUBLIC_DESKTOP%\iTunes.lnk" 2>nul
    call :LogDebug "Removed iTunes shortcut"
)

call :LogSuccess "Desktop shortcuts removed"
exit /b 0

:RemoveFirewallRules
call :LogInfo "Removing firewall rules..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove firewall rules
    exit /b 0
)

netsh advfirewall firewall delete rule name="%FW_RULE_VNC_ALLOW%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogSuccess "Removed rule: %FW_RULE_VNC_ALLOW%"
) else (
    call :LogDebug "Rule not found: %FW_RULE_VNC_ALLOW%"
)

netsh advfirewall firewall delete rule name="%FW_RULE_VNC_BLOCK%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogSuccess "Removed rule: %FW_RULE_VNC_BLOCK%"
) else (
    call :LogDebug "Rule not found: %FW_RULE_VNC_BLOCK%"
)

exit /b 0

:UninstallTightVNC
call :LogInfo "Uninstalling TightVNC..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would uninstall TightVNC
    exit /b 0
)

sc query %TIGHTVNC_SERVICE% >nul 2>&1
if errorlevel 1 (
    call :LogDebug "TightVNC not installed, skipping"
    exit /b 0
)

:: Stop the service first
call :LogDebug "Stopping TightVNC service..."
net stop %TIGHTVNC_SERVICE% >nul 2>&1

:: Find uninstall command from registry
for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "TightVNC" 2^>nul ^| findstr /i "UninstallString"') do (
    set "UNINSTALL_CMD=%%B"
)

if defined UNINSTALL_CMD (
    call :LogDebug "Running uninstaller..."
    echo %UNINSTALL_CMD% | findstr /i "msiexec" >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        for /f "tokens=2 delims={}" %%G in ("%UNINSTALL_CMD%") do (
            msiexec /x {%%G} /quiet /norestart
        )
    ) else (
        %UNINSTALL_CMD% /S
    )
    timeout /t 5 /nobreak >nul
    call :LogSuccess "TightVNC uninstalled"
) else (
    call :LogWarn "Could not find TightVNC uninstaller"
    exit /b 1
)

exit /b 0

:UninstallTailscale
call :LogInfo "Uninstalling Tailscale..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would uninstall Tailscale
    exit /b 0
)

if not exist "%TAILSCALE_EXE%" (
    call :LogDebug "Tailscale not installed, skipping"
    exit /b 0
)

:: Disconnect and logout
call :LogDebug "Disconnecting from Tailscale..."
"%TAILSCALE_EXE%" down >nul 2>&1
"%TAILSCALE_EXE%" logout >nul 2>&1

:: Stop the service
call :LogDebug "Stopping Tailscale service..."
net stop Tailscale >nul 2>&1

:: Find uninstaller
for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "Tailscale" 2^>nul ^| findstr /i "UninstallString"') do (
    set "UNINSTALL_CMD=%%B"
)

if defined UNINSTALL_CMD (
    call :LogDebug "Running uninstaller..."
    %UNINSTALL_CMD% /S
    timeout /t 10 /nobreak >nul
    call :LogSuccess "Tailscale uninstalled"
) else if exist "C:\Program Files\Tailscale\uninstall.exe" (
    "C:\Program Files\Tailscale\uninstall.exe" /S
    timeout /t 10 /nobreak >nul
    call :LogSuccess "Tailscale uninstalled"
) else (
    call :LogWarn "Could not find Tailscale uninstaller"
    exit /b 1
)

exit /b 0

:RemoveSetupArtifacts
call :LogInfo "Removing setup artifacts..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove setup artifacts
    exit /b 0
)

if exist "%CREDENTIALS_FILE%" (
    call :LogDebug "Removing credentials file..."
    echo xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx > "%CREDENTIALS_FILE%"
    del "%CREDENTIALS_FILE%" 2>nul
    call :LogSuccess "Credentials file removed"
)

if exist "%OUTPUT_DIR%\verification-report.txt" (
    del "%OUTPUT_DIR%\verification-report.txt" 2>nul
)

call :LogDebug "Log files preserved for troubleshooting"
exit /b 0

:CleanupRegistry
call :LogInfo "Cleaning up registry..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove registry key: %SETUP_REG_KEY%
    exit /b 0
)

reg delete "%SETUP_REG_KEY%" /f >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogSuccess "Setup registry keys removed"
) else (
    call :LogDebug "No setup registry keys found"
)

exit /b 0

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

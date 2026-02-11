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
echo    - Tailscale VPN (and disconnect from network)
echo    - TightVNC Server (remote access will be disabled)
echo    - Firewall rules for VNC
echo    - Setup configuration and artifacts
echo.
echo  This action cannot be easily undone.
echo.
set /p "CONFIRM=Are you sure you want to proceed? [y/N]: "
if /i "%CONFIRM%"=="y" exit /b 0
if /i "%CONFIRM%"=="yes" exit /b 0
exit /b 1

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

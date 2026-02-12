@echo off
::==============================================================================
:: 00-setup-master.bat - Master Setup Orchestrator
::==============================================================================
:: Main entry point for the Remote Access Automation Suite.
:: Runs all installation scripts in sequence with error handling.
::
:: Usage: 00-setup-master.bat --authkey=tskey-auth-xxxxx [options]
::
:: Options:
::   --authkey=KEY       Tailscale auth key (required)
::   --dry-run           Show what would be done without making changes
::   --verbose           Enable verbose output
::   --force             Skip confirmation prompts
::   --skip-tailscale    Skip Tailscale installation
::   --skip-vnc          Skip TightVNC installation
::   --skip-firewall     Skip firewall configuration
::   --skip-hardening    Skip system hardening
::   --skip-apps         Skip essential app installation
::   --skip-chrome       Skip Chrome hardening
::   --skip-power        Skip power and update settings
::   --skip-dns          Skip DNS filtering
::   --skip-desktop      Skip desktop customization
::   --skip-user         Skip standard user creation
::   --username=NAME     Standard user account name
::   --password=PASS     Standard user account password
::   --continue-on-error Continue even if a step fails
::
:: Exit Codes: 0=Success, 1=Cancelled, 2=Prerequisites, 3=Failed, 4=Verification
::==============================================================================
setlocal EnableDelayedExpansion

:: Get script directory
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: Load configuration (sets environment variables only)
call "%SCRIPT_DIR%\lib\config.bat"
if errorlevel 1 (
    echo ERROR: Failed to load configuration
    pause
    exit /b 2
)

:: Initialize skip flags
set "SKIP_TAILSCALE=0"
set "SKIP_VNC=0"
set "SKIP_FIREWALL=0"
set "SKIP_HARDENING=0"
set "SKIP_APPS=0"
set "SKIP_CHROME_HARDENING=0"
set "SKIP_POWER=0"
set "SKIP_DNS=0"
set "SKIP_DESKTOP=0"
set "SKIP_USER=0"

:: Parse command line arguments
:ParseArgs
if "%~1"=="" goto :ParseArgsDone
if /i "%~1"=="--dry-run" set "DRY_RUN=1"
if /i "%~1"=="-n" set "DRY_RUN=1"
if /i "%~1"=="--verbose" set "VERBOSE=1"
if /i "%~1"=="-v" set "VERBOSE=1"
if /i "%~1"=="--force" set "FORCE=1"
if /i "%~1"=="-f" set "FORCE=1"
if /i "%~1"=="--continue-on-error" set "CONTINUE_ON_ERROR=1"
if /i "%~1"=="--skip-tailscale" set "SKIP_TAILSCALE=1"
if /i "%~1"=="--skip-vnc" set "SKIP_VNC=1"
if /i "%~1"=="--skip-firewall" set "SKIP_FIREWALL=1"
if /i "%~1"=="--skip-hardening" set "SKIP_HARDENING=1"
if /i "%~1"=="--skip-apps" set "SKIP_APPS=1"
if /i "%~1"=="--skip-chrome" set "SKIP_CHROME_HARDENING=1"
if /i "%~1"=="--skip-power" set "SKIP_POWER=1"
if /i "%~1"=="--skip-dns" set "SKIP_DNS=1"
if /i "%~1"=="--skip-desktop" set "SKIP_DESKTOP=1"
if /i "%~1"=="--skip-user" set "SKIP_USER=1"
if /i "%~1"=="--help" goto :ShowHelp
if /i "%~1"=="/?" goto :ShowHelp
:: Handle --authkey=VALUE format
echo %~1 | findstr /i "^--authkey=" >nul
if not errorlevel 1 (
    for /f "tokens=1,* delims==" %%A in ("%~1") do set "TAILSCALE_AUTHKEY=%%B"
)
:: Handle --username=VALUE format
echo %~1 | findstr /i "^--username=" >nul
if not errorlevel 1 (
    for /f "tokens=1,* delims==" %%A in ("%~1") do set "STANDARD_USERNAME=%%B"
)
:: Handle --password=VALUE format
echo %~1 | findstr /i "^--password=" >nul
if not errorlevel 1 (
    for /f "tokens=1,* delims==" %%A in ("%~1") do set "STANDARD_PASSWORD=%%B"
)
shift
goto :ParseArgs
:ParseArgsDone

:: ============================================================================
:: MAIN EXECUTION
:: ============================================================================

:: Display banner
call :ShowBanner

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    call "%LOG%" info "Please right-click and select 'Run as administrator'"
    pause
    exit /b %EXIT_PREREQ_FAILED%
)

:: Validate auth key
if "%TAILSCALE_AUTHKEY%"=="" (
    if "%SKIP_TAILSCALE%"=="0" (
        call "%LOG%" error "Tailscale auth key is required"
        echo.
        echo Usage: %~nx0 --authkey=tskey-auth-xxxxx [options]
        echo.
        echo Get your auth key from:
        echo   https://login.tailscale.com/admin/settings/keys
        echo.
        echo For a dry-run without auth key:
        echo   %~nx0 --dry-run
        echo.
        pause
        exit /b %EXIT_PREREQ_FAILED%
    )
)

:: Confirmation
if "%FORCE%"=="0" (
    if "%DRY_RUN%"=="0" (
        call :ConfirmSetup
        if errorlevel 1 (
            call "%LOG%" info "Setup cancelled by user"
            exit /b %EXIT_CANCELLED%
        )
    )
)

:: Initialize step tracking
set "STEPS_TOTAL=12"
set "STEPS_COMPLETED=0"
set "STEPS_FAILED=0"
set "STEPS_SKIPPED=0"
set "START_TIME=%TIME%"

:: ============================================================================
:: STEP 1: Install Tailscale
:: ============================================================================
if "%SKIP_TAILSCALE%"=="1" (
    call :StepSkipped "Tailscale Installation"
) else (
    call :RunStep "Tailscale Installation" "10-install-tailscale.bat"
    if errorlevel 1 (
        if "%CONTINUE_ON_ERROR%"=="0" goto :SetupFailed
    )
)

:: ============================================================================
:: STEP 2: Install TightVNC
:: ============================================================================
if "%SKIP_VNC%"=="1" (
    call :StepSkipped "TightVNC Installation"
) else (
    call :RunStep "TightVNC Installation" "20-install-tightvnc.bat"
    if errorlevel 1 (
        if "%CONTINUE_ON_ERROR%"=="0" goto :SetupFailed
    )
)

:: ============================================================================
:: STEP 3: Configure Firewall
:: ============================================================================
if "%SKIP_FIREWALL%"=="1" (
    call :StepSkipped "Firewall Configuration"
) else (
    call :RunStep "Firewall Configuration" "30-configure-firewall.bat"
    if errorlevel 1 (
        if "%CONTINUE_ON_ERROR%"=="0" goto :SetupFailed
    )
)

:: ============================================================================
:: STEP 4: System Hardening
:: ============================================================================
if "%SKIP_HARDENING%"=="1" (
    call :StepSkipped "System Hardening"
) else (
    call :RunStep "System Hardening" "40-harden-system.bat"
    if errorlevel 1 (
        if "%CONTINUE_ON_ERROR%"=="0" goto :SetupFailed
    )
)

:: ============================================================================
:: STEP 5: Power and Update Settings
:: ============================================================================
if "%SKIP_POWER%"=="1" (
    call :StepSkipped "Power and Update Settings"
) else (
    call :RunStep "Power and Update Settings" "45-configure-power.bat"
    if errorlevel 1 (
        if "%CONTINUE_ON_ERROR%"=="0" goto :SetupFailed
    )
)

:: ============================================================================
:: STEP 6: Install Essential Apps
:: ============================================================================
if "%SKIP_APPS%"=="1" (
    call :StepSkipped "Essential App Installation"
) else (
    call :RunStep "Essential App Installation" "60-install-apps.bat"
    if errorlevel 1 (
        if "%CONTINUE_ON_ERROR%"=="0" goto :SetupFailed
    )
)

:: ============================================================================
:: STEP 7: DNS Filtering
:: ============================================================================
if "%SKIP_DNS%"=="1" (
    call :StepSkipped "DNS Filtering"
) else (
    call :RunStep "DNS Filtering" "65-configure-dns.bat"
    if errorlevel 1 (
        if "%CONTINUE_ON_ERROR%"=="0" goto :SetupFailed
    )
)

:: ============================================================================
:: STEP 8: Harden Chrome
:: ============================================================================
if "%SKIP_CHROME_HARDENING%"=="1" (
    call :StepSkipped "Chrome Hardening"
) else (
    call :RunStep "Chrome Hardening" "70-harden-chrome.bat"
    if errorlevel 1 (
        if "%CONTINUE_ON_ERROR%"=="0" goto :SetupFailed
    )
)

:: ============================================================================
:: STEP 9: Desktop Customization
:: ============================================================================
if "%SKIP_DESKTOP%"=="1" (
    call :StepSkipped "Desktop Customization"
) else (
    call :RunStep "Desktop Customization" "75-customize-desktop.bat"
    if errorlevel 1 (
        if "%CONTINUE_ON_ERROR%"=="0" goto :SetupFailed
    )
)

:: ============================================================================
:: STEP 10: Standard User Account
:: ============================================================================
if "%SKIP_USER%"=="1" (
    call :StepSkipped "Standard User Account"
) else (
    call :RunStep "Standard User Account" "80-create-standard-user.bat"
    if errorlevel 1 (
        if "%CONTINUE_ON_ERROR%"=="0" goto :SetupFailed
    )
)

:: ============================================================================
:: STEP 11: Configure Services
:: ============================================================================
call :RunStep "Service Configuration" "50-configure-services.bat"
if errorlevel 1 (
    if "%CONTINUE_ON_ERROR%"=="0" goto :SetupFailed
)

:: ============================================================================
:: STEP 12: Verify Setup
:: ============================================================================
call :RunStep "Setup Verification" "90-verify-setup.bat"
set "VERIFY_RESULT=%ERRORLEVEL%"

:: ============================================================================
:: SUMMARY
:: ============================================================================
call :ShowSummary

if %STEPS_FAILED% GTR 0 (
    exit /b %EXIT_PARTIAL_SUCCESS%
)

if %VERIFY_RESULT% NEQ 0 (
    exit /b %EXIT_VERIFICATION_FAILED%
)

exit /b %EXIT_SUCCESS%

:SetupFailed
call "%LOG%" error "Setup failed at step"
call :ShowSummary
exit /b %EXIT_EXECUTION_FAILED%

:: ============================================================================
:: FUNCTIONS (must be in same file to be callable)
:: ============================================================================

:ShowBanner
echo.
echo  ============================================================
echo   %SETUP_NAME%
echo   Version %SETUP_VERSION%
echo  ============================================================
echo.
if "%DRY_RUN%"=="1" (
    echo   *** DRY-RUN MODE - No changes will be made ***
    echo.
)
goto :eof

:ConfirmSetup
echo  This script will:
echo.
if "%SKIP_TAILSCALE%"=="0" echo    1. Install Tailscale VPN
if "%SKIP_VNC%"=="0"       echo    2. Install TightVNC Server
if "%SKIP_FIREWALL%"=="0"  echo    3. Configure Windows Firewall
if "%SKIP_HARDENING%"=="0" echo    4. Apply security hardening
if "%SKIP_POWER%"=="0"     echo    5. Configure power and update settings
if "%SKIP_APPS%"=="0"      echo    6. Install essential apps (Chrome, iTunes, Malwarebytes)
if "%SKIP_DNS%"=="0"       echo    7. Configure DNS filtering (malware/phishing protection)
if "%SKIP_CHROME_HARDENING%"=="0" echo    8. Harden Chrome browser
if "%SKIP_DESKTOP%"=="0"   echo    9. Customize desktop and Start menu
if "%SKIP_USER%"=="0"      echo   10. Create standard user account
echo   11. Configure services for auto-start
echo   12. Verify the installation
echo.
echo  ============================================================
echo.
set /p "CONFIRM=Continue with setup? [Y/n]: "
if /i "%CONFIRM%"=="n" exit /b 1
if /i "%CONFIRM%"=="no" exit /b 1
exit /b 0

:RunStep
setlocal
set "STEP_NAME=%~1"
set "STEP_SCRIPT=%~2"

set /a "CURRENT_STEP=STEPS_COMPLETED + STEPS_FAILED + STEPS_SKIPPED + 1"

echo.
echo ============================================================
echo [%CURRENT_STEP%/%STEPS_TOTAL%] %STEP_NAME%
echo ============================================================

:: Build command with arguments
set "CMD=%SCRIPT_DIR%\%STEP_SCRIPT%"

:: Execute step - pass arguments via environment variables (already set)
call "%CMD%"
set "STEP_RESULT=%ERRORLEVEL%"

:: Return result to caller
endlocal & set "STEP_RESULT=%STEP_RESULT%"

if %STEP_RESULT% EQU 0 (
    set /a "STEPS_COMPLETED+=1"
    exit /b 0
) else if %STEP_RESULT% EQU 5 (
    set /a "STEPS_COMPLETED+=1"
    exit /b 0
) else (
    set /a "STEPS_FAILED+=1"
    exit /b %STEP_RESULT%
)

:StepSkipped
set "STEP_NAME=%~1"
set /a "STEPS_SKIPPED+=1"
set /a "CURRENT_STEP=STEPS_COMPLETED + STEPS_FAILED + STEPS_SKIPPED"
echo.
echo ============================================================
echo [%CURRENT_STEP%/%STEPS_TOTAL%] %STEP_NAME% - SKIPPED
echo ============================================================
goto :eof

:ShowSummary
echo.
echo ============================================================
echo Setup Summary
echo ============================================================
echo.
echo   Started:    %START_TIME%
echo   Finished:   %TIME%
echo.
echo   Steps Completed: %STEPS_COMPLETED%
echo   Steps Skipped:   %STEPS_SKIPPED%
echo   Steps Failed:    %STEPS_FAILED%
echo.

:: Try to get Tailscale IP
if exist "%TAILSCALE_EXE%" (
    for /f "tokens=*" %%I in ('"%TAILSCALE_EXE%" ip -4 2^>nul') do set "TAILSCALE_IP=%%I"
)

if defined TAILSCALE_IP (
    echo ============================================================
    echo Connection Information
    echo ============================================================
    echo.
    echo   Tailscale IP:  %TAILSCALE_IP%
    echo   VNC Port:      %VNC_PORT%
    echo.
    echo   To connect, use a VNC client:
    echo     Address: %TAILSCALE_IP%:%VNC_PORT%
    echo.
)

if exist "%CREDENTIALS_FILE%" (
    echo   VNC Password saved to:
    echo     %CREDENTIALS_FILE%
    echo.
)

if defined LOG_FILE (
    echo   Log file:
    echo     %LOG_FILE%
    echo.
)

echo ============================================================

if %STEPS_FAILED% EQU 0 (
    if "%DRY_RUN%"=="0" (
        echo.
        echo  Setup completed successfully!
        echo.
    ) else (
        echo.
        echo  Dry-run completed. No changes were made.
        echo  Remove --dry-run flag to perform actual setup.
        echo.
    )
) else (
    echo.
    echo  Setup completed with errors.
    echo  Check the log file for details.
    echo.
)

pause
goto :eof

:ShowHelp
echo.
echo Remote Access Automation Suite v%SETUP_VERSION%
echo.
echo Usage: %~nx0 --authkey=KEY [options]
echo.
echo Required:
echo   --authkey=KEY       Tailscale authentication key
echo                       Get from: https://login.tailscale.com/admin/settings/keys
echo.
echo Options:
echo   --dry-run           Show what would be done without making changes
echo   --verbose           Enable verbose output
echo   --force             Skip confirmation prompts
echo   --continue-on-error Continue if a step fails
echo.
echo   --skip-tailscale    Skip Tailscale installation
echo   --skip-vnc          Skip TightVNC installation
echo   --skip-firewall     Skip firewall configuration
echo   --skip-hardening    Skip system hardening
echo   --skip-apps         Skip essential app installation
echo   --skip-chrome       Skip Chrome hardening
echo   --skip-power        Skip power and update settings
echo   --skip-dns          Skip DNS filtering
echo   --skip-desktop      Skip desktop customization
echo   --skip-user         Skip standard user creation
echo.
echo   --username=NAME     Standard user account name
echo   --password=PASS     Standard user account password
echo.
echo Examples:
echo   %~nx0 --authkey=tskey-auth-xxxxx
echo   %~nx0 --authkey=tskey-auth-xxxxx --dry-run
echo   %~nx0 --authkey=tskey-auth-xxxxx --verbose --skip-hardening
echo.
pause
exit /b 0

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

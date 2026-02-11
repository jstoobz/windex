@echo off
::==============================================================================
:: 30-configure-firewall.bat - Windows Firewall Configuration
::==============================================================================
:: Configures Windows Firewall to allow VNC connections ONLY from
:: Tailscale subnet (100.64.0.0/10) and block all other VNC access.
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
shift
goto :ParseArgs
:ParseArgsDone

:: ============================================================================
:: MAIN EXECUTION
:: ============================================================================
call :LogSection "Firewall Configuration"

:: Check for admin privileges
call :CheckAdmin
if errorlevel 1 (
    call :LogError "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if firewall rules already exist
call :CheckFirewallRulesExist
if %ERRORLEVEL% EQU 0 (
    call :LogInfo "Firewall rules already configured"
    call :VerifyFirewallRules
    if %ERRORLEVEL% EQU 0 (
        call :LogSuccess "Firewall rules are correctly configured"
        exit /b %EXIT_SUCCESS%
    ) else (
        call :LogWarn "Firewall rules exist but may be misconfigured"
        call :LogInfo "Removing existing rules and recreating..."
        call :RemoveFirewallRules
    )
)

:: Ensure Windows Firewall is enabled
call :EnsureFirewallEnabled
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Create firewall rules
call :CreateFirewallRules
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Enable firewall logging
call :EnableFirewallLogging

:: Verify rules
call :VerifyFirewallRules
if errorlevel 1 exit /b %EXIT_VERIFICATION_FAILED%

:: Mark as configured
call :MarkConfigured

call :LogSuccess "Firewall configuration completed successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:LogSection
echo.
echo ============================================================
echo %~1
echo ============================================================
if defined LOG_FILE echo ============================================================ >> "%LOG_FILE%"
if defined LOG_FILE echo %~1 >> "%LOG_FILE%"
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

:CheckFirewallRulesExist
call :LogDebug "Checking for existing firewall rules..."
netsh advfirewall firewall show rule name="%FW_RULE_VNC_ALLOW%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogDebug "VNC allow rule exists"
    exit /b 0
)
netsh advfirewall firewall show rule name="%FW_RULE_VNC_BLOCK%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogDebug "VNC block rule exists"
    exit /b 0
)
exit /b 1

:EnsureFirewallEnabled
call :LogInfo "Verifying Windows Firewall is enabled..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would verify/enable Windows Firewall
    exit /b 0
)

netsh advfirewall show allprofiles state | findstr "ON" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogDebug "Windows Firewall is enabled"
    exit /b 0
)

call :LogWarn "Windows Firewall is disabled, enabling..."
netsh advfirewall set allprofiles state on >nul 2>&1
if errorlevel 1 (
    call :LogError "Failed to enable Windows Firewall"
    exit /b 1
)
call :LogSuccess "Windows Firewall enabled"
exit /b 0

:RemoveFirewallRules
call :LogInfo "Removing existing VNC firewall rules..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove firewall rules
    exit /b 0
)

netsh advfirewall firewall delete rule name="%FW_RULE_VNC_ALLOW%" >nul 2>&1
netsh advfirewall firewall delete rule name="%FW_RULE_VNC_BLOCK%" >nul 2>&1
call :LogDebug "Existing rules removed"
exit /b 0

:CreateFirewallRules
call :LogInfo "Creating firewall rules..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would create firewall rule: Allow VNC from Tailscale (%TAILSCALE_SUBNET%)
    echo [DRY-RUN] Would create firewall rule: Block VNC from all other sources
    exit /b 0
)

:: Rule 1: Allow VNC from Tailscale subnet only
call :LogDebug "Creating allow rule for Tailscale subnet..."
netsh advfirewall firewall add rule name="%FW_RULE_VNC_ALLOW%" dir=in action=allow protocol=tcp localport=%VNC_PORT% remoteip=%TAILSCALE_SUBNET% profile=any description="Allow VNC connections from Tailscale network only" enable=yes >nul 2>&1
if errorlevel 1 (
    call :LogError "Failed to create VNC allow rule"
    exit /b 1
)
call :LogSuccess "Created rule: %FW_RULE_VNC_ALLOW%"

:: Rule 2: Block VNC from everywhere else
call :LogDebug "Creating block rule for all other sources..."
netsh advfirewall firewall add rule name="%FW_RULE_VNC_BLOCK%" dir=in action=block protocol=tcp localport=%VNC_PORT% profile=any description="Block VNC connections from non-Tailscale sources" enable=yes >nul 2>&1
if errorlevel 1 (
    call :LogError "Failed to create VNC block rule"
    exit /b 1
)
call :LogSuccess "Created rule: %FW_RULE_VNC_BLOCK%"
exit /b 0

:EnableFirewallLogging
call :LogInfo "Enabling firewall logging for blocked connections..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would enable firewall logging
    exit /b 0
)

netsh advfirewall set allprofiles logging droppedconnections enable >nul 2>&1
set "FW_LOG_PATH=%SystemRoot%\System32\LogFiles\Firewall\pfirewall.log"
netsh advfirewall set allprofiles logging filename "%FW_LOG_PATH%" >nul 2>&1
netsh advfirewall set allprofiles logging maxfilesize 32768 >nul 2>&1
call :LogDebug "Firewall logging configured"
exit /b 0

:VerifyFirewallRules
call :LogInfo "Verifying firewall rules..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would verify firewall rules
    exit /b 0
)

set "VERIFY_PASSED=1"

netsh advfirewall firewall show rule name="%FW_RULE_VNC_ALLOW%" >nul 2>&1
if errorlevel 1 (
    call :LogError "Allow rule not found: %FW_RULE_VNC_ALLOW%"
    set "VERIFY_PASSED=0"
) else (
    call :LogDebug "Allow rule verified: OK"
)

netsh advfirewall firewall show rule name="%FW_RULE_VNC_BLOCK%" >nul 2>&1
if errorlevel 1 (
    call :LogError "Block rule not found: %FW_RULE_VNC_BLOCK%"
    set "VERIFY_PASSED=0"
) else (
    call :LogDebug "Block rule verified: OK"
)

netsh advfirewall show allprofiles state | findstr "ON" >nul 2>&1
if errorlevel 1 (
    call :LogError "Windows Firewall is not enabled"
    set "VERIFY_PASSED=0"
) else (
    call :LogDebug "Firewall enabled: OK"
)

if "%VERIFY_PASSED%"=="0" (
    call :LogError "Firewall verification failed"
    exit /b 1
)
call :LogSuccess "Firewall verification passed"
exit /b 0

:MarkConfigured
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark firewall as configured in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "FirewallConfigured" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "FirewallConfigDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "FirewallAllowedSubnet" /t REG_SZ /d "%TAILSCALE_SUBNET%" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

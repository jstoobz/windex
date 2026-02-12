@echo off
::==============================================================================
:: 90-verify-setup.bat - Installation Verification Script
::==============================================================================
:: Performs comprehensive verification of the entire remote access setup.
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
shift
goto :ParseArgs
:ParseArgsDone

:: ============================================================================
:: MAIN EXECUTION
:: ============================================================================
call "%LOG%" section "Setup Verification"

:: Initialize counters
set "CHECKS_PASSED=0"
set "CHECKS_FAILED=0"
set "CHECKS_WARNED=0"
set "TOTAL_CHECKS=0"

:: Run all verification checks
call :VerifyTailscale
call :VerifyTightVNC
call :VerifyFirewall
call :VerifyServices
call :VerifyApps
call :VerifyChromePolicies
call :VerifyDns
call :VerifyPowerSettings

:: Generate summary
call :GenerateSummary

:: Return appropriate exit code
if %CHECKS_FAILED% GTR 0 (
    echo.
    echo [ERROR] Verification FAILED: %CHECKS_FAILED% checks failed
    exit /b %EXIT_VERIFICATION_FAILED%
)

if %CHECKS_WARNED% GTR 0 (
    echo.
    echo [WARN] Verification PASSED with warnings: %CHECKS_WARNED% warnings
    exit /b %EXIT_PARTIAL_SUCCESS%
)

echo.
echo [OK] Verification PASSED: All %CHECKS_PASSED% checks passed
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: VERIFICATION FUNCTIONS
:: ============================================================================

:VerifyTailscale
echo.
echo Verifying Tailscale...

:: Check 1: Tailscale executable exists
set /a "TOTAL_CHECKS+=1"
if exist "%TAILSCALE_EXE%" (
    call :CheckPass "Tailscale executable exists"
) else (
    call :CheckFail "Tailscale executable not found"
    goto :VerifyTailscaleDone
)

:: Check 2: Tailscale service is running
set /a "TOTAL_CHECKS+=1"
sc query Tailscale | findstr "RUNNING" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "Tailscale service is running"
) else (
    call :CheckFail "Tailscale service is not running"
)

:: Check 3: Tailscale is connected
set /a "TOTAL_CHECKS+=1"
"%TAILSCALE_EXE%" status >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "Tailscale is connected"
) else (
    call :CheckFail "Tailscale is not connected"
)

:: Check 4: Tailscale has an IP address
set /a "TOTAL_CHECKS+=1"
for /f "tokens=*" %%I in ('"%TAILSCALE_EXE%" ip -4 2^>nul') do set "TAILSCALE_IP=%%I"
if defined TAILSCALE_IP (
    call :CheckPass "Tailscale IP: %TAILSCALE_IP%"
) else (
    call :CheckFail "Tailscale IP not assigned"
)

:VerifyTailscaleDone
goto :eof

:VerifyTightVNC
echo.
echo Verifying TightVNC...

:: Check 1: TightVNC executable exists
set /a "TOTAL_CHECKS+=1"
if exist "%TIGHTVNC_DIR%\tvnserver.exe" (
    call :CheckPass "TightVNC executable exists"
) else (
    call :CheckFail "TightVNC executable not found"
    goto :VerifyTightVNCDone
)

:: Check 2: TightVNC service is running
set /a "TOTAL_CHECKS+=1"
sc query %TIGHTVNC_SERVICE% | findstr "RUNNING" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "TightVNC service is running"
) else (
    call :CheckFail "TightVNC service is not running"
)

:: Check 3: VNC port is listening
set /a "TOTAL_CHECKS+=1"
netstat -an | findstr ":%VNC_PORT% .*LISTENING" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "VNC port %VNC_PORT% is listening"
) else (
    call :CheckFail "VNC port %VNC_PORT% is not listening"
)

:: Check 4: Credentials file exists
set /a "TOTAL_CHECKS+=1"
if exist "%CREDENTIALS_FILE%" (
    call :CheckPass "Credentials file exists"
) else (
    call :CheckWarn "Credentials file not found"
)

:VerifyTightVNCDone
goto :eof

:VerifyFirewall
echo.
echo Verifying Firewall...

:: Check 1: Windows Firewall is enabled
set /a "TOTAL_CHECKS+=1"
netsh advfirewall show allprofiles state | findstr "ON" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "Windows Firewall is enabled"
) else (
    call :CheckFail "Windows Firewall is disabled"
)

:: Check 2: VNC allow rule exists
set /a "TOTAL_CHECKS+=1"
netsh advfirewall firewall show rule name="%FW_RULE_VNC_ALLOW%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "VNC allow rule exists"
) else (
    call :CheckFail "VNC allow rule not found"
)

:: Check 3: VNC block rule exists
set /a "TOTAL_CHECKS+=1"
netsh advfirewall firewall show rule name="%FW_RULE_VNC_BLOCK%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "VNC block rule exists"
) else (
    call :CheckFail "VNC block rule not found"
)

goto :eof

:VerifyServices
echo.
echo Verifying Service Configuration...

:: Check 1: Tailscale auto-start
set /a "TOTAL_CHECKS+=1"
sc qc Tailscale 2>nul | findstr "AUTO_START" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "Tailscale set to auto-start"
) else (
    call :CheckWarn "Tailscale may not auto-start"
)

:: Check 2: TightVNC auto-start
set /a "TOTAL_CHECKS+=1"
sc qc %TIGHTVNC_SERVICE% 2>nul | findstr "AUTO_START" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "TightVNC set to auto-start"
) else (
    call :CheckWarn "TightVNC may not auto-start"
)

goto :eof

:VerifyApps
echo.
echo Verifying Essential Apps...

:: Check Chrome
set /a "TOTAL_CHECKS+=1"
if exist "%CHROME_EXE%" (
    call :CheckPass "Google Chrome is installed"
) else (
    call :CheckFail "Google Chrome not found"
)

:: Check iTunes
set /a "TOTAL_CHECKS+=1"
if exist "%ITUNES_EXE%" (
    call :CheckPass "Apple iTunes is installed"
) else (
    call :CheckFail "Apple iTunes not found"
)

:: Check Malwarebytes
set /a "TOTAL_CHECKS+=1"
if exist "%MALWAREBYTES_EXE%" (
    call :CheckPass "Malwarebytes is installed"
) else (
    call :CheckFail "Malwarebytes not found"
)

goto :eof

:VerifyChromePolicies
echo.
echo Verifying Chrome Policies...

:: Check uBlock Origin force-install
set /a "TOTAL_CHECKS+=1"
reg query "HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist" /v "1" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "uBlock Origin force-install key exists"
) else (
    call :CheckFail "uBlock Origin force-install key not found"
)

:: Check Safe Browsing
set /a "TOTAL_CHECKS+=1"
reg query "HKLM\SOFTWARE\Policies\Google\Chrome" /v "SafeBrowsingProtectionLevel" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "Chrome Safe Browsing policy is set"
) else (
    call :CheckFail "Chrome Safe Browsing policy not found"
)

:: Check popup blocking
set /a "TOTAL_CHECKS+=1"
reg query "HKLM\SOFTWARE\Policies\Google\Chrome" /v "DefaultPopupsSetting" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "Chrome popup blocking policy is set"
) else (
    call :CheckFail "Chrome popup blocking policy not found"
)

goto :eof

:VerifyDns
echo.
echo Verifying DNS Configuration...

set /a "TOTAL_CHECKS+=1"
powershell -NoProfile -Command ^
    "$dns = Get-DnsClientServerAddress -AddressFamily IPv4 | " ^
    "Where-Object { $_.ServerAddresses -contains '%DNS_PRIMARY%' }; " ^
    "if ($dns) { exit 0 } else { exit 1 }" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "DNS filtering active (%DNS_PRIMARY%)"
) else (
    call :CheckWarn "DNS filtering not detected on any adapter"
)

goto :eof

:VerifyPowerSettings
echo.
echo Verifying Power Settings...

:: Check AC sleep timeout (should be 0 = never)
set /a "TOTAL_CHECKS+=1"
powershell -NoProfile -Command ^
    "$p = powercfg /query scheme_current sub_sleep standby-timeout-ac 2>$null; " ^
    "if ($p -match '0x00000000') { exit 0 } else { exit 1 }" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "AC sleep disabled (never)"
) else (
    call :CheckWarn "AC sleep may not be disabled"
)

:: Check Windows Update active hours
set /a "TOTAL_CHECKS+=1"
reg query "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v "IsActiveHoursEnabled" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :CheckPass "Windows Update active hours configured"
) else (
    call :CheckWarn "Windows Update active hours not set"
)

goto :eof

:: ============================================================================
:: HELPER FUNCTIONS
:: ============================================================================

:CheckPass
set /a "CHECKS_PASSED+=1"
echo   [PASS] %~1
goto :eof

:CheckFail
set /a "CHECKS_FAILED+=1"
echo   [FAIL] %~1
goto :eof

:CheckWarn
set /a "CHECKS_WARNED+=1"
echo   [WARN] %~1
goto :eof

:GenerateSummary
echo.
echo ============================================================
echo Verification Summary
echo ============================================================
echo   Total Checks:  %TOTAL_CHECKS%
echo   Passed:        %CHECKS_PASSED%
echo   Failed:        %CHECKS_FAILED%
echo   Warnings:      %CHECKS_WARNED%
echo ============================================================

if defined TAILSCALE_IP (
    echo.
    echo Connection Information:
    echo   Tailscale IP:  %TAILSCALE_IP%
    echo   VNC Port:      %VNC_PORT%
    echo   Connect to:    %TAILSCALE_IP%:%VNC_PORT%
)

if exist "%CREDENTIALS_FILE%" (
    echo   Credentials:   %CREDENTIALS_FILE%
)

echo ============================================================
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

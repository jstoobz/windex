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
call :LogSection "Setup Verification"

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

:: Generate summary
call :GenerateSummary

:: Return appropriate exit code
if %CHECKS_FAILED% GTR 0 (
    echo.
    echo [ERROR] Verification FAILED: %CHECKS_FAILED% check(s) failed
    exit /b %EXIT_VERIFICATION_FAILED%
)

if %CHECKS_WARNED% GTR 0 (
    echo.
    echo [WARN] Verification PASSED with warnings: %CHECKS_WARNED% warning(s)
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

:: ============================================================================
:: HELPER FUNCTIONS
:: ============================================================================

:LogSection
echo.
echo ============================================================
echo %~1
echo ============================================================
goto :eof

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

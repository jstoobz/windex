@echo off
::==============================================================================
:: 70-harden-chrome.bat - Chrome Browser Hardening
::==============================================================================
:: Force-installs essential extensions and applies safe browsing policies
:: via Chrome enterprise registry keys.
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
call :LogSection "Chrome Browser Hardening"

:: Check for admin privileges
call :CheckAdmin
if errorlevel 1 (
    call :LogError "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if Chrome is installed
if not exist "%CHROME_EXE%" (
    call :LogWarn "Google Chrome is not installed, skipping hardening"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

:: Check if already hardened
reg query "%SETUP_REG_KEY%" /v "ChromeHardened" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    if not "%FORCE%"=="1" (
        call :LogInfo "Chrome hardening already applied"
        call :LogSuccess "Chrome hardening is in place"
        exit /b %EXIT_SUCCESS%
    )
)

:: Apply hardening
set "HARDEN_ERRORS=0"

call :ForceInstallExtensions
if errorlevel 1 set /a "HARDEN_ERRORS+=1"

call :ApplyChromePolicies
if errorlevel 1 set /a "HARDEN_ERRORS+=1"

:: Mark as hardened
call :MarkHardened

if %HARDEN_ERRORS% GTR 0 (
    call :LogWarn "Chrome hardening completed with %HARDEN_ERRORS% error(s)"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

call :LogSuccess "Chrome hardening completed successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:LogSection
echo.
echo ============================================================
echo %~1
echo ============================================================
if defined LOG_FILE (
    echo. >> "%LOG_FILE%"
    echo ============================================================ >> "%LOG_FILE%"
    echo %~1 >> "%LOG_FILE%"
    echo ============================================================ >> "%LOG_FILE%"
)
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

:: ============================================================================
:: FORCE-INSTALL EXTENSIONS
:: ============================================================================

:ForceInstallExtensions
call :LogInfo "Force-installing Chrome extensions..."

set "EXT_KEY=HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist"
set "UBLOCK_VALUE=%EXT_UBLOCK%;https://clients2.google.com/service/update2/crx"

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would create registry key: %EXT_KEY%
    echo [DRY-RUN] Would add extension: uBlock Origin (%EXT_UBLOCK%)
    echo [DRY-RUN]   reg add "%EXT_KEY%" /v "1" /t REG_SZ /d "%UBLOCK_VALUE%" /f
    exit /b 0
)

reg add "%EXT_KEY%" /v "1" /t REG_SZ /d "%UBLOCK_VALUE%" /f >nul 2>&1
if errorlevel 1 (
    call :LogError "Failed to add uBlock Origin to force-install list"
    exit /b 1
)

call :LogSuccess "uBlock Origin added to force-install list"
exit /b 0

:: ============================================================================
:: CHROME POLICIES
:: ============================================================================

:ApplyChromePolicies
call :LogInfo "Applying Chrome browser policies..."

set "CHROME_KEY=HKLM\SOFTWARE\Policies\Google\Chrome"

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would apply Chrome policies to: %CHROME_KEY%
    echo [DRY-RUN]   SafeBrowsingProtectionLevel = 2 (enhanced)
    echo [DRY-RUN]   SafeBrowsingEnabled = 1
    echo [DRY-RUN]   PasswordManagerEnabled = 0
    echo [DRY-RUN]   AutofillCreditCardEnabled = 0
    echo [DRY-RUN]   DefaultPopupsSetting = 2 (block)
    echo [DRY-RUN]   BrowserSignin = 0 (disabled)
    echo [DRY-RUN]   HomepageLocation = https://www.google.com
    exit /b 0
)

set "POLICY_ERRORS=0"

:: Enhanced Safe Browsing
reg add "%CHROME_KEY%" /v "SafeBrowsingProtectionLevel" /t REG_DWORD /d 2 /f >nul 2>&1
if errorlevel 1 set /a "POLICY_ERRORS+=1"

:: Safe Browsing enabled
reg add "%CHROME_KEY%" /v "SafeBrowsingEnabled" /t REG_DWORD /d 1 /f >nul 2>&1
if errorlevel 1 set /a "POLICY_ERRORS+=1"

:: Disable password manager
reg add "%CHROME_KEY%" /v "PasswordManagerEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
if errorlevel 1 set /a "POLICY_ERRORS+=1"

:: Disable credit card autofill
reg add "%CHROME_KEY%" /v "AutofillCreditCardEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
if errorlevel 1 set /a "POLICY_ERRORS+=1"

:: Block popups
reg add "%CHROME_KEY%" /v "DefaultPopupsSetting" /t REG_DWORD /d 2 /f >nul 2>&1
if errorlevel 1 set /a "POLICY_ERRORS+=1"

:: Disable browser sign-in
reg add "%CHROME_KEY%" /v "BrowserSignin" /t REG_DWORD /d 0 /f >nul 2>&1
if errorlevel 1 set /a "POLICY_ERRORS+=1"

:: Set homepage
reg add "%CHROME_KEY%" /v "HomepageLocation" /t REG_SZ /d "https://www.google.com" /f >nul 2>&1
if errorlevel 1 set /a "POLICY_ERRORS+=1"

if %POLICY_ERRORS% GTR 0 (
    call :LogError "Failed to apply %POLICY_ERRORS% Chrome policy(s)"
    exit /b 1
)

call :LogSuccess "Chrome policies applied"
exit /b 0

:: ============================================================================
:: REGISTRY MARKER
:: ============================================================================

:MarkHardened
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark Chrome as hardened in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "ChromeHardened" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "ChromeHardenedDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

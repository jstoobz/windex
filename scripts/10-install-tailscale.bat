@echo off
::==============================================================================
:: 10-install-tailscale.bat - Tailscale Installation Script
::==============================================================================
:: Downloads and installs Tailscale mesh VPN with auth key authentication.
:: Supports dry-run mode and idempotent execution.
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

:: Parse command line arguments (for standalone use)
:ParseArgs
if "%~1"=="" goto :ParseArgsDone
if /i "%~1"=="--dry-run" set "DRY_RUN=1"
if /i "%~1"=="--verbose" set "VERBOSE=1"
if /i "%~1"=="--force" set "FORCE=1"
echo %~1 | findstr /i "^--authkey=" >nul
if not errorlevel 1 (
    for /f "tokens=1,* delims==" %%A in ("%~1") do set "TAILSCALE_AUTHKEY=%%B"
)
shift
goto :ParseArgs
:ParseArgsDone

:: ============================================================================
:: MAIN EXECUTION
:: ============================================================================
call :LogSection "Tailscale Installation"

:: Check for admin privileges
call :CheckAdmin
if errorlevel 1 (
    call :LogError "Administrator privileges required"
    call :LogInfo "Please run this script as Administrator"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if auth key is provided
if "%TAILSCALE_AUTHKEY%"=="" (
    call :LogError "Tailscale auth key not provided"
    call :LogInfo "Set TAILSCALE_AUTHKEY environment variable or use --authkey parameter"
    call :LogInfo "Get your auth key from: https://login.tailscale.com/admin/settings/keys"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already installed (idempotency)
call :CheckTailscaleInstalled
if %ERRORLEVEL% EQU 0 (
    call :LogInfo "Tailscale is already installed"
    call :VerifyTailscaleConnection
    if %ERRORLEVEL% EQU 0 (
        call :LogSuccess "Tailscale is installed and connected"
        exit /b %EXIT_SUCCESS%
    ) else (
        call :LogInfo "Tailscale installed but not connected, attempting to connect..."
        call :ConnectTailscale
        exit /b %ERRORLEVEL%
    )
)

:: Pre-flight checks
call :PreflightChecks
if errorlevel 1 exit /b %EXIT_PREREQ_FAILED%

:: Download Tailscale installer
call :DownloadTailscale
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Install Tailscale
call :InstallTailscale
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Connect to Tailscale network
call :ConnectTailscale
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Verify installation
call :VerifyInstallation
if errorlevel 1 exit /b %EXIT_VERIFICATION_FAILED%

:: Mark as installed in registry
call :MarkInstalled

call :LogSuccess "Tailscale installation completed successfully"
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

:CheckTailscaleInstalled
call :LogDebug "Checking if Tailscale is installed..."
if exist "%TAILSCALE_EXE%" (
    call :LogDebug "Tailscale executable found"
    exit /b 0
)
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "Tailscale" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogDebug "Tailscale found in registry"
    exit /b 0
)
sc query Tailscale >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogDebug "Tailscale service found"
    exit /b 0
)
exit /b 1

:VerifyTailscaleConnection
call :LogDebug "Verifying Tailscale connection..."
if not exist "%TAILSCALE_EXE%" exit /b 1
"%TAILSCALE_EXE%" status >nul 2>&1
if errorlevel 1 (
    call :LogDebug "Tailscale not connected"
    exit /b 1
)
for /f "tokens=*" %%I in ('"%TAILSCALE_EXE%" ip -4 2^>nul') do set "TAILSCALE_IP=%%I"
if not defined TAILSCALE_IP (
    call :LogDebug "Could not get Tailscale IP"
    exit /b 1
)
call :LogDebug "Tailscale connected with IP: %TAILSCALE_IP%"
exit /b 0

:PreflightChecks
call :LogInfo "Running pre-flight checks..."
ping -n 1 -w 3000 8.8.8.8 >nul 2>&1
if errorlevel 1 (
    call :LogError "No internet connectivity"
    exit /b 1
)
call :LogDebug "Internet connectivity: OK"
call :LogSuccess "Pre-flight checks passed"
exit /b 0

:DownloadTailscale
set "INSTALLER_PATH=%TEMP%\tailscale-setup.exe"
call :LogInfo "Downloading Tailscale installer..."
if exist "%INSTALLER_PATH%" del "%INSTALLER_PATH%" 2>nul

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would download: %TAILSCALE_URL%
    echo [DRY-RUN]   to: %INSTALLER_PATH%
    exit /b 0
)

powershell -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%TAILSCALE_URL%' -OutFile '%INSTALLER_PATH%' -UseBasicParsing"
if errorlevel 1 (
    call :LogError "Failed to download Tailscale installer"
    exit /b 1
)

if not exist "%INSTALLER_PATH%" (
    call :LogError "Installer file not found after download"
    exit /b 1
)
call :LogSuccess "Download complete"
exit /b 0

:InstallTailscale
set "INSTALLER_PATH=%TEMP%\tailscale-setup.exe"
call :LogInfo "Installing Tailscale..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would execute: "%INSTALLER_PATH%" /S
    exit /b 0
)

call :LogDebug "Running: %INSTALLER_PATH% /S"
"%INSTALLER_PATH%" /S
if errorlevel 1 (
    call :LogError "Tailscale installation failed"
    exit /b 1
)

call :LogDebug "Waiting for installation to complete..."
set "WAIT_COUNT=0"
:WaitForInstall
if exist "%TAILSCALE_EXE%" goto :InstallComplete
timeout /t 2 /nobreak >nul
set /a "WAIT_COUNT+=1"
if %WAIT_COUNT% GTR 30 (
    call :LogError "Timeout waiting for Tailscale installation"
    exit /b 1
)
goto :WaitForInstall

:InstallComplete
call :LogSuccess "Tailscale installed successfully"
del "%INSTALLER_PATH%" 2>nul
exit /b 0

:ConnectTailscale
call :LogInfo "Connecting to Tailscale network..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would execute: "%TAILSCALE_EXE%" up --authkey=***
    exit /b 0
)

call :LogDebug "Waiting for Tailscale service..."
set "WAIT_COUNT=0"
:WaitForService
sc query Tailscale | findstr "RUNNING" >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :ServiceRunning
timeout /t 2 /nobreak >nul
set /a "WAIT_COUNT+=1"
if %WAIT_COUNT% GTR 30 (
    call :LogError "Timeout waiting for Tailscale service"
    exit /b 1
)
goto :WaitForService

:ServiceRunning
call :LogDebug "Tailscale service is running"
call :LogDebug "Authenticating with auth key..."
"%TAILSCALE_EXE%" up --authkey=%TAILSCALE_AUTHKEY%
if errorlevel 1 (
    call :LogError "Failed to connect to Tailscale"
    call :LogError "Check that your auth key is valid and not expired"
    exit /b 1
)

timeout /t 5 /nobreak >nul

for /f "tokens=*" %%I in ('"%TAILSCALE_EXE%" ip -4 2^>nul') do set "TAILSCALE_IP=%%I"
if not defined TAILSCALE_IP (
    call :LogWarn "Could not retrieve Tailscale IP address"
) else (
    call :LogSuccess "Connected to Tailscale with IP: %TAILSCALE_IP%"
)
exit /b 0

:VerifyInstallation
call :LogInfo "Verifying Tailscale installation..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would verify Tailscale installation
    exit /b 0
)

if not exist "%TAILSCALE_EXE%" (
    call :LogError "Tailscale executable not found"
    exit /b 1
)
call :LogDebug "Executable exists: OK"

sc query Tailscale | findstr "RUNNING" >nul 2>&1
if errorlevel 1 (
    call :LogError "Tailscale service is not running"
    exit /b 1
)
call :LogDebug "Service running: OK"

"%TAILSCALE_EXE%" status >nul 2>&1
if errorlevel 1 (
    call :LogError "Tailscale is not connected"
    exit /b 1
)
call :LogDebug "Connection status: OK"

for /f "tokens=*" %%I in ('"%TAILSCALE_EXE%" ip -4 2^>nul') do set "TAILSCALE_IP=%%I"
if defined TAILSCALE_IP (
    call :LogInfo "Tailscale IP: %TAILSCALE_IP%"
)

call :LogSuccess "Tailscale verification passed"
exit /b 0

:MarkInstalled
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark Tailscale as installed in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "TailscaleInstalled" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "TailscaleInstallDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
if defined TAILSCALE_IP (
    reg add "%SETUP_REG_KEY%" /v "TailscaleIP" /t REG_SZ /d "%TAILSCALE_IP%" /f >nul 2>&1
)
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

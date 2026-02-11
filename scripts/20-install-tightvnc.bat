@echo off
::==============================================================================
:: 20-install-tightvnc.bat - TightVNC Installation Script
::==============================================================================
:: Downloads and installs TightVNC Server with auto-generated secure password.
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
shift
goto :ParseArgs
:ParseArgsDone

:: ============================================================================
:: MAIN EXECUTION
:: ============================================================================
call :LogSection "TightVNC Installation"

:: Check for admin privileges
call :CheckAdmin
if errorlevel 1 (
    call :LogError "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already installed (idempotency)
call :CheckTightVNCInstalled
if %ERRORLEVEL% EQU 0 (
    call :LogInfo "TightVNC is already installed"
    call :VerifyTightVNCService
    if %ERRORLEVEL% EQU 0 (
        call :LogSuccess "TightVNC is installed and running"
        exit /b %EXIT_SUCCESS%
    ) else (
        call :LogWarn "TightVNC installed but service not running"
        call :StartTightVNCService
        exit /b %ERRORLEVEL%
    )
)

:: Pre-flight checks
call :PreflightChecks
if errorlevel 1 exit /b %EXIT_PREREQ_FAILED%

:: Generate secure password
call :GeneratePassword
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Download TightVNC installer
call :DownloadTightVNC
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Install TightVNC
call :InstallTightVNC
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Save credentials
call :SaveCredentials

:: Verify installation
call :VerifyInstallation
if errorlevel 1 exit /b %EXIT_VERIFICATION_FAILED%

:: Mark as installed
call :MarkInstalled

call :LogSuccess "TightVNC installation completed successfully"
call :LogInfo "VNC credentials saved to: %CREDENTIALS_FILE%"
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

:CheckTightVNCInstalled
call :LogDebug "Checking if TightVNC is installed..."
if exist "%TIGHTVNC_DIR%\tvnserver.exe" (
    call :LogDebug "TightVNC executable found"
    exit /b 0
)
sc query %TIGHTVNC_SERVICE% >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogDebug "TightVNC service found"
    exit /b 0
)
exit /b 1

:VerifyTightVNCService
call :LogDebug "Checking TightVNC service status..."
sc query %TIGHTVNC_SERVICE% | findstr "RUNNING" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogDebug "TightVNC service is running"
    exit /b 0
)
exit /b 1

:StartTightVNCService
call :LogInfo "Starting TightVNC service..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would start TightVNC service
    exit /b 0
)
net start %TIGHTVNC_SERVICE% >nul 2>&1
if errorlevel 1 (
    call :LogError "Failed to start TightVNC service"
    exit /b 1
)
call :LogSuccess "TightVNC service started"
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

:GeneratePassword
call :LogInfo "Generating secure VNC password..."
if "%DRY_RUN%"=="1" (
    set "VNC_PASSWORD=DryRunPassword123"
    echo [DRY-RUN] Would generate %VNC_PASSWORD_LENGTH%-character password
    exit /b 0
)

:: Generate password using PowerShell
for /f "delims=" %%P in ('powershell -Command "Add-Type -AssemblyName System.Web; [System.Web.Security.Membership]::GeneratePassword(%VNC_PASSWORD_LENGTH%, %VNC_PASSWORD_SPECIAL_CHARS%)"') do (
    set "VNC_PASSWORD=%%P"
)

if not defined VNC_PASSWORD (
    :: Fallback: simpler password generation
    for /f "delims=" %%P in ('powershell -Command "$chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -join ((1..%VNC_PASSWORD_LENGTH%) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })"') do (
        set "VNC_PASSWORD=%%P"
    )
)

if not defined VNC_PASSWORD (
    call :LogError "Failed to generate password"
    exit /b 1
)

call :LogDebug "Password generated successfully"
exit /b 0

:DownloadTightVNC
set "INSTALLER_PATH=%TEMP%\tightvnc-setup.msi"
call :LogInfo "Downloading TightVNC installer..."

if exist "%INSTALLER_PATH%" del "%INSTALLER_PATH%" 2>nul

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would download: %TIGHTVNC_URL%
    exit /b 0
)

powershell -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%TIGHTVNC_URL%' -OutFile '%INSTALLER_PATH%' -UseBasicParsing"
if errorlevel 1 (
    call :LogError "Failed to download TightVNC installer"
    exit /b 1
)

if not exist "%INSTALLER_PATH%" (
    call :LogError "Installer file not found after download"
    exit /b 1
)
call :LogSuccess "Download complete"
exit /b 0

:InstallTightVNC
set "INSTALLER_PATH=%TEMP%\tightvnc-setup.msi"
call :LogInfo "Installing TightVNC..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would install TightVNC with generated password
    exit /b 0
)

:: Build MSI command
set "MSI_ARGS=/quiet /norestart ADDLOCAL=Server"
set "MSI_ARGS=%MSI_ARGS% SET_USEVNCAUTHENTICATION=1 VALUE_OF_USEVNCAUTHENTICATION=1"
set "MSI_ARGS=%MSI_ARGS% SET_PASSWORD=1 VALUE_OF_PASSWORD=%VNC_PASSWORD%"
set "MSI_ARGS=%MSI_ARGS% SET_USECONTROLAUTHENTICATION=1 VALUE_OF_CONTROLPASSWORD=%VNC_PASSWORD%"
set "MSI_ARGS=%MSI_ARGS% SET_ALLOWLOOPBACK=1 VALUE_OF_ALLOWLOOPBACK=1"

call :LogDebug "Running MSI installer..."
msiexec /i "%INSTALLER_PATH%" %MSI_ARGS%
set "MSI_RESULT=%ERRORLEVEL%"

if %MSI_RESULT% EQU 0 (
    call :LogSuccess "TightVNC installed successfully"
) else if %MSI_RESULT% EQU 3010 (
    call :LogSuccess "TightVNC installed (reboot may be required)"
) else (
    call :LogError "TightVNC installation failed (code: %MSI_RESULT%)"
    exit /b 1
)

:: Wait for service registration
call :LogDebug "Waiting for service registration..."
set "WAIT_COUNT=0"
:WaitForServiceReg
sc query %TIGHTVNC_SERVICE% >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :ServiceRegistered
timeout /t 2 /nobreak >nul
set /a "WAIT_COUNT+=1"
if %WAIT_COUNT% GTR 30 (
    call :LogError "Timeout waiting for TightVNC service registration"
    exit /b 1
)
goto :WaitForServiceReg

:ServiceRegistered
call :LogDebug "Service registered successfully"
call :StartTightVNCService
del "%INSTALLER_PATH%" 2>nul
exit /b 0

:SaveCredentials
call :LogInfo "Saving VNC credentials..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would save credentials to: %CREDENTIALS_FILE%
    exit /b 0
)

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%" 2>nul

:: Get Tailscale IP if available
if exist "%TAILSCALE_EXE%" (
    for /f "tokens=*" %%I in ('"%TAILSCALE_EXE%" ip -4 2^>nul') do set "TAILSCALE_IP=%%I"
)

(
    echo ============================================================
    echo Remote Access Credentials
    echo Generated: %DATE% %TIME%
    echo ============================================================
    echo.
    echo VNC Server Configuration:
    echo   Port: %VNC_PORT%
    echo   Password: %VNC_PASSWORD%
    echo.
    if defined TAILSCALE_IP (
        echo Connection Information:
        echo   Tailscale IP: %TAILSCALE_IP%
        echo   Connect to: %TAILSCALE_IP%:%VNC_PORT%
        echo.
    )
    echo IMPORTANT: Keep this file secure and delete after use.
    echo ============================================================
) > "%CREDENTIALS_FILE%"

call :LogDebug "Credentials saved to: %CREDENTIALS_FILE%"
exit /b 0

:VerifyInstallation
call :LogInfo "Verifying TightVNC installation..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would verify TightVNC installation
    exit /b 0
)

if not exist "%TIGHTVNC_DIR%\tvnserver.exe" (
    call :LogError "TightVNC executable not found"
    exit /b 1
)
call :LogDebug "Executable exists: OK"

sc query %TIGHTVNC_SERVICE% | findstr "RUNNING" >nul 2>&1
if errorlevel 1 (
    call :LogWarn "TightVNC service is not running"
    call :StartTightVNCService
    if errorlevel 1 (
        call :LogError "Could not start TightVNC service"
        exit /b 1
    )
)
call :LogDebug "Service running: OK"

:: Check VNC port is listening
set "WAIT_COUNT=0"
:WaitForPort
netstat -an | findstr ":%VNC_PORT% .*LISTENING" >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :PortListening
timeout /t 2 /nobreak >nul
set /a "WAIT_COUNT+=1"
if %WAIT_COUNT% GTR 15 (
    call :LogError "VNC port %VNC_PORT% is not listening"
    exit /b 1
)
goto :WaitForPort

:PortListening
call :LogDebug "Port %VNC_PORT% listening: OK"
call :LogSuccess "TightVNC verification passed"
exit /b 0

:MarkInstalled
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark TightVNC as installed in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "TightVNCInstalled" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "TightVNCInstallDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "TightVNCPort" /t REG_SZ /d "%VNC_PORT%" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

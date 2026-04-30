@echo off
::==============================================================================
:: 20-install-tightvnc.bat - VNC Server Installation (TigerVNC)
::==============================================================================
:: Installs TigerVNC Server via winget with auto-generated secure password.
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
call "%LOG%" section "VNC Server Installation"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already installed (idempotency)
call :CheckVNCInstalled
if !ERRORLEVEL! EQU 0 (
    call "%LOG%" info "VNC server is already installed"
    call :VerifyVNCService
    if !ERRORLEVEL! EQU 0 (
        call "%LOG%" success "VNC server is installed and running"
        exit /b %EXIT_SUCCESS%
    ) else (
        call "%LOG%" warn "VNC installed but service not running"
        call :StartVNCService
        exit /b !ERRORLEVEL!
    )
)

:: Pre-flight checks
call :PreflightChecks
if errorlevel 1 exit /b %EXIT_PREREQ_FAILED%

:: Generate secure password
call :GeneratePassword
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Install VNC server
call :InstallVNC
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Configure VNC password and settings
call :ConfigureVNC
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Save credentials
call :SaveCredentials

:: Verify installation
call :VerifyInstallation
if errorlevel 1 exit /b %EXIT_VERIFICATION_FAILED%

:: Mark as installed
call :MarkInstalled

call "%LOG%" success "VNC server installation completed successfully"
call "%LOG%" info "VNC credentials saved to: %CREDENTIALS_FILE%"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:CheckVNCInstalled
call "%LOG%" debug "Checking if VNC server is installed..."
if exist "%VNC_DIR%\winvnc4.exe" (
    call "%LOG%" debug "TigerVNC executable found"
    exit /b 0
)
sc query %VNC_SERVICE% >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" debug "VNC service found"
    exit /b 0
)
exit /b 1

:VerifyVNCService
call "%LOG%" debug "Checking VNC service status..."
sc query %VNC_SERVICE% | findstr "RUNNING" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" debug "VNC service is running"
    exit /b 0
)
exit /b 1

:StartVNCService
call "%LOG%" info "Starting VNC service..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would start VNC service
    exit /b 0
)
net start %VNC_SERVICE% >nul 2>&1
if errorlevel 1 (
    call "%LOG%" error "Failed to start VNC service"
    exit /b 1
)
call "%LOG%" success "VNC service started"
exit /b 0

:PreflightChecks
call "%LOG%" info "Running pre-flight checks..."
if "%CONNECTIVITY_CHECKED%"=="1" goto :PreflightDone
ping -n 1 -w 3000 %CONNECTIVITY_CHECK_IP% >nul 2>&1
if errorlevel 1 (
    call "%LOG%" error "No internet connectivity"
    exit /b 1
)
set "CONNECTIVITY_CHECKED=1"
call "%LOG%" debug "Internet connectivity: OK"
:PreflightDone
call "%LOG%" success "Pre-flight checks passed"
exit /b 0

:GeneratePassword
call "%LOG%" info "Generating secure VNC password..."
if "%DRY_RUN%"=="1" (
    set "VNC_PASSWORD=DryRunPassword123"
    echo [DRY-RUN] Would generate %VNC_PASSWORD_LENGTH%-character password
    exit /b 0
)

:: Generate password using PowerShell (safe chars only — no cmd.exe specials)
for /f "delims=" %%P in ('powershell -NoProfile -Command "$c = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789~_-+.'; -join ((1..%VNC_PASSWORD_LENGTH%) | ForEach-Object { $c[(Get-Random -Maximum $c.Length)] })"') do (
    set "VNC_PASSWORD=%%P"
)

if not defined VNC_PASSWORD (
    call "%LOG%" error "Failed to generate password"
    exit /b 1
)

call "%LOG%" debug "Password generated successfully"
exit /b 0

:InstallVNC
call "%LOG%" info "Installing TigerVNC server..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would install TigerVNC via: winget install TigerVNC.TigerVNC
    exit /b 0
)

:: Install via winget
call "%LOG%" debug "Running winget install for TigerVNC..."
winget install TigerVNC.TigerVNC --silent --accept-package-agreements --accept-source-agreements >nul 2>&1

:: Verify executable exists
if exist "%VNC_DIR%\winvnc4.exe" (
    call "%LOG%" success "TigerVNC installed via winget"
) else (
    call "%LOG%" error "TigerVNC installation failed"
    call "%LOG%" info "Try manually: winget install TigerVNC.TigerVNC"
    exit /b 1
)

:: Wait for service registration
call "%LOG%" debug "Waiting for service registration..."
set "WAIT_COUNT=0"
:WaitForServiceReg
sc query %VNC_SERVICE% >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :ServiceRegistered
ping -n 3 127.0.0.1 >nul
set /a "WAIT_COUNT+=1"
if %WAIT_COUNT% GTR 30 (
    call "%LOG%" debug "Service not auto-registered, trying manual registration..."
    "%VNC_DIR%\winvnc4.exe" -register
    ping -n 5 127.0.0.1 >nul
    sc query %VNC_SERVICE% >nul 2>&1
    if errorlevel 1 (
        call "%LOG%" error "Timeout waiting for VNC service registration"
        exit /b 1
    )
)
goto :WaitForServiceReg

:ServiceRegistered
call "%LOG%" debug "Service registered successfully"
exit /b 0

:ConfigureVNC
call "%LOG%" info "Configuring VNC server..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would configure VNC password and settings
    exit /b 0
)

:: Set VNC password via PowerShell (DES encryption per RFB protocol)
:: VNC auth uses a fixed DES key with bit-reversed bytes
call "%LOG%" debug "Setting VNC password..."
powershell -NoProfile -Command ^
    "$pw = $env:VNC_PASSWORD; " ^
    "$k = [byte[]](0xE8,0x4A,0xD6,0x60,0xC4,0x72,0x1A,0xE0); " ^
    "$pb = [byte[]]::new(8); " ^
    "$r = [Text.Encoding]::ASCII.GetBytes($pw); " ^
    "[Array]::Copy($r,$pb,[Math]::Min($r.Length,8)); " ^
    "$d = [Security.Cryptography.DES]::Create(); " ^
    "$d.Mode = 'ECB'; $d.Padding = 'None'; $d.Key = $k; " ^
    "$e = $d.CreateEncryptor().TransformFinalBlock($pb,0,8); " ^
    "$hex = -join ($e | ForEach-Object { '{0:x2}' -f $_ }); " ^
    "reg add 'HKLM\SOFTWARE\TigerVNC\Server' /v Password /t REG_BINARY /d $hex /f | Out-Null; " ^
    "reg add 'HKLM\SOFTWARE\TigerVNC\Server' /v ControlPassword /t REG_BINARY /d $hex /f | Out-Null"

if errorlevel 1 (
    call "%LOG%" error "Failed to set VNC password"
    exit /b 1
)

:: Configure additional server settings
reg add "HKLM\SOFTWARE\TigerVNC\Server" /v SecurityTypes /t REG_SZ /d "VncAuth" /f >nul 2>&1
reg add "HKLM\SOFTWARE\TigerVNC\Server" /v PortNumber /t REG_DWORD /d %VNC_PORT% /f >nul 2>&1
reg add "HKLM\SOFTWARE\TigerVNC\Server" /v AllowLoopback /t REG_DWORD /d 1 /f >nul 2>&1

:: Restart service to pick up new configuration
net stop %VNC_SERVICE% >nul 2>&1
call :StartVNCService
if errorlevel 1 exit /b 1

call "%LOG%" success "VNC server configured"
exit /b 0

:SaveCredentials
call "%LOG%" info "Saving VNC credentials..."

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

:: Restrict credentials file to Administrators and SYSTEM only
icacls "%CREDENTIALS_FILE%" /inheritance:r /grant:r Administrators:F SYSTEM:F >nul 2>&1

call "%LOG%" debug "Credentials saved to: %CREDENTIALS_FILE%"
exit /b 0

:VerifyInstallation
call "%LOG%" info "Verifying VNC installation..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would verify VNC installation
    exit /b 0
)

if not exist "%VNC_DIR%\winvnc4.exe" (
    call "%LOG%" error "VNC executable not found"
    exit /b 1
)
call "%LOG%" debug "Executable exists: OK"

sc query %VNC_SERVICE% | findstr "RUNNING" >nul 2>&1
if errorlevel 1 (
    call "%LOG%" warn "VNC service is not running"
    call :StartVNCService
    if errorlevel 1 (
        call "%LOG%" error "Could not start VNC service"
        exit /b 1
    )
)
call "%LOG%" debug "Service running: OK"

:: Check VNC port is listening
set "WAIT_COUNT=0"
:WaitForPort
netstat -an | findstr ":%VNC_PORT% .*LISTENING" >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :PortListening
ping -n 3 127.0.0.1 >nul
set /a "WAIT_COUNT+=1"
if %WAIT_COUNT% GTR 15 (
    call "%LOG%" error "VNC port %VNC_PORT% is not listening"
    exit /b 1
)
goto :WaitForPort

:PortListening
call "%LOG%" debug "Port %VNC_PORT% listening: OK"
call "%LOG%" success "VNC verification passed"
exit /b 0

:MarkInstalled
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark VNC as installed in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "VNCInstalled" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "VNCInstallDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "VNCPort" /t REG_SZ /d "%VNC_PORT%" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "VNCProvider" /t REG_SZ /d "TigerVNC" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

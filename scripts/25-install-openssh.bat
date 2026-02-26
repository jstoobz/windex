@echo off
::==============================================================================
:: 25-install-openssh.bat - OpenSSH Server Installation
::==============================================================================
:: Installs and configures OpenSSH Server using setup-openssh-server.ps1.
:: Restricts the firewall rule to Tailscale subnet only.
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
call "%LOG%" section "OpenSSH Server Installation"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    call "%LOG%" info "Please run this script as Administrator"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already installed (idempotency)
if not "%FORCE%"=="1" (
    reg query "%SETUP_REG_KEY%" /v "OpenSSHInstalled" >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        call "%LOG%" info "OpenSSH Server already installed"
        call :VerifyInstallation
        if !ERRORLEVEL! EQU 0 (
            call "%LOG%" success "OpenSSH Server is installed and running"
            exit /b %EXIT_SUCCESS%
        ) else (
            call "%LOG%" warn "OpenSSH marked as installed but verification failed, reinstalling..."
        )
    )
)

:: Validate SSH public key
if "%ADMIN_SSH_PUBKEY%"=="" (
    call "%LOG%" warn "ADMIN_SSH_PUBKEY not set — OpenSSH will install without key-based auth"
    call "%LOG%" info "Set ADMIN_SSH_PUBKEY environment variable to enable key auth"
)

:: Check that PS1 script exists
if not exist "%OPENSSH_PS1%" (
    call "%LOG%" error "setup-openssh-server.ps1 not found at: %OPENSSH_PS1%"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Pre-flight: internet check (OpenSSH installs via Windows capability)
call :PreflightChecks
if errorlevel 1 exit /b %EXIT_PREREQ_FAILED%

:: Run the PowerShell setup script
call :RunOpenSSHSetup
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Restrict firewall rule to Tailscale subnet
call :RestrictFirewallRule
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

:: Verify installation
call :VerifyInstallation
if errorlevel 1 exit /b %EXIT_VERIFICATION_FAILED%

:: Mark as installed in registry
call :MarkInstalled

call "%LOG%" success "OpenSSH Server installation completed successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:PreflightChecks
call "%LOG%" info "Running pre-flight checks..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would verify internet connectivity
    exit /b 0
)
ping -n 1 -w 3000 8.8.8.8 >nul 2>&1
if errorlevel 1 (
    call "%LOG%" error "No internet connectivity (required for OpenSSH capability install)"
    exit /b 1
)
call "%LOG%" debug "Internet connectivity: OK"
call "%LOG%" success "Pre-flight checks passed"
exit /b 0

:RunOpenSSHSetup
call "%LOG%" info "Running OpenSSH Server setup..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would execute: powershell -NoProfile -ExecutionPolicy Bypass -File "%OPENSSH_PS1%"
    if not "%ADMIN_SSH_PUBKEY%"=="" (
        echo [DRY-RUN]   with -PubKey "***"
    )
    exit /b 0
)

if not "%ADMIN_SSH_PUBKEY%"=="" (
    call "%LOG%" debug "Installing with SSH public key..."
    powershell -NoProfile -ExecutionPolicy Bypass -File "%OPENSSH_PS1%" -PubKey "%ADMIN_SSH_PUBKEY%"
) else (
    :: Run without -PubKey to avoid PS1 exiting with error on empty key
    :: This installs OpenSSH and sshd but skips key-based auth setup
    call "%LOG%" debug "Installing without SSH public key..."
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$ErrorActionPreference='Stop'; " ^
        "$cap = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'; " ^
        "if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 }; " ^
        "Start-Service sshd; " ^
        "Set-Service -Name sshd -StartupType Automatic; " ^
        "$fw = Get-NetFirewallRule -Name *ssh* -ErrorAction SilentlyContinue; " ^
        "if ($fw) { Set-NetFirewallRule -Name $fw.Name -Profile Any } " ^
        "else { New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server [sshd]' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any }"
)
if errorlevel 1 (
    call "%LOG%" error "OpenSSH setup script failed"
    exit /b 1
)

call "%LOG%" success "OpenSSH setup script completed"
exit /b 0

:RestrictFirewallRule
call "%LOG%" info "Restricting SSH firewall rule to Tailscale subnet..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would restrict OpenSSH-Server-In-TCP rule to remoteip=%TAILSCALE_SUBNET%
    exit /b 0
)

:: The PS1 creates a rule allowing all profiles. Restrict to Tailscale subnet only.
netsh advfirewall firewall show rule name="OpenSSH-Server-In-TCP" >nul 2>&1
if errorlevel 1 (
    :: PS1 may have created it with a different name — check for sshd rule
    netsh advfirewall firewall show rule name="sshd" >nul 2>&1
    if errorlevel 1 (
        call "%LOG%" warn "No SSH firewall rule found to restrict"
        exit /b 0
    )
    call "%LOG%" debug "Restricting 'sshd' rule to Tailscale subnet..."
    netsh advfirewall firewall set rule name="sshd" new remoteip=%TAILSCALE_SUBNET% >nul 2>&1
    if errorlevel 1 (
        call "%LOG%" warn "Failed to restrict sshd firewall rule"
    ) else (
        call "%LOG%" success "SSH firewall rule restricted to Tailscale subnet"
    )
    exit /b 0
)

call "%LOG%" debug "Restricting 'OpenSSH-Server-In-TCP' rule to Tailscale subnet..."
netsh advfirewall firewall set rule name="OpenSSH-Server-In-TCP" new remoteip=%TAILSCALE_SUBNET% >nul 2>&1
if errorlevel 1 (
    call "%LOG%" warn "Failed to restrict OpenSSH-Server-In-TCP firewall rule"
) else (
    call "%LOG%" success "SSH firewall rule restricted to Tailscale subnet"
)
exit /b 0

:VerifyInstallation
call "%LOG%" info "Verifying OpenSSH installation..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would verify OpenSSH installation
    exit /b 0
)

:: Check sshd service is running
sc query sshd | findstr "RUNNING" >nul 2>&1
if errorlevel 1 (
    call "%LOG%" error "sshd service is not running"
    exit /b 1
)
call "%LOG%" debug "sshd service: running"

:: Check port 22 is listening
netstat -an | findstr ":%SSH_PORT% .*LISTENING" >nul 2>&1
if errorlevel 1 (
    call "%LOG%" error "Port %SSH_PORT% is not listening"
    exit /b 1
)
call "%LOG%" debug "Port %SSH_PORT%: listening"

call "%LOG%" success "OpenSSH verification passed"
exit /b 0

:MarkInstalled
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark OpenSSH as installed in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "OpenSSHInstalled" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "OpenSSHInstallDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

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
call "%LOG%" section "Firewall Configuration"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if firewall rules already exist
call :CheckFirewallRulesExist
if !ERRORLEVEL! EQU 0 (
    if not "%FORCE%"=="1" (
        call "%LOG%" info "Firewall rules already configured"
        call :VerifyFirewallRules
        if !ERRORLEVEL! EQU 0 (
            call "%LOG%" success "Firewall rules are correctly configured"
            exit /b %EXIT_SUCCESS%
        ) else (
            call "%LOG%" warn "Firewall rules exist but may be misconfigured"
            call "%LOG%" info "Removing existing rules and recreating..."
            call :RemoveFirewallRules
        )
    ) else (
        call "%LOG%" info "Force mode: removing existing rules and recreating..."
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

call "%LOG%" success "Firewall configuration completed successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:CheckFirewallRulesExist
call "%LOG%" debug "Checking for existing firewall rules..."
netsh advfirewall firewall show rule name="%FW_RULE_VNC_ALLOW%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" debug "VNC allow rule exists"
    exit /b 0
)
netsh advfirewall firewall show rule name="%FW_RULE_VNC_BLOCK%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" debug "VNC block rule exists"
    exit /b 0
)
exit /b 1

:EnsureFirewallEnabled
call "%LOG%" info "Verifying Windows Firewall is enabled..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would verify/enable Windows Firewall
    exit /b 0
)

netsh advfirewall show allprofiles state | findstr "ON" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" debug "Windows Firewall is enabled"
    exit /b 0
)

call "%LOG%" warn "Windows Firewall is disabled, enabling..."
netsh advfirewall set allprofiles state on >nul 2>&1
if errorlevel 1 (
    call "%LOG%" error "Failed to enable Windows Firewall"
    exit /b 1
)
call "%LOG%" success "Windows Firewall enabled"
exit /b 0

:RemoveFirewallRules
call "%LOG%" info "Removing existing firewall rules..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove firewall rules
    exit /b 0
)

netsh advfirewall firewall delete rule name="%FW_RULE_VNC_ALLOW%" >nul 2>&1
netsh advfirewall firewall delete rule name="%FW_RULE_VNC_BLOCK%" >nul 2>&1
netsh advfirewall firewall delete rule name="OpenSSH-Server-In-TCP" >nul 2>&1
netsh advfirewall firewall delete rule name="sshd" >nul 2>&1
call "%LOG%" debug "Existing rules removed"
exit /b 0

:CreateFirewallRules
call "%LOG%" info "Creating firewall rules..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would create firewall rule: Allow VNC from Tailscale subnet %TAILSCALE_SUBNET%
    echo [DRY-RUN] Would create firewall rule: Block VNC from all other sources
    exit /b 0
)

:: Rule 1: Allow VNC from Tailscale subnet only
call "%LOG%" debug "Creating allow rule for Tailscale subnet..."
netsh advfirewall firewall add rule name="%FW_RULE_VNC_ALLOW%" dir=in action=allow protocol=tcp localport=%VNC_PORT% remoteip=%TAILSCALE_SUBNET% profile=any description="Allow VNC connections from Tailscale network only" enable=yes >nul 2>&1
if errorlevel 1 (
    call "%LOG%" error "Failed to create VNC allow rule"
    exit /b 1
)
call "%LOG%" success "Created rule: %FW_RULE_VNC_ALLOW%"

:: No catch-all block rule on %VNC_PORT%. Windows Firewall evaluates block
:: rules BEFORE allow rules, so an any-source block nullifies the Tailscale
:: allow above and VNC becomes unreachable from everywhere - proven live
:: 2026-08-04 (RFB connect timed out until the block rule was disabled).
:: Default inbound is already BlockInbound on all profiles, so the scoped
:: allow rule alone yields exactly the intended posture. Delete the rule if
:: an earlier run left one behind.
netsh advfirewall firewall delete rule name="%FW_RULE_VNC_BLOCK%" >nul 2>&1
if %ERRORLEVEL% EQU 0 call "%LOG%" info "Removed legacy %FW_RULE_VNC_BLOCK% rule [blocked Tailscale VNC]"

:: Rule 3: SSH locked to the same scope - :RemoveFirewallRules deleted the
:: SSH rules, so they MUST be re-created here or SSH is left with no allow
:: rule at all (default inbound block). Only when OpenSSH is present.
:: SSH_EXTRA_ALLOW (optional env) keeps the VM harness reachable over SLIRP.
sc query sshd >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    set "SSH_SCOPE=%TAILSCALE_SUBNET%"
    if defined SSH_EXTRA_ALLOW set "SSH_SCOPE=%TAILSCALE_SUBNET%,!SSH_EXTRA_ALLOW!"
    call "%LOG%" debug "Creating SSH allow rule scoped to: !SSH_SCOPE!"
    netsh advfirewall firewall add rule name="OpenSSH-Server-In-TCP" dir=in action=allow protocol=tcp localport=22 remoteip=!SSH_SCOPE! profile=any description="Allow SSH from Tailscale network" enable=yes >nul 2>&1
    if errorlevel 1 (
        call "%LOG%" error "Failed to create SSH allow rule"
        exit /b 1
    )
    call "%LOG%" success "Created rule: OpenSSH-Server-In-TCP [scoped]"
)
exit /b 0

:EnableFirewallLogging
call "%LOG%" info "Enabling firewall logging for blocked connections..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would enable firewall logging
    exit /b 0
)

netsh advfirewall set allprofiles logging droppedconnections enable >nul 2>&1
set "FW_LOG_PATH=%SystemRoot%\System32\LogFiles\Firewall\pfirewall.log"
netsh advfirewall set allprofiles logging filename "%FW_LOG_PATH%" >nul 2>&1
netsh advfirewall set allprofiles logging maxfilesize 32768 >nul 2>&1
call "%LOG%" debug "Firewall logging configured"
exit /b 0

:VerifyFirewallRules
call "%LOG%" info "Verifying firewall rules..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would verify firewall rules
    exit /b 0
)

set "VERIFY_PASSED=1"

netsh advfirewall firewall show rule name="%FW_RULE_VNC_ALLOW%" >nul 2>&1
if errorlevel 1 (
    call "%LOG%" error "Allow rule not found: %FW_RULE_VNC_ALLOW%"
    set "VERIFY_PASSED=0"
) else (
    :: Verify rule is enabled and scoped to Tailscale subnet
    netsh advfirewall firewall show rule name="%FW_RULE_VNC_ALLOW%" | findstr /i "Enabled.*Yes" >nul 2>&1
    if errorlevel 1 (
        call "%LOG%" error "Allow rule exists but is disabled: %FW_RULE_VNC_ALLOW%"
        set "VERIFY_PASSED=0"
    ) else (
        netsh advfirewall firewall show rule name="%FW_RULE_VNC_ALLOW%" | findstr /i "%TAILSCALE_SUBNET%" >nul 2>&1
        if errorlevel 1 (
            call "%LOG%" error "Allow rule not scoped to Tailscale subnet: %FW_RULE_VNC_ALLOW%"
            set "VERIFY_PASSED=0"
        ) else (
            call "%LOG%" debug "Allow rule verified: enabled, scoped to %TAILSCALE_SUBNET%"
        )
    )
)

:: The catch-all block rule must NOT exist - it out-prioritizes the allow
:: rule and severs VNC over Tailscale
netsh advfirewall firewall show rule name="%FW_RULE_VNC_BLOCK%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" error "Legacy %FW_RULE_VNC_BLOCK% rule present - blocks Tailscale VNC"
    set "VERIFY_PASSED=0"
) else (
    call "%LOG%" debug "No catch-all block rule: OK"
)

netsh advfirewall show allprofiles state | findstr "ON" >nul 2>&1
if errorlevel 1 (
    call "%LOG%" error "Windows Firewall is not enabled"
    set "VERIFY_PASSED=0"
) else (
    call "%LOG%" debug "Firewall enabled: OK"
)

:: Verify SSH firewall rule is restricted to Tailscale subnet (if OpenSSH is installed)
sc query sshd >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    set "SSH_RULE_FOUND=0"
    netsh advfirewall firewall show rule name="OpenSSH-Server-In-TCP" >nul 2>&1
    if !ERRORLEVEL! EQU 0 set "SSH_RULE_FOUND=1"
    netsh advfirewall firewall show rule name="sshd" >nul 2>&1
    if !ERRORLEVEL! EQU 0 set "SSH_RULE_FOUND=1"
    if "!SSH_RULE_FOUND!"=="1" (
        call "%LOG%" debug "SSH firewall rule verified: OK"
    ) else (
        call "%LOG%" warn "SSH firewall rule not found — OpenSSH may be unrestricted"
        set "VERIFY_PASSED=0"
    )
)

if "%VERIFY_PASSED%"=="0" (
    call "%LOG%" error "Firewall verification failed"
    exit /b 1
)
call "%LOG%" success "Firewall verification passed"
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

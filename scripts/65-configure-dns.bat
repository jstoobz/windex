@echo off
::==============================================================================
:: 65-configure-dns.bat - DNS-Level Malware and Phishing Filtering
::==============================================================================
:: Sets DNS servers to Cloudflare Family (1.1.1.3 / 1.0.0.3) on all active
:: network adapters for automatic malware and phishing domain blocking.
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
call "%LOG%" section "DNS Filtering Configuration"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already configured
reg query "%SETUP_REG_KEY%" /v "DnsConfigured" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    if not "%FORCE%"=="1" (
        call "%LOG%" info "DNS filtering already configured"
        call "%LOG%" success "DNS configuration is in place"
        exit /b %EXIT_SUCCESS%
    )
)

call :ConfigureDns
if errorlevel 1 (
    call "%LOG%" error "DNS configuration failed"
    exit /b %EXIT_EXECUTION_FAILED%
)

call :MarkConfigured

call "%LOG%" success "DNS filtering configured successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:: ============================================================================
:: DNS CONFIGURATION
:: ============================================================================

:ConfigureDns
call "%LOG%" info "Setting DNS to %DNS_PRIMARY% / %DNS_SECONDARY% on all adapters..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would set DNS on all active network adapters:
    echo [DRY-RUN]   Primary:   %DNS_PRIMARY% - Cloudflare Family, malware + phishing blocking
    echo [DRY-RUN]   Secondary: %DNS_SECONDARY%
    echo [DRY-RUN] Would use PowerShell Get-NetAdapter to find active adapters
    exit /b 0
)

:: Use PowerShell to set DNS on all active adapters
:: This handles Wi-Fi, Ethernet, and any other connected adapter
powershell -NoProfile -Command ^
    "$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }; " ^
    "foreach ($a in $adapters) { " ^
    "  Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses ('%DNS_PRIMARY%','%DNS_SECONDARY%'); " ^
    "  Write-Host \"  Set DNS on: $($a.Name)\"; " ^
    "}"
if errorlevel 1 (
    call "%LOG%" error "Failed to set DNS via PowerShell"
    exit /b 1
)

:: Verify by checking current DNS
call "%LOG%" debug "Verifying DNS settings..."
powershell -NoProfile -Command ^
    "Get-DnsClientServerAddress -AddressFamily IPv4 | " ^
    "Where-Object { $_.ServerAddresses -contains '%DNS_PRIMARY%' } | " ^
    "Select-Object -First 1 | Out-Null; " ^
    "if ($?) { exit 0 } else { exit 1 }"
if errorlevel 1 (
    call "%LOG%" warn "DNS verification: could not confirm settings applied"
)

call "%LOG%" success "DNS filtering set to Cloudflare Family (%DNS_PRIMARY% / %DNS_SECONDARY%)"
exit /b 0

:: ============================================================================
:: REGISTRY MARKER
:: ============================================================================

:MarkConfigured
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark DNS as configured in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "DnsConfigured" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "DnsConfiguredDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "DnsProvider" /t REG_SZ /d "%DNS_PRIMARY%,%DNS_SECONDARY%" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

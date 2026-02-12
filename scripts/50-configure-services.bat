@echo off
::==============================================================================
:: 50-configure-services.bat - Service Configuration
::==============================================================================
:: Configures Tailscale and TightVNC services for automatic startup
:: and recovery on failure.
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
call "%LOG%" section "Service Configuration"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Configure services
set "CONFIG_ERRORS=0"

call :ConfigureTailscaleService
if errorlevel 1 set /a "CONFIG_ERRORS+=1"

call :ConfigureTightVNCService
if errorlevel 1 set /a "CONFIG_ERRORS+=1"

call :VerifyServiceConfiguration
if errorlevel 1 set /a "CONFIG_ERRORS+=1"

call :MarkConfigured

if %CONFIG_ERRORS% GTR 0 (
    call "%LOG%" warn "Service configuration completed with %CONFIG_ERRORS% warnings"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

call "%LOG%" success "Service configuration completed successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:ConfigureTailscaleService
call "%LOG%" info "Configuring Tailscale service..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would configure Tailscale service for auto-start and recovery
    exit /b 0
)

sc query Tailscale >nul 2>&1
if errorlevel 1 (
    call "%LOG%" warn "Tailscale service not found"
    exit /b 1
)

sc config Tailscale start= auto >nul 2>&1
sc failure Tailscale reset= 86400 actions= restart/60000/restart/60000/restart/60000 >nul 2>&1

sc query Tailscale | findstr "RUNNING" >nul 2>&1
if errorlevel 1 (
    call "%LOG%" debug "Starting Tailscale service..."
    net start Tailscale >nul 2>&1
)

call "%LOG%" success "Tailscale service configured"
exit /b 0

:ConfigureTightVNCService
call "%LOG%" info "Configuring TightVNC service..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would configure TightVNC service for auto-start and recovery
    exit /b 0
)

sc query %TIGHTVNC_SERVICE% >nul 2>&1
if errorlevel 1 (
    call "%LOG%" warn "TightVNC service not found"
    exit /b 1
)

sc config %TIGHTVNC_SERVICE% start= auto >nul 2>&1
sc failure %TIGHTVNC_SERVICE% reset= 86400 actions= restart/60000/restart/60000/restart/60000 >nul 2>&1

sc query %TIGHTVNC_SERVICE% | findstr "RUNNING" >nul 2>&1
if errorlevel 1 (
    call "%LOG%" debug "Starting TightVNC service..."
    net start %TIGHTVNC_SERVICE% >nul 2>&1
)

call "%LOG%" success "TightVNC service configured"
exit /b 0

:VerifyServiceConfiguration
call "%LOG%" info "Verifying service configuration..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would verify service configuration
    exit /b 0
)

set "VERIFY_PASSED=1"

sc qc Tailscale 2>nul | findstr "AUTO_START" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" debug "Tailscale startup type: AUTO (OK)"
) else (
    call "%LOG%" warn "Tailscale may not auto-start"
    set "VERIFY_PASSED=0"
)

sc qc %TIGHTVNC_SERVICE% 2>nul | findstr "AUTO_START" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" debug "TightVNC startup type: AUTO (OK)"
) else (
    call "%LOG%" warn "TightVNC may not auto-start"
    set "VERIFY_PASSED=0"
)

if "%VERIFY_PASSED%"=="0" (
    exit /b 1
)
call "%LOG%" success "Service verification passed"
exit /b 0

:MarkConfigured
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark services as configured in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "ServicesConfigured" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "ServicesConfiguredDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

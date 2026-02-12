@echo off
::==============================================================================
:: 45-configure-power.bat - Power, Sleep, and Windows Update Settings
::==============================================================================
:: Configures power plan for remote access (no sleep on AC) and sets
:: Windows Update active hours to prevent daytime reboots.
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
call "%LOG%" section "Power and Update Configuration"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already configured
reg query "%SETUP_REG_KEY%" /v "PowerConfigured" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    if not "%FORCE%"=="1" (
        call "%LOG%" info "Power settings already configured"
        call "%LOG%" success "Power configuration is in place"
        exit /b %EXIT_SUCCESS%
    )
)

set "CONFIG_ERRORS=0"

call :ConfigurePowerPlan
if errorlevel 1 set /a "CONFIG_ERRORS+=1"

call :ConfigureUpdateHours
if errorlevel 1 set /a "CONFIG_ERRORS+=1"

call :MarkConfigured

if %CONFIG_ERRORS% GTR 0 (
    call "%LOG%" warn "Power configuration completed with %CONFIG_ERRORS% error(s)"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

call "%LOG%" success "Power and update configuration completed successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:: ============================================================================
:: POWER PLAN
:: ============================================================================

:ConfigurePowerPlan
call "%LOG%" info "Configuring power plan..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would set AC sleep timeout to 0 - never
    echo [DRY-RUN] Would set battery sleep timeout to 1800s - 30 min
    echo [DRY-RUN] Would set AC display timeout to 3600s - 60 min
    echo [DRY-RUN] Would set battery display timeout to 600s - 10 min
    echo [DRY-RUN] Would disable hibernate
    exit /b 0
)

:: Never sleep on AC (critical for remote access)
powercfg /change standby-timeout-ac 0
call "%LOG%" debug "AC sleep: never"

:: Sleep after 30 min on battery
powercfg /change standby-timeout-dc 30
call "%LOG%" debug "Battery sleep: 30 min"

:: Display timeout: 60 min on AC, 10 min on battery
powercfg /change monitor-timeout-ac 60
powercfg /change monitor-timeout-dc 10
call "%LOG%" debug "Display timeout: 60 min AC, 10 min battery"

:: Disable hibernate (saves disk space, not needed with remote access)
powercfg /hibernate off
call "%LOG%" debug "Hibernate: off"

:: Ensure lid close on AC does nothing (laptop stays on when lid closed)
powercfg /setacvalueindex scheme_current sub_buttons lidaction 0
powercfg /setactive scheme_current
call "%LOG%" debug "Lid close on AC: do nothing"

call "%LOG%" success "Power plan configured"
exit /b 0

:: ============================================================================
:: WINDOWS UPDATE ACTIVE HOURS
:: ============================================================================

:ConfigureUpdateHours
call "%LOG%" info "Setting Windows Update active hours..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would set active hours: 8:00 - 23:00
    echo [DRY-RUN]   reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v ActiveHoursStart /t REG_DWORD /d 8 /f
    echo [DRY-RUN]   reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v ActiveHoursEnd /t REG_DWORD /d 23 /f
    echo [DRY-RUN]   reg add "HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings" /v IsActiveHoursEnabled /t REG_DWORD /d 1 /f
    exit /b 0
)

set "UPDATE_KEY=HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"

:: Set active hours 8am to 11pm — no restarts during this window
reg add "%UPDATE_KEY%" /v "ActiveHoursStart" /t REG_DWORD /d 8 /f >nul 2>&1
reg add "%UPDATE_KEY%" /v "ActiveHoursEnd" /t REG_DWORD /d 23 /f >nul 2>&1
reg add "%UPDATE_KEY%" /v "IsActiveHoursEnabled" /t REG_DWORD /d 1 /f >nul 2>&1

if errorlevel 1 (
    call "%LOG%" error "Failed to set Windows Update active hours"
    exit /b 1
)

call "%LOG%" success "Windows Update active hours set (8:00 - 23:00)"
exit /b 0

:: ============================================================================
:: REGISTRY MARKER
:: ============================================================================

:MarkConfigured
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark power settings as configured in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "PowerConfigured" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "PowerConfiguredDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

@echo off
::==============================================================================
:: 35-debloat-apps.bat - Consumer Appx Debloat + OEM/AV Trialware Removal
::==============================================================================
:: Removes consumer Appx packages for all users AND deprovisions them so new
:: profiles stay clean, uninstalls OneDrive (with a stranded-files guard), and
:: sweeps OEM/AV trialware. Runs BEFORE user creation so the standard user's
:: profile never inherits bloat. Heavy lifting lives in debloat-apps.ps1.
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
call "%LOG%" section "App Debloat and Trialware Removal"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already debloated
reg query "%SETUP_REG_KEY%" /v "AppsDebloated" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    if not "%FORCE%"=="1" (
        call "%LOG%" info "Apps already debloated"
        call "%LOG%" success "App debloat is in place"
        exit /b %EXIT_SUCCESS%
    )
    call "%LOG%" info "Re-running debloat [--force]"
)

set "DEBLOAT_PS1=%SCRIPT_DIR%\debloat-apps.ps1"
if not exist "%DEBLOAT_PS1%" (
    call "%LOG%" error "Missing companion script: %DEBLOAT_PS1%"
    exit /b %EXIT_PREREQ_FAILED%
)

set "PS_ARGS="
if "%DRY_RUN%"=="1" set "PS_ARGS=-DryRun"

call "%LOG%" info "Removing consumer Appx packages, OneDrive, and trialware..."
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEBLOAT_PS1%" %PS_ARGS%
set "PS_RESULT=!ERRORLEVEL!"

if !PS_RESULT! EQU 0 (
    call :MarkDebloated
    call "%LOG%" success "App debloat completed successfully"
    exit /b %EXIT_SUCCESS%
)

:: No marker on partial success - the next run retries what was skipped,
:: e.g. OneDrive removal held back by the stranded-files guard.
if !PS_RESULT! EQU 5 (
    call "%LOG%" warn "App debloat completed with warnings - will retry remainder on next run"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

call "%LOG%" error "App debloat failed [exit code !PS_RESULT!]"
exit /b %EXIT_EXECUTION_FAILED%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:MarkDebloated
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark apps as debloated in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "AppsDebloated" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "AppsDebloatedDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
exit /b 0

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

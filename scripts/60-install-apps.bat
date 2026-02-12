@echo off
::==============================================================================
:: 60-install-apps.bat - Essential Application Installation
::==============================================================================
:: Installs Chrome, iTunes, and Malwarebytes via winget.
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
call "%LOG%" section "Essential Application Installation"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already completed
reg query "%SETUP_REG_KEY%" /v "AppsInstalled" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    if not "%FORCE%"=="1" (
        call "%LOG%" info "Essential apps already installed"
        call "%LOG%" success "App installation is complete"
        exit /b %EXIT_SUCCESS%
    )
)

:: Install each application
set "APP_ERRORS=0"

call :InstallChrome
if errorlevel 1 set /a "APP_ERRORS+=1"

call :InstallITunes
if errorlevel 1 set /a "APP_ERRORS+=1"

call :InstallMalwarebytes
if errorlevel 1 set /a "APP_ERRORS+=1"

:: Mark as installed
call :MarkInstalled

if %APP_ERRORS% GTR 0 (
    call "%LOG%" warn "App installation completed with %APP_ERRORS% error(s)"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

call "%LOG%" success "All essential apps installed successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:: ============================================================================
:: CHROME
:: ============================================================================

:InstallChrome
call "%LOG%" info "Installing Google Chrome..."

if exist "%CHROME_EXE%" (
    call "%LOG%" info "Google Chrome is already installed"
    call "%LOG%" success "Chrome: OK"
    exit /b 0
)

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would execute: winget install --id Google.Chrome --exact --silent --accept-package-agreements --accept-source-agreements
    exit /b 0
)

call "%LOG%" debug "Running winget install for Google Chrome..."
winget install --id Google.Chrome --exact --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
    call "%LOG%" error "Failed to install Google Chrome via winget"
    exit /b 1
)

:: Verify
if exist "%CHROME_EXE%" (
    call "%LOG%" success "Google Chrome installed successfully"
    exit /b 0
)

call "%LOG%" error "Chrome executable not found after install"
exit /b 1

:: ============================================================================
:: ITUNES
:: ============================================================================

:InstallITunes
call "%LOG%" info "Installing Apple iTunes..."

if exist "%ITUNES_EXE%" (
    call "%LOG%" info "Apple iTunes is already installed"
    call "%LOG%" success "iTunes: OK"
    exit /b 0
)

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would execute: winget install --id Apple.iTunes --exact --silent --accept-package-agreements --accept-source-agreements
    exit /b 0
)

call "%LOG%" debug "Running winget install for Apple iTunes..."
winget install --id Apple.iTunes --exact --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
    call "%LOG%" error "Failed to install Apple iTunes via winget"
    exit /b 1
)

:: Verify
if exist "%ITUNES_EXE%" (
    call "%LOG%" success "Apple iTunes installed successfully"
    exit /b 0
)

call "%LOG%" error "iTunes executable not found after install"
exit /b 1

:: ============================================================================
:: MALWAREBYTES
:: ============================================================================

:InstallMalwarebytes
call "%LOG%" info "Installing Malwarebytes..."

if exist "%MALWAREBYTES_EXE%" (
    call "%LOG%" info "Malwarebytes is already installed"
    call "%LOG%" success "Malwarebytes: OK"
    exit /b 0
)

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would execute: winget install --id Malwarebytes.Malwarebytes --exact --silent --accept-package-agreements --accept-source-agreements
    exit /b 0
)

call "%LOG%" debug "Running winget install for Malwarebytes..."
winget install --id Malwarebytes.Malwarebytes --exact --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
    call "%LOG%" error "Failed to install Malwarebytes via winget"
    exit /b 1
)

:: Verify
if exist "%MALWAREBYTES_EXE%" (
    call "%LOG%" success "Malwarebytes installed successfully"
    exit /b 0
)

call "%LOG%" error "Malwarebytes executable not found after install"
exit /b 1

:: ============================================================================
:: REGISTRY MARKER
:: ============================================================================

:MarkInstalled
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark apps as installed in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "AppsInstalled" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "AppsInstallDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

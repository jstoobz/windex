@echo off
::==============================================================================
:: 60-install-apps.bat - Essential Application Installation
::==============================================================================
:: Installs Chrome, iTunes, Malwarebytes, and Rufus via winget.
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

:: Ensure winget source is initialized (required on fresh installs)
call :InitWingetSource
if errorlevel 1 (
    call "%LOG%" error "Failed to initialize winget source"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Install each application
set "APP_ERRORS=0"

call :InstallChrome
if errorlevel 1 set /a "APP_ERRORS+=1"

call :InstallITunes
if errorlevel 1 set /a "APP_ERRORS+=1"

call :InstallMalwarebytes
if errorlevel 1 set /a "APP_ERRORS+=1"

call :InstallRufus
if errorlevel 1 set /a "APP_ERRORS+=1"

:: Mark as installed
call :MarkInstalled

if %APP_ERRORS% GTR 0 (
    call "%LOG%" warn "App installation completed with %APP_ERRORS% errors"
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
    echo [DRY-RUN] Would install Google Chrome via winget or direct MSI download
    exit /b 0
)

:: Try winget first
call "%LOG%" debug "Trying winget install for Google Chrome..."
winget install --id Google.Chrome --exact --silent --accept-package-agreements --accept-source-agreements >nul 2>&1

:: Check if winget actually installed it
if exist "%CHROME_EXE%" (
    call "%LOG%" success "Google Chrome installed via winget"
    exit /b 0
)

:: Winget failed or hash mismatch — fall back to direct MSI download
call "%LOG%" info "Winget install incomplete, downloading Chrome MSI directly..."
set "CHROME_MSI=%TEMP%\chrome-setup.msi"
powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%CHROME_MSI_URL%' -OutFile '%CHROME_MSI%' -UseBasicParsing"
if errorlevel 1 (
    call "%LOG%" error "Failed to download Chrome MSI"
    exit /b 1
)

call "%LOG%" debug "Installing Chrome MSI..."
msiexec /i "%CHROME_MSI%" /quiet /norestart
set "MSI_RESULT=%ERRORLEVEL%"
del "%CHROME_MSI%" 2>nul

if %MSI_RESULT% NEQ 0 if %MSI_RESULT% NEQ 3010 (
    call "%LOG%" error "Chrome MSI install failed with code %MSI_RESULT%"
    exit /b 1
)

:: Verify
if exist "%CHROME_EXE%" (
    call "%LOG%" success "Google Chrome installed via direct download"
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

:: Skip on ARM64 — winget package unavailable (exit code 200), direct installer untested
powershell -NoProfile -Command "if ((Get-CimInstance Win32_Processor).Architecture -eq 12) { exit 1 }" >nul 2>&1
if errorlevel 1 (
    call "%LOG%" warn "Malwarebytes ARM64 not available via winget — install manually from malwarebytes.com"
    exit /b 0
)

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would execute: winget install --id Malwarebytes.Malwarebytes --exact --silent --accept-package-agreements --accept-source-agreements
    exit /b 0
)

call "%LOG%" debug "Running winget install for Malwarebytes..."
winget install --id Malwarebytes.Malwarebytes --exact --silent --accept-package-agreements --accept-source-agreements

:: Check if winget actually installed it
if exist "%MALWAREBYTES_EXE%" (
    call "%LOG%" success "Malwarebytes installed via winget"
    exit /b 0
)

:: Winget failed — fall back to direct download
call "%LOG%" info "Winget install failed, downloading Malwarebytes directly..."
set "MB_SETUP=%TEMP%\MBSetup.exe"
powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%MALWAREBYTES_URL%' -OutFile '%MB_SETUP%' -UseBasicParsing"
if errorlevel 1 (
    call "%LOG%" warn "Failed to download Malwarebytes — install manually from malwarebytes.com"
    exit /b 0
)

call "%LOG%" debug "Running Malwarebytes installer..."
"%MB_SETUP%" /VERYSILENT /NORESTART
del "%MB_SETUP%" 2>nul

:: Verify after direct download
if exist "%MALWAREBYTES_EXE%" (
    call "%LOG%" success "Malwarebytes installed via direct download"
    exit /b 0
)

call "%LOG%" warn "Malwarebytes not found after install — install manually from malwarebytes.com"
exit /b 0

:: ============================================================================
:: RUFUS (USB format / bootable-media tool)
:: ============================================================================

:InstallRufus
call "%LOG%" info "Installing Rufus (USB format tool)..."

if exist "%RUFUS_EXE%" (
    call "%LOG%" info "Rufus is already installed"
    call "%LOG%" success "Rufus: OK"
    exit /b 0
)

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would execute: winget install --id %RUFUS_WINGET_ID% --scope machine --exact --silent --accept-package-agreements --accept-source-agreements
    echo [DRY-RUN] Would create All-Users Start Menu shortcut at %RUFUS_SHORTCUT%
    exit /b 0
)

:: Machine scope: apps install before the standard user exists, so a per-user
:: install would land in the admin profile. Machine scope reaches every user.
call "%LOG%" debug "Running winget install for Rufus (machine scope)..."
winget install --id %RUFUS_WINGET_ID% --scope machine --exact --silent --accept-package-agreements --accept-source-agreements >nul 2>&1

if not exist "%RUFUS_EXE%" (
    call "%LOG%" warn "Rufus not found after winget install - install manually from rufus.ie"
    exit /b 0
)

:: All-Users Start Menu shortcut so the standard (non-admin) user can find it
call :CreateRufusShortcut

call "%LOG%" success "Rufus installed via winget"
exit /b 0

:CreateRufusShortcut
if "%DRY_RUN%"=="1" goto :eof
if exist "%RUFUS_SHORTCUT%" goto :eof
powershell -NoProfile -Command "$s = (New-Object -ComObject WScript.Shell).CreateShortcut('%RUFUS_SHORTCUT%'); $s.TargetPath = '%RUFUS_EXE%'; $s.Description = 'Create bootable USB drives and format large drives as FAT32'; $s.Save()" >nul 2>&1
goto :eof

:: ============================================================================
:: WINGET SOURCE INITIALIZATION
:: ============================================================================

:InitWingetSource
call "%LOG%" info "Initializing winget package source..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would initialize winget source via MSIX package
    exit /b 0
)

:: Test if winget source is already working
winget search --id Microsoft.PowerToys --exact --source winget --count 1 >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" debug "Winget source is already working"
    exit /b 0
)

:: Source is broken — install the MSIX source package directly
call "%LOG%" debug "Winget source not functional, installing source MSIX..."
powershell -NoProfile -Command "Add-AppxPackage -Path 'https://cdn.winget.microsoft.com/cache/source.msix'" 2>nul
if errorlevel 1 (
    call "%LOG%" warn "MSIX install returned error, trying source reset..."
    winget source reset --force >nul 2>&1
    winget source update >nul 2>&1
)

:: Verify it works now
winget search --id Microsoft.PowerToys --exact --source winget --count 1 >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call "%LOG%" success "Winget source initialized"
    exit /b 0
)

call "%LOG%" error "Winget source still not functional after initialization"
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

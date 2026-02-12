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
call :LogSection "Essential Application Installation"

:: Check for admin privileges
call :CheckAdmin
if errorlevel 1 (
    call :LogError "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already completed
reg query "%SETUP_REG_KEY%" /v "AppsInstalled" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    if not "%FORCE%"=="1" (
        call :LogInfo "Essential apps already installed"
        call :LogSuccess "App installation is complete"
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
    call :LogWarn "App installation completed with %APP_ERRORS% error(s)"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

call :LogSuccess "All essential apps installed successfully"
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
    echo ============================================================ >> "%LOG_FILE%"
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

:: ============================================================================
:: CHROME
:: ============================================================================

:InstallChrome
call :LogInfo "Installing Google Chrome..."

if exist "%CHROME_EXE%" (
    call :LogInfo "Google Chrome is already installed"
    call :LogSuccess "Chrome: OK"
    exit /b 0
)

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would execute: winget install --id Google.Chrome --exact --silent --accept-package-agreements --accept-source-agreements
    exit /b 0
)

call :LogDebug "Running winget install for Google Chrome..."
winget install --id Google.Chrome --exact --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
    call :LogError "Failed to install Google Chrome via winget"
    exit /b 1
)

:: Verify
if exist "%CHROME_EXE%" (
    call :LogSuccess "Google Chrome installed successfully"
    exit /b 0
)

call :LogError "Chrome executable not found after install"
exit /b 1

:: ============================================================================
:: ITUNES
:: ============================================================================

:InstallITunes
call :LogInfo "Installing Apple iTunes..."

if exist "%ITUNES_EXE%" (
    call :LogInfo "Apple iTunes is already installed"
    call :LogSuccess "iTunes: OK"
    exit /b 0
)

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would execute: winget install --id Apple.iTunes --exact --silent --accept-package-agreements --accept-source-agreements
    exit /b 0
)

call :LogDebug "Running winget install for Apple iTunes..."
winget install --id Apple.iTunes --exact --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
    call :LogError "Failed to install Apple iTunes via winget"
    exit /b 1
)

:: Verify
if exist "%ITUNES_EXE%" (
    call :LogSuccess "Apple iTunes installed successfully"
    exit /b 0
)

call :LogError "iTunes executable not found after install"
exit /b 1

:: ============================================================================
:: MALWAREBYTES
:: ============================================================================

:InstallMalwarebytes
call :LogInfo "Installing Malwarebytes..."

if exist "%MALWAREBYTES_EXE%" (
    call :LogInfo "Malwarebytes is already installed"
    call :LogSuccess "Malwarebytes: OK"
    exit /b 0
)

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would execute: winget install --id Malwarebytes.Malwarebytes --exact --silent --accept-package-agreements --accept-source-agreements
    exit /b 0
)

call :LogDebug "Running winget install for Malwarebytes..."
winget install --id Malwarebytes.Malwarebytes --exact --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
    call :LogError "Failed to install Malwarebytes via winget"
    exit /b 1
)

:: Verify
if exist "%MALWAREBYTES_EXE%" (
    call :LogSuccess "Malwarebytes installed successfully"
    exit /b 0
)

call :LogError "Malwarebytes executable not found after install"
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

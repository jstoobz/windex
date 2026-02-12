@echo off
::==============================================================================
:: 80-create-standard-user.bat - Create Standard User Account
::==============================================================================
:: Creates a standard (non-admin) user account for daily use. The admin
:: account stays available for provisioning and maintenance.
::
:: Usage:
::   80-create-standard-user.bat --username=NAME --password=PASS [--dry-run]
::
:: The password is temporary — the user will be prompted to change it on
:: first login.
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
echo %~1 | findstr /i "^--username=" >nul
if not errorlevel 1 (
    for /f "tokens=1,* delims==" %%A in ("%~1") do set "STD_USERNAME=%%B"
)
echo %~1 | findstr /i "^--password=" >nul
if not errorlevel 1 (
    for /f "tokens=1,* delims==" %%A in ("%~1") do set "STD_PASSWORD=%%B"
)
shift
goto :ParseArgs
:ParseArgsDone

:: ============================================================================
:: MAIN EXECUTION
:: ============================================================================
call :LogSection "Standard User Account Creation"

:: Check for admin privileges
call :CheckAdmin
if errorlevel 1 (
    call :LogError "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Validate inputs
if not defined STD_USERNAME (
    if not defined STANDARD_USERNAME (
        call :LogError "Username is required"
        call :LogInfo "Usage: %~nx0 --username=NAME --password=PASS"
        call :LogInfo "Or set STANDARD_USERNAME and STANDARD_PASSWORD in config.bat"
        exit /b %EXIT_PREREQ_FAILED%
    )
    set "STD_USERNAME=%STANDARD_USERNAME%"
)

if not defined STD_PASSWORD (
    if not defined STANDARD_PASSWORD (
        call :LogError "Password is required"
        call :LogInfo "Usage: %~nx0 --username=NAME --password=PASS"
        exit /b %EXIT_PREREQ_FAILED%
    )
    set "STD_PASSWORD=%STANDARD_PASSWORD%"
)

:: Check if user already exists
net user "%STD_USERNAME%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    if not "%FORCE%"=="1" (
        call :LogInfo "User '%STD_USERNAME%' already exists"
        call :LogSuccess "Standard user account is in place"
        exit /b %EXIT_SUCCESS%
    )
)

call :CreateUser
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

call :ConfigureUser
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

call :MarkConfigured

call :LogSuccess "Standard user account '%STD_USERNAME%' created successfully"
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
:: CREATE USER
:: ============================================================================

:CreateUser
call :LogInfo "Creating standard user account '%STD_USERNAME%'..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would create user: net user "%STD_USERNAME%" *** /add
    echo [DRY-RUN] Would set full name and password-change-on-login
    exit /b 0
)

:: Create the user account
net user "%STD_USERNAME%" "%STD_PASSWORD%" /add
if errorlevel 1 (
    call :LogError "Failed to create user '%STD_USERNAME%'"
    exit /b 1
)

call :LogSuccess "User account '%STD_USERNAME%' created"
exit /b 0

:: ============================================================================
:: CONFIGURE USER
:: ============================================================================

:ConfigureUser
call :LogInfo "Configuring user account..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would add user to 'Users' group (standard, non-admin)
    echo [DRY-RUN] Would set password to expire (force change on first login)
    echo [DRY-RUN] Would set auto-login for the standard user
    exit /b 0
)

:: Ensure user is NOT in Administrators group (standard user only)
net localgroup Administrators "%STD_USERNAME%" /delete >nul 2>&1

:: Ensure user IS in Users group
net localgroup Users "%STD_USERNAME%" /add >nul 2>&1

:: Force password change on next login
net user "%STD_USERNAME%" /logonpasswordchg:yes >nul 2>&1
call :LogDebug "Password change required on next login"

:: Set auto-login to the standard user account
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "AutoAdminLogon" /t REG_SZ /d "1" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultUserName" /t REG_SZ /d "%STD_USERNAME%" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultPassword" /t REG_SZ /d "%STD_PASSWORD%" /f >nul 2>&1
call :LogDebug "Auto-login configured for '%STD_USERNAME%'"

call :LogSuccess "User '%STD_USERNAME%' configured as standard user with auto-login"
exit /b 0

:: ============================================================================
:: REGISTRY MARKER
:: ============================================================================

:MarkConfigured
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark standard user as created in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "StandardUserCreated" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "StandardUserName" /t REG_SZ /d "%STD_USERNAME%" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "StandardUserDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

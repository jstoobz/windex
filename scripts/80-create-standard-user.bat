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
call "%LOG%" section "Standard User Account Creation"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Validate inputs
if not defined STD_USERNAME (
    if not defined STANDARD_USERNAME (
        call "%LOG%" error "Username is required"
        call "%LOG%" info "Usage: %~nx0 --username=NAME --password=PASS"
        call "%LOG%" info "Or set STANDARD_USERNAME and STANDARD_PASSWORD in config.bat"
        exit /b %EXIT_PREREQ_FAILED%
    )
    set "STD_USERNAME=%STANDARD_USERNAME%"
)

if not defined STD_PASSWORD (
    if not defined STANDARD_PASSWORD (
        call "%LOG%" error "Password is required"
        call "%LOG%" info "Usage: %~nx0 --username=NAME --password=PASS"
        exit /b %EXIT_PREREQ_FAILED%
    )
    set "STD_PASSWORD=%STANDARD_PASSWORD%"
)

:: Check if user already exists
net user "%STD_USERNAME%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    if not "%FORCE%"=="1" (
        call "%LOG%" info "User '%STD_USERNAME%' already exists"
        call "%LOG%" success "Standard user account is in place"
        exit /b %EXIT_SUCCESS%
    )
)

call :ScrubOrphanProfiles

call :CreateUser
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

call :ConfigureUser
if errorlevel 1 exit /b %EXIT_EXECUTION_FAILED%

call :ClearAutoLogon

call :MarkConfigured

call "%LOG%" success "Standard user account '%STD_USERNAME%' created successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:: ============================================================================
:: SCRUB ORPHANED PROFILES
:: ============================================================================
:: Defense for the duplicate lock-screen tile bug: a prior provisioning run
:: (or OEM setup) can leave a C:\Users\<name> profile whose SAM account was
:: deleted. Creating a new account then yields C:\Users\<name>.<COMPUTERNAME>
:: plus a second ProfileList entry -> two identical tiles. Remove any profile
:: under C:\Users\<name>* whose SID has NO live local account. The SID-orphan
:: check is the safety net -- a live account's profile is never touched.
:: Best-effort -- never fails user creation.
:: ============================================================================

:ScrubOrphanProfiles
call "%LOG%" info "Checking for orphaned profiles from prior runs..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove C:\Users\%STD_USERNAME%* profiles whose SID has no local account
    exit /b 0
)
powershell -NoProfile -Command "$u='%STD_USERNAME%'; Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -like ('C:\Users\'+$u+'*') } | Where-Object { -not (Get-LocalUser -SID $_.SID -ErrorAction SilentlyContinue) } | Remove-CimInstance -ErrorAction SilentlyContinue" >nul 2>&1
call "%LOG%" success "Orphaned profile check complete"
exit /b 0

:: ============================================================================
:: CREATE USER
:: ============================================================================

:CreateUser
call "%LOG%" info "Creating standard user account '%STD_USERNAME%'..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would create user: net user "%STD_USERNAME%" *** /add
    echo [DRY-RUN] Would set full name and password-change-on-login
    exit /b 0
)

:: Create the user account
net user "%STD_USERNAME%" "%STD_PASSWORD%" /add
if errorlevel 1 (
    call "%LOG%" error "Failed to create user '%STD_USERNAME%'"
    exit /b 1
)

call "%LOG%" success "User account '%STD_USERNAME%' created"
exit /b 0

:: ============================================================================
:: CONFIGURE USER
:: ============================================================================

:ConfigureUser
call "%LOG%" info "Configuring user account..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would add user to 'Users' group - standard, non-admin
    echo [DRY-RUN] Would set password to expire - force change on first login
    exit /b 0
)

:: Ensure user is NOT in Administrators group (standard user only)
net localgroup Administrators "%STD_USERNAME%" /delete >nul 2>&1

:: Ensure user IS in Users group
net localgroup Users "%STD_USERNAME%" /add >nul 2>&1

:: Force password change on next login (the password arg is required — without
:: it the /logonpasswordchg flag silently no-ops on Windows 11)
net user "%STD_USERNAME%" "%STD_PASSWORD%" /logonpasswordchg:yes >nul 2>&1
call "%LOG%" debug "Password change required on next login"

call "%LOG%" success "User '%STD_USERNAME%' configured as standard user"
exit /b 0

:: ============================================================================
:: CLEAR AUTO-LOGON
:: ============================================================================
:: Removes AutoAdminLogon/DefaultPassword left behind by OEM OOBE or a prior
:: provisioning run. Stale auto-logon racing a Windows Update reboot can orphan
:: ProfileList entries (duplicate lock-screen tiles) and leaves the account's
:: real password unknown to the user. Best-effort — never fails user creation.
:: ============================================================================

:ClearAutoLogon
call "%LOG%" info "Clearing any auto-logon configuration..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would clear AutoAdminLogon/DefaultPassword/DefaultUserName/DefaultDomainName
    exit /b 0
)
set "WINLOGON=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
reg add    "%WINLOGON%" /v "AutoAdminLogon" /t REG_SZ /d "0" /f >nul 2>&1
reg delete "%WINLOGON%" /v "DefaultPassword" /f >nul 2>&1
reg delete "%WINLOGON%" /v "DefaultUserName" /f >nul 2>&1
reg delete "%WINLOGON%" /v "DefaultDomainName" /f >nul 2>&1
call "%LOG%" success "Auto-logon disabled"
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

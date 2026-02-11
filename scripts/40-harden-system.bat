@echo off
::==============================================================================
:: 40-harden-system.bat - Windows Security Hardening
::==============================================================================
:: Applies security hardening settings for remote access deployment.
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
call :LogSection "System Security Hardening"

:: Check for admin privileges
call :CheckAdmin
if errorlevel 1 (
    call :LogError "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already hardened
reg query "%SETUP_REG_KEY%" /v "SystemHardened" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogInfo "System hardening already applied"
    call :LogSuccess "System hardening is in place"
    exit /b %EXIT_SUCCESS%
)

:: Apply hardening measures
set "HARDEN_ERRORS=0"

call :BackupRegistry
call :DisableRemoteAssistance
if errorlevel 1 set /a "HARDEN_ERRORS+=1"

call :ReduceTelemetry
if errorlevel 1 set /a "HARDEN_ERRORS+=1"

call :DisableUnnecessaryServices
if errorlevel 1 set /a "HARDEN_ERRORS+=1"

call :VerifyWindowsDefender
if errorlevel 1 set /a "HARDEN_ERRORS+=1"

call :DisableAutoplay
if errorlevel 1 set /a "HARDEN_ERRORS+=1"

:: Mark as hardened
call :MarkHardened

if %HARDEN_ERRORS% GTR 0 (
    call :LogWarn "System hardening completed with %HARDEN_ERRORS% warnings"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

call :LogSuccess "System hardening completed successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:LogSection
echo.
echo ============================================================
echo %~1
echo ============================================================
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

:BackupRegistry
call :LogInfo "Backing up registry keys..."
set "BACKUP_DIR=%OUTPUT_DIR%\registry-backup"
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would backup registry to: %BACKUP_DIR%
    exit /b 0
)
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%" 2>nul
reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "%BACKUP_DIR%\DataCollection.reg" /y >nul 2>&1
reg export "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance" "%BACKUP_DIR%\RemoteAssistance.reg" /y >nul 2>&1
call :LogDebug "Registry backup saved to: %BACKUP_DIR%"
exit /b 0

:DisableRemoteAssistance
call :LogInfo "Disabling Remote Assistance..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would disable Remote Assistance
    exit /b 0
)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance" /v "fAllowToGetHelp" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Remote Assistance" /v "fAllowFullControl" /t REG_DWORD /d 0 /f >nul 2>&1
call :LogSuccess "Remote Assistance disabled"
exit /b 0

:ReduceTelemetry
call :LogInfo "Reducing telemetry..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would reduce telemetry settings
    exit /b 0
)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows" /v "CEIPEnable" /t REG_DWORD /d 0 /f >nul 2>&1
call :LogSuccess "Telemetry reduced to minimum"
exit /b 0

:DisableUnnecessaryServices
call :LogInfo "Reviewing unnecessary services..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would review and disable unnecessary services
    exit /b 0
)
sc query RemoteRegistry >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    sc config RemoteRegistry start= disabled >nul 2>&1
    sc stop RemoteRegistry >nul 2>&1
    call :LogSuccess "RemoteRegistry service disabled"
)
exit /b 0

:VerifyWindowsDefender
call :LogInfo "Verifying Windows Defender status..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would verify Windows Defender is enabled
    exit /b 0
)
sc query WinDefend | findstr "RUNNING" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    call :LogSuccess "Windows Defender is running"
    exit /b 0
)
call :LogWarn "Windows Defender may not be running"
exit /b 1

:DisableAutoplay
call :LogInfo "Disabling Autoplay..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would disable Autoplay
    exit /b 0
)
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "NoDriveTypeAutoRun" /t REG_DWORD /d 255 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "NoAutorun" /t REG_DWORD /d 1 /f >nul 2>&1
call :LogSuccess "Autoplay disabled"
exit /b 0

:MarkHardened
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark system as hardened in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "SystemHardened" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "SystemHardenedDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

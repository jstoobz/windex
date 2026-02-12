@echo off
::==============================================================================
:: 75-customize-desktop.bat - Desktop and Start Menu Customization
::==============================================================================
:: Removes Win11 bloatware pins, creates desktop shortcuts for essential
:: apps, and pins them to the taskbar.
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
call "%LOG%" section "Desktop and Start Menu Customization"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already customized
reg query "%SETUP_REG_KEY%" /v "DesktopCustomized" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    if not "%FORCE%"=="1" (
        call "%LOG%" info "Desktop already customized"
        call "%LOG%" success "Desktop customization is in place"
        exit /b %EXIT_SUCCESS%
    )
)

set "CUSTOM_ERRORS=0"

call :RemoveBloatwarePins
if errorlevel 1 set /a "CUSTOM_ERRORS+=1"

call :CreateDesktopShortcuts
if errorlevel 1 set /a "CUSTOM_ERRORS+=1"

call :MarkCustomized

if %CUSTOM_ERRORS% GTR 0 (
    call "%LOG%" warn "Desktop customization completed with %CUSTOM_ERRORS% error(s)"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

call "%LOG%" success "Desktop customization completed successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:: ============================================================================
:: REMOVE BLOATWARE PINS
:: ============================================================================

:RemoveBloatwarePins
call "%LOG%" info "Removing bloatware Start menu pins..."

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would remove provisioned appx packages (bloatware):
    echo [DRY-RUN]   Clipchamp, BingNews, BingWeather, GetHelp, Getstarted
    echo [DRY-RUN]   MicrosoftSolitaireCollection, MicrosoftStickyNotes
    echo [DRY-RUN]   People, PowerAutomate, Todos, WindowsFeedbackHub
    echo [DRY-RUN]   ZuneMusic, ZuneVideo, OutlookForWindows
    exit /b 0
)

:: Remove common Win11 bloatware appx packages
:: These are provisioned packages — removing them unpins from Start and
:: prevents reinstall for new users
set "BLOAT_PACKAGES=Clipchamp.Clipchamp Microsoft.BingNews Microsoft.BingWeather"
set "BLOAT_PACKAGES=%BLOAT_PACKAGES% Microsoft.GetHelp Microsoft.Getstarted"
set "BLOAT_PACKAGES=%BLOAT_PACKAGES% Microsoft.MicrosoftSolitaireCollection"
set "BLOAT_PACKAGES=%BLOAT_PACKAGES% Microsoft.MicrosoftStickyNotes"
set "BLOAT_PACKAGES=%BLOAT_PACKAGES% Microsoft.People Microsoft.PowerAutomateDesktop"
set "BLOAT_PACKAGES=%BLOAT_PACKAGES% Microsoft.Todos Microsoft.WindowsFeedbackHub"
set "BLOAT_PACKAGES=%BLOAT_PACKAGES% Microsoft.ZuneMusic Microsoft.ZuneVideo"
set "BLOAT_PACKAGES=%BLOAT_PACKAGES% Microsoft.OutlookForWindows"

for %%P in (%BLOAT_PACKAGES%) do (
    call "%LOG%" debug "Removing: %%P"
    powershell -NoProfile -Command "Get-AppxPackage -AllUsers '%%P' | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue" >nul 2>&1
    powershell -NoProfile -Command "Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq '%%P' | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue" >nul 2>&1
)

call "%LOG%" success "Bloatware packages removed"
exit /b 0

:: ============================================================================
:: DESKTOP SHORTCUTS
:: ============================================================================

:CreateDesktopShortcuts
call "%LOG%" info "Creating desktop shortcuts..."

set "PUBLIC_DESKTOP=C:\Users\Public\Desktop"

if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would create shortcuts on %PUBLIC_DESKTOP%:
    if exist "%CHROME_EXE%" echo [DRY-RUN]   Google Chrome.lnk
    if exist "%ITUNES_EXE%" echo [DRY-RUN]   iTunes.lnk
    exit /b 0
)

:: Create Chrome shortcut
if exist "%CHROME_EXE%" (
    if not exist "%PUBLIC_DESKTOP%\Google Chrome.lnk" (
        powershell -NoProfile -Command ^
            "$ws = New-Object -ComObject WScript.Shell; " ^
            "$s = $ws.CreateShortcut('%PUBLIC_DESKTOP%\Google Chrome.lnk'); " ^
            "$s.TargetPath = '%CHROME_EXE%'; " ^
            "$s.Save()"
        if errorlevel 1 (
            call "%LOG%" warn "Failed to create Chrome desktop shortcut"
        ) else (
            call "%LOG%" debug "Created Chrome desktop shortcut"
        )
    ) else (
        call "%LOG%" debug "Chrome shortcut already exists"
    )
) else (
    call "%LOG%" debug "Chrome not installed, skipping shortcut"
)

:: Create iTunes shortcut
if exist "%ITUNES_EXE%" (
    if not exist "%PUBLIC_DESKTOP%\iTunes.lnk" (
        powershell -NoProfile -Command ^
            "$ws = New-Object -ComObject WScript.Shell; " ^
            "$s = $ws.CreateShortcut('%PUBLIC_DESKTOP%\iTunes.lnk'); " ^
            "$s.TargetPath = '%ITUNES_EXE%'; " ^
            "$s.Save()"
        if errorlevel 1 (
            call "%LOG%" warn "Failed to create iTunes desktop shortcut"
        ) else (
            call "%LOG%" debug "Created iTunes desktop shortcut"
        )
    ) else (
        call "%LOG%" debug "iTunes shortcut already exists"
    )
) else (
    call "%LOG%" debug "iTunes not installed, skipping shortcut"
)

call "%LOG%" success "Desktop shortcuts created"
exit /b 0

:: ============================================================================
:: REGISTRY MARKER
:: ============================================================================

:MarkCustomized
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark desktop as customized in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "DesktopCustomized" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "DesktopCustomizedDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
goto :eof

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

@echo off
::==============================================================================
:: 37-suppress-nags.bat - Windows 11 Nag and Ad Suppression
::==============================================================================
:: Silences consumer nagware: Start/Settings/lock-screen suggestions, Edge
:: default-browser and sidebar nags, Widgets, Copilot/Recall, OneDrive upsell.
:: Two scopes: machine-wide HKLM policies, plus a per-user HKCU set applied to
:: the current user AND seeded into the Default-User hive so accounts created
:: later (step 80) inherit clean defaults. Consumer-SKU safe: relies on
:: ContentDeliveryManager DWORDs, not Enterprise-only CloudContent policies.
::
:: --user-only: apply the HKCU set for the calling user and exit. No admin
:: needed. Used by the RunOnce safety net seeded into new profiles.
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
if /i "%~1"=="--user-only" set "USER_ONLY=1"
shift
goto :ParseArgs
:ParseArgsDone

:: User-only mode: per-user keys for the calling user, no admin gate, no
:: marker, no log facade - this runs unelevated at first logon of new users.
if "%USER_ONLY%"=="1" (
    if "%DRY_RUN%"=="1" (
        echo [DRY-RUN] Would apply per-user nag suppression to HKCU
        exit /b 0
    )
    call :ApplyUserKeys HKCU
    exit /b 0
)

:: ============================================================================
:: MAIN EXECUTION
:: ============================================================================
call "%LOG%" section "Nag and Ad Suppression"

:: Check for admin privileges
call "%ADMIN%"
if errorlevel 1 (
    call "%LOG%" error "Administrator privileges required"
    exit /b %EXIT_PREREQ_FAILED%
)

:: Check if already suppressed
reg query "%SETUP_REG_KEY%" /v "NagsSuppressed" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
    if not "%FORCE%"=="1" (
        call "%LOG%" info "Nag suppression already applied"
        call "%LOG%" success "Nag suppression is in place"
        exit /b %EXIT_SUCCESS%
    )
    call "%LOG%" info "Re-applying nag suppression [--force]"
)

set "NAG_ERRORS=0"

call :ApplyMachineKeys
if errorlevel 1 set /a "NAG_ERRORS+=1"

call :ApplyCurrentUserKeys
if errorlevel 1 set /a "NAG_ERRORS+=1"

call :SeedDefaultHive
if errorlevel 1 set /a "NAG_ERRORS+=1"

call :SeedStartLayout
if errorlevel 1 set /a "NAG_ERRORS+=1"

:: No marker on partial success - a failed Default-hive seed must be
:: retried on the next run or new profiles inherit the nags silently.
if %NAG_ERRORS% GTR 0 (
    call "%LOG%" warn "Nag suppression completed with %NAG_ERRORS% warnings - will retry on next run"
    exit /b %EXIT_PARTIAL_SUCCESS%
)

call :MarkSuppressed
call "%LOG%" success "Nag suppression completed successfully"
exit /b %EXIT_SUCCESS%

:: ============================================================================
:: FUNCTIONS
:: ============================================================================

:: ============================================================================
:: MACHINE-WIDE POLICIES (HKLM - all of these work on consumer SKUs)
:: ============================================================================

:ApplyMachineKeys
call "%LOG%" info "Applying machine-wide nag suppression policies..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would apply HKLM policies: Edge nags, Widgets, ads, Recall/Copilot, OneDrive upsell
    exit /b 0
)

set "EDGE_POL=HKLM\SOFTWARE\Policies\Microsoft\Edge"
reg add "%EDGE_POL%" /v "HideFirstRunExperience" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "%EDGE_POL%" /v "BrowserSignin" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EDGE_POL%" /v "SpotlightExperiencesAndRecommendationsEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EDGE_POL%" /v "ShowRecommendationsEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EDGE_POL%" /v "DefaultBrowserSettingEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EDGE_POL%" /v "StartupBoostEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EDGE_POL%" /v "BackgroundModeEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EDGE_POL%" /v "HubsSidebarEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EDGE_POL%" /v "NewTabPageContentEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EDGE_POL%" /v "EdgeShoppingAssistantEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EDGE_POL%" /v "PersonalizationReportingEnabled" /t REG_DWORD /d 0 /f >nul 2>&1

:: Widgets - the durable machine-wide lock, also blocks the Win+W board
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v "AllowNewsAndInterests" /t REG_DWORD /d 0 /f >nul 2>&1

:: Start menu Recommended section
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v "HideRecommendedSection" /t REG_DWORD /d 1 /f >nul 2>&1

:: Advertising ID
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" /v "DisabledByGroupPolicy" /t REG_DWORD /d 1 /f >nul 2>&1

:: Recall + Click To Do. AllowRecallEnablement=0 removes Recall entirely
:: (Home-confirmed); DisableAIDataAnalysis stops snapshots as backup.
set "WINAI_POL=HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
reg add "%WINAI_POL%" /v "AllowRecallEnablement" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%WINAI_POL%" /v "DisableAIDataAnalysis" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "%WINAI_POL%" /v "DisableClickToDo" /t REG_DWORD /d 1 /f >nul 2>&1

:: Legacy Copilot policy - harmless where ignored; app removal in step 35 is
:: the durable path for the consumer Copilot app.
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v "TurnOffWindowsCopilot" /t REG_DWORD /d 1 /f >nul 2>&1

:: OneDrive upsell belt-and-suspenders - the app itself is removed in step 35
set "ONEDRIVE_POL=HKLM\SOFTWARE\Policies\Microsoft\OneDrive"
reg add "%ONEDRIVE_POL%" /v "KFMBlockOptIn" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "%ONEDRIVE_POL%" /v "DisableFileSyncNGSC" /t REG_DWORD /d 1 /f >nul 2>&1

call "%LOG%" success "Machine-wide policies applied"
exit /b 0

:: ============================================================================
:: PER-USER KEYS - CURRENT USER
:: ============================================================================

:ApplyCurrentUserKeys
call "%LOG%" info "Applying per-user nag suppression to current user..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would apply HKCU set: suggestions, tips, lock-screen ads, Bing search, taskbar clutter
    exit /b 0
)
call :ApplyUserKeys HKCU
call "%LOG%" success "Current user keys applied"
exit /b 0

:: ============================================================================
:: PER-USER KEYS - DEFAULT-USER HIVE SEED
:: ============================================================================
:: Loads C:\Users\Default\NTUSER.DAT so every profile created after this step
:: (including the standard user from step 80) inherits clean defaults, plus a
:: RunOnce safety net that re-applies at the profile's first logon in case
:: new-user provisioning clobbers seeded values.

:SeedDefaultHive
call "%LOG%" info "Seeding nag suppression into the Default-User hive..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would load Default-User hive, apply the HKCU set, and seed a RunOnce re-apply
    exit /b 0
)

reg load HKU\DefUser "%SystemDrive%\Users\Default\NTUSER.DAT" >nul 2>&1
if errorlevel 1 (
    call "%LOG%" warn "Could not load Default-User hive - new profiles will rely on the RunOnce safety net only"
    exit /b 1
)

call :ApplyUserKeys HKU\DefUser

:: RunOnce safety net: re-apply per-user keys at the new profile's first
:: logon. Best-effort - benign no-op if the script path no longer exists.
reg add "HKU\DefUser\Software\Microsoft\Windows\CurrentVersion\RunOnce" /v "WindexNagSuppress" /t REG_SZ /d "\"%~f0\" --user-only" /f >nul 2>&1

:: Unload with retry - the hive can briefly hold handles after the writes
set "UNLOAD_OK=0"
for /l %%R in (1,1,3) do (
    if "!UNLOAD_OK!"=="0" (
        reg unload HKU\DefUser >nul 2>&1
        if !ERRORLEVEL! EQU 0 (
            set "UNLOAD_OK=1"
        ) else (
            ping -n 3 127.0.0.1 >nul
        )
    )
)
if "!UNLOAD_OK!"=="0" (
    call "%LOG%" warn "Failed to unload Default-User hive - a reboot will release it"
    exit /b 1
)

call "%LOG%" success "Default-User hive seeded"
exit /b 0

:: ============================================================================
:: THE PER-USER KEY SET
:: ============================================================================
:: %~1 is the registry root: HKCU for a live user, HKU\DefUser for the seed.
:: Pure reg adds, no logging - callers log. Safe to run unelevated for HKCU.

:ApplyUserKeys
set "ROOT=%~1"

:: Suggestions, tips, ads, silent promo-app installs
set "CDM=%ROOT%\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
reg add "%CDM%" /v "ContentDeliveryAllowed" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "FeatureManagementEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "OemPreInstalledAppsEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "PreInstalledAppsEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "PreInstalledAppsEverEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "SilentInstalledAppsEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "SoftLandingEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "SystemPaneSuggestionsEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "RotatingLockScreenEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "RotatingLockScreenOverlayEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "SubscribedContent-310093Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "SubscribedContent-338387Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "SubscribedContent-338388Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "SubscribedContent-338389Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "SubscribedContent-338393Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "SubscribedContent-353694Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%CDM%" /v "SubscribedContent-353696Enabled" /t REG_DWORD /d 0 /f >nul 2>&1

:: "Finish setting up your device" full-screen nag
reg add "%ROOT%\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v "ScoobeSystemSettingEnabled" /t REG_DWORD /d 0 /f >nul 2>&1

:: Explorer surface: OneDrive/M365 flyout nags, Start recommendations,
:: Chat taskbar icon, Copilot button. No TaskbarDa here: Microsoft locks that
:: value against direct writes on 24H2+ (Access is denied even in the user's
:: own hive) - the Dsh\AllowNewsAndInterests=0 policy above is the Widgets kill.
set "EXP_ADV=%ROOT%\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
reg add "%EXP_ADV%" /v "ShowSyncProviderNotifications" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EXP_ADV%" /v "Start_IrisRecommendations" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EXP_ADV%" /v "Start_AccountNotifications" /t REG_DWORD /d 0 /f >nul 2>&1

:: OneDrive residue for this user: kill the first-logon setup trigger and
:: the orphaned Explorer nav-pane entry (step 35 removes the app itself)
reg delete "%ROOT%\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f >nul 2>&1
reg add "%ROOT%\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /v "System.IsPinnedToNameSpaceTree" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EXP_ADV%" /v "TaskbarMn" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%EXP_ADV%" /v "ShowCopilotButton" /t REG_DWORD /d 0 /f >nul 2>&1

:: Local-only search - no Bing web results, no search highlights
reg add "%ROOT%\Software\Policies\Microsoft\Windows\Explorer" /v "DisableSearchBoxSuggestions" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "%ROOT%\Software\Microsoft\Windows\CurrentVersion\Search" /v "BingSearchEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%ROOT%\Software\Microsoft\Windows\CurrentVersion\Search" /v "CortanaConsent" /t REG_DWORD /d 0 /f >nul 2>&1

:: Tailored experiences + per-user advertising ID
reg add "%ROOT%\Software\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%ROOT%\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f >nul 2>&1

:: Game Bar capture prompts
reg add "%ROOT%\Software\Microsoft\Windows\CurrentVersion\GameDVR" /v "AppCaptureEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "%ROOT%\System\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d 0 /f >nul 2>&1

exit /b 0

:: ============================================================================
:: REGISTRY MARKER
:: ============================================================================

:MarkSuppressed
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would mark nags as suppressed in registry
    exit /b 0
)
reg add "%SETUP_REG_KEY%" /v "NagsSuppressed" /t REG_SZ /d "1" /f >nul 2>&1
reg add "%SETUP_REG_KEY%" /v "NagsSuppressedDate" /t REG_SZ /d "%DATE% %TIME%" /f >nul 2>&1
exit /b 0

:: ============================================================================
:: DEFAULT START-MENU PIN LAYOUT (new profiles only)
:: ============================================================================
:: Replaces the promo pins (Solitaire/WhatsApp/LinkedIn/Xbox/Outlook) with a
:: curated list for profiles created after this step. Existing profiles keep
:: their start2.bin - unpin manually there. Delayed expansion is disabled so
:: the ! in packaged-app AUMIDs survives the echo.

:SeedStartLayout
call "%LOG%" info "Seeding default Start-menu pin layout for new profiles..."
if "%DRY_RUN%"=="1" (
    echo [DRY-RUN] Would write LayoutModification.json to the Default profile
    exit /b 0
)

setlocal DisableDelayedExpansion
set "LAYOUT_DIR=%SystemDrive%\Users\Default\AppData\Local\Microsoft\Windows\Shell"
if not exist "%LAYOUT_DIR%" mkdir "%LAYOUT_DIR%" >nul 2>&1
set "CHROME_LNK=%ALLUSERSPROFILE:\=\\%\\Microsoft\\Windows\\Start Menu\\Programs\\Google Chrome.lnk"
(
    echo {
    echo   "pinnedList": [
    echo     { "desktopAppLink": "%CHROME_LNK%" },
    echo     { "packagedAppId": "windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel" },
    echo     { "packagedAppId": "Microsoft.WindowsStore_8wekyb3d8bbwe!App" },
    echo     { "packagedAppId": "Microsoft.Windows.Photos_8wekyb3d8bbwe!App" },
    echo     { "packagedAppId": "Microsoft.WindowsCalculator_8wekyb3d8bbwe!App" },
    echo     { "packagedAppId": "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App" },
    echo     { "packagedAppId": "Microsoft.ScreenSketch_8wekyb3d8bbwe!App" },
    echo     { "packagedAppId": "Microsoft.Paint_8wekyb3d8bbwe!App" },
    echo     { "packagedAppId": "Microsoft.WindowsAlarms_8wekyb3d8bbwe!App" }
    echo   ]
    echo }
) > "%LAYOUT_DIR%\LayoutModification.json"
endlocal

call "%LOG%" success "Default Start layout seeded"
exit /b 0

:: ============================================================================
:: END OF SCRIPT
:: ============================================================================

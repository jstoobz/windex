@echo off
:: ============================================================================
:: config.bat - Centralized Configuration for Remote Access Setup
:: ============================================================================
:: All values read from environment first, falling back to defaults.
:: Set values in .env or export before running scripts.
:: DO NOT define labels/functions here - they won't be accessible from caller.
:: ============================================================================

:: Prevent re-initialization if already loaded
if defined CONFIG_LOADED exit /b 0
set "CONFIG_LOADED=1"

:: ============================================================================
:: VERSION INFO
:: ============================================================================
set "SETUP_VERSION=1.0.0"
set "SETUP_NAME=Remote Access Automation Suite"

:: ============================================================================
:: PATHS
:: ============================================================================
:: Get the directory where this config.bat lives
set "LIB_DIR=%~dp0"
:: Remove trailing backslash
if "%LIB_DIR:~-1%"=="\" set "LIB_DIR=%LIB_DIR:~0,-1%"

:: Shared utility scripts
set "LOG=%LIB_DIR%\log.bat"
set "ADMIN=%LIB_DIR%\admin.bat"

:: Parent directories (scripts and base)
for %%I in ("%LIB_DIR%\..") do set "SCRIPTS_DIR=%%~fI"
if not defined BASE_DIR (
    for %%I in ("%SCRIPTS_DIR%\..") do set "BASE_DIR=%%~fI"
)

:: Output directories
set "LOG_DIR=%BASE_DIR%\logs"
set "OUTPUT_DIR=%BASE_DIR%\output"

:: Ensure directories exist
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%" 2>nul

:: Log file (timestamped with seconds to avoid collisions)
for /f "tokens=*" %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmmss"') do set "DATETIME=%%I"
set "DATE_STAMP=%DATETIME:~0,8%"
set "TIME_STAMP=%DATETIME:~8,6%"
set "LOG_FILE=%LOG_DIR%\setup_%DATE_STAMP%_%TIME_STAMP%.log"

:: Credentials output file
set "CREDENTIALS_FILE=%OUTPUT_DIR%\credentials.txt"

:: ============================================================================
:: DOWNLOAD URLs
:: ============================================================================
if not defined TAILSCALE_URL set "TAILSCALE_URL=https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"

:: ============================================================================
:: TAILSCALE CONFIGURATION
:: ============================================================================
if not defined TAILSCALE_AUTHKEY set "TAILSCALE_AUTHKEY="
if not defined TAILSCALE_DIR set "TAILSCALE_DIR=C:\Program Files\Tailscale"
set "TAILSCALE_EXE=%TAILSCALE_DIR%\tailscale.exe"
if not defined TAILSCALE_SUBNET set "TAILSCALE_SUBNET=100.64.0.0/10"

:: ============================================================================
:: VNC CONFIGURATION (TigerVNC - winget installs viewer-only in silent mode;
:: falls back to the dedicated server installer direct from SourceForge.
:: Confirmed live 2026-07-10: TigerVNC.TigerVNC's winget package wraps the
:: combined Inno Setup installer, which silently defaults to viewer-only
:: with no component switches passed - winvnc4.exe never appears.
:: Use the downloads.sourceforge.net/project/... URL form, NOT the
:: sourceforge.net/.../download browser-page URL -- the latter depends on
:: cookie continuity across an internal redirect chain and silently serves
:: an HTML mirror-selection page to scripted clients instead of the binary.)
:: ============================================================================
if not defined VNC_PORT set "VNC_PORT=5900"
if not defined VNC_PASSWORD_LENGTH set "VNC_PASSWORD_LENGTH=16"
if not defined VNC_DIR set "VNC_DIR=C:\Program Files\TigerVNC"
if not defined VNC_SERVICE set "VNC_SERVICE=winvnc4"
if not defined TIGERVNC_WINVNC_URL set "TIGERVNC_WINVNC_URL=https://downloads.sourceforge.net/project/tigervnc/stable/1.16.2/tigervnc64-winvnc-1.16.2.exe"

:: ============================================================================
:: FIREWALL CONFIGURATION
:: ============================================================================
if not defined FW_RULE_VNC_ALLOW set "FW_RULE_VNC_ALLOW=VNC-Tailscale-Allow"
if not defined FW_RULE_VNC_BLOCK set "FW_RULE_VNC_BLOCK=VNC-Block-All"

:: ============================================================================
:: SSH / OPENSSH CONFIGURATION
:: ============================================================================
if not defined SSH_PORT set "SSH_PORT=22"
set "OPENSSH_PS1=%SCRIPTS_DIR%\setup-openssh-server.ps1"
if not defined FW_RULE_SSH_ALLOW set "FW_RULE_SSH_ALLOW=SSH-Tailscale-Allow"
if not defined FW_RULE_SSH_BLOCK set "FW_RULE_SSH_BLOCK=SSH-Block-All"
if not defined ADMIN_SSH_PUBKEY set "ADMIN_SSH_PUBKEY="

:: ============================================================================
:: ESSENTIAL APPS
:: ============================================================================
if not defined CHROME_MSI_URL set "CHROME_MSI_URL=https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise_arm64.msi"
set "CHROME_EXE=C:\Program Files\Google\Chrome\Application\chrome.exe"

set "ITUNES_EXE=C:\Program Files\iTunes\iTunes.exe"
if not defined MALWAREBYTES_URL set "MALWAREBYTES_URL=https://downloads.malwarebytes.com/file/mb-windows"
set "MALWAREBYTES_EXE=C:\Program Files\Malwarebytes\Anti-Malware\mbam.exe"

:: Rufus - USB format / bootable-media tool (machine scope so it survives user creation)
if not defined RUFUS_WINGET_ID set "RUFUS_WINGET_ID=Rufus.Rufus"
set "RUFUS_EXE=%ProgramFiles%\WinGet\Links\rufus.exe"
set "RUFUS_SHORTCUT=%ProgramData%\Microsoft\Windows\Start Menu\Programs\Rufus.lnk"

:: CHROME EXTENSIONS (Chrome Web Store IDs)
set "EXT_UBLOCK=cjpalhdlnbpafiamejdnhcphjbkeiagm"

:: ============================================================================
:: DNS CONFIGURATION
:: ============================================================================
if not defined DNS_PRIMARY set "DNS_PRIMARY=1.1.1.3"
if not defined DNS_SECONDARY set "DNS_SECONDARY=1.0.0.3"

:: ============================================================================
:: CONNECTIVITY
:: ============================================================================
if not defined CONNECTIVITY_CHECK_IP set "CONNECTIVITY_CHECK_IP=8.8.8.8"

:: ============================================================================
:: STANDARD USER ACCOUNT (optional — set via --username/--password args or .env)
:: ============================================================================
if not defined STANDARD_USERNAME set "STANDARD_USERNAME="
if not defined STANDARD_PASSWORD set "STANDARD_PASSWORD="

:: ============================================================================
:: REGISTRY CONFIGURATION
:: ============================================================================
set "SETUP_REG_KEY=HKLM\SOFTWARE\RemoteAccessSetup"

:: ============================================================================
:: RUNTIME FLAGS (can be overridden before calling config)
:: ============================================================================
if not defined DRY_RUN set "DRY_RUN=0"
if not defined VERBOSE set "VERBOSE=0"
if not defined CONTINUE_ON_ERROR set "CONTINUE_ON_ERROR=0"
if not defined FORCE set "FORCE=0"

:: ============================================================================
:: EXIT CODES (Standardized)
:: ============================================================================
set "EXIT_SUCCESS=0"
set "EXIT_CANCELLED=1"
set "EXIT_PREREQ_FAILED=2"
set "EXIT_EXECUTION_FAILED=3"
set "EXIT_VERIFICATION_FAILED=4"
set "EXIT_PARTIAL_SUCCESS=5"

exit /b 0

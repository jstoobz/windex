@echo off
:: ============================================================================
:: config.bat - Centralized Configuration for Remote Access Setup
:: ============================================================================
:: This file sets environment variables. Call it, then use the variables.
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

:: Parent directories (scripts and base)
for %%I in ("%LIB_DIR%\..") do set "SCRIPTS_DIR=%%~fI"
for %%I in ("%SCRIPTS_DIR%\..") do set "BASE_DIR=%%~fI"

:: Output directories
set "LOG_DIR=%BASE_DIR%\logs"
set "OUTPUT_DIR=%BASE_DIR%\output"

:: Ensure directories exist
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%" 2>nul

:: Log file (timestamped) - use simple date format
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set "DATETIME=%%I"
set "DATE_STAMP=%DATETIME:~0,8%"
set "TIME_STAMP=%DATETIME:~8,4%"
set "LOG_FILE=%LOG_DIR%\setup_%DATE_STAMP%_%TIME_STAMP%.log"

:: Credentials output file
set "CREDENTIALS_FILE=%OUTPUT_DIR%\credentials.txt"

:: ============================================================================
:: DOWNLOAD URLs
:: ============================================================================
set "TAILSCALE_URL=https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe"
set "TIGHTVNC_URL=https://www.tightvnc.com/download/2.8.85/tightvnc-2.8.85-gpl-setup-64bit.msi"

:: ============================================================================
:: TAILSCALE CONFIGURATION
:: ============================================================================
if not defined TAILSCALE_AUTHKEY set "TAILSCALE_AUTHKEY="
set "TAILSCALE_DIR=C:\Program Files\Tailscale"
set "TAILSCALE_EXE=%TAILSCALE_DIR%\tailscale.exe"
set "TAILSCALE_SUBNET=100.64.0.0/10"

:: ============================================================================
:: TIGHTVNC CONFIGURATION
:: ============================================================================
set "VNC_PORT=5900"
set "VNC_PASSWORD_LENGTH=16"
set "VNC_PASSWORD_SPECIAL_CHARS=4"
set "TIGHTVNC_DIR=C:\Program Files\TightVNC"
set "TIGHTVNC_SERVICE=tvnserver"

:: ============================================================================
:: FIREWALL CONFIGURATION
:: ============================================================================
set "FW_RULE_VNC_ALLOW=VNC-Tailscale-Allow"
set "FW_RULE_VNC_BLOCK=VNC-Block-All"

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
:: TIMEOUTS AND RETRIES
:: ============================================================================
set "DOWNLOAD_TIMEOUT=300"
set "MAX_RETRIES=3"
set "SERVICE_TIMEOUT=60"

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

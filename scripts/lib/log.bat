@echo off
:: ============================================================================
:: log.bat - Shared Logging Utility
:: ============================================================================
:: Usage: call "%LOG%" <level> "message"
::
:: Levels: section, info, error, success, debug, warn
::
:: Requires LOG_FILE (for file logging) and VERBOSE (for debug) to be set
:: in the caller's environment. Both are set by config.bat.
:: ============================================================================
set "_LEVEL=%~1"
set "_MSG=%~2"

if /i "%_LEVEL%"=="section" (
    echo.
    echo ============================================================
    echo %_MSG%
    echo ============================================================
    if defined LOG_FILE (
        echo. >> "%LOG_FILE%"
        echo ============================================================ >> "%LOG_FILE%"
        echo %_MSG% >> "%LOG_FILE%"
        echo ============================================================ >> "%LOG_FILE%"
    )
    exit /b 0
)

if /i "%_LEVEL%"=="info" (
    echo [INFO] %_MSG%
    if defined LOG_FILE echo [%DATE% %TIME%] [INFO] %_MSG% >> "%LOG_FILE%"
    exit /b 0
)

if /i "%_LEVEL%"=="error" (
    echo [ERROR] %_MSG%
    if defined LOG_FILE echo [%DATE% %TIME%] [ERROR] %_MSG% >> "%LOG_FILE%"
    exit /b 0
)

if /i "%_LEVEL%"=="success" (
    echo [OK] %_MSG%
    if defined LOG_FILE echo [%DATE% %TIME%] [OK] %_MSG% >> "%LOG_FILE%"
    exit /b 0
)

if /i "%_LEVEL%"=="debug" (
    if "%VERBOSE%"=="1" echo [DEBUG] %_MSG%
    if defined LOG_FILE echo [%DATE% %TIME%] [DEBUG] %_MSG% >> "%LOG_FILE%"
    exit /b 0
)

if /i "%_LEVEL%"=="warn" (
    echo [WARN] %_MSG%
    if defined LOG_FILE echo [%DATE% %TIME%] [WARN] %_MSG% >> "%LOG_FILE%"
    exit /b 0
)

echo [???] Unknown log level: %_LEVEL% — %_MSG%
exit /b 0

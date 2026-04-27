@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

:: Ensure build_logs directory exists
if not exist "build_logs" mkdir "build_logs"

:: Generate timestamp for unique log files
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%%i

set "MASTER_LOG=build_logs\master_build_%TS%.log"
set "FAILURES=0"

echo ============================================================
echo           Lumina Multi-Platform Release Builder
echo ============================================================
echo Started: %DATE% %TIME%
echo Build started at %DATE% %TIME% > "%MASTER_LOG%"
echo.

:: 1. WINDOWS BUILD
call :build_task "Windows Desktop" "windows" "flutter build windows --release --dart-define-from-file=.env" "build_logs\windows_build_%TS%.log"

:: 2. ANDROID BUILDS
call :build_task "Android Mobile" "android" "flutter build apk --release --dart-define-from-file=.env" "build_logs\android_mobile_%TS%.log"
call :build_task "Android Tablet" "android" "flutter build apk --release --dart-define=FORM_FACTOR=tablet --dart-define-from-file=.env" "build_logs\android_tablet_%TS%.log"
call :build_task "Android TV" "android" "flutter build apk --release --dart-define=UI_MODE=tv --dart-define=FORM_FACTOR=tv --dart-define-from-file=.env" "build_logs\android_tv_%TS%.log"
call :build_task "Firestick" "android" "flutter build apk --release --target-platform android-arm --dart-define=UI_MODE=tv --dart-define=FORM_FACTOR=firestick --dart-define-from-file=.env" "build_logs\android_firestick_%TS%.log"

:: 3. SAMSUNG TV (TIZEN) BUILD
:: Checking if Tizen folder exists
if exist "tizen" (
    call :build_task "Samsung TV (Tizen)" "tizen" "flutter-tizen build tizen --release --dart-define-from-file=.env" "build_logs\tizen_build_%TS%.log"
) else (
    echo [%TIME%] SKIPPING: Samsung TV (Tizen folder not found)
    echo [TIZEN] Skipped - Folder not found >> "%MASTER_LOG%"
)

:: 4. ROKU BUILD (Placeholder)
:: Note: Roku apps are typically not built with Flutter. Placeholder added for manual verification.
echo [%TIME%] SKIPPING: Roku (No Roku project files detected in workspace)
echo [ROKU] Skipped - No Roku project detected >> "%MASTER_LOG%"

echo.
echo ============================================================
echo Build Process Finished with %FAILURES% failure(s).
echo ============================================================
echo Full logs available in: %CD%\build_logs\
echo. >> "%MASTER_LOG%"
echo Build finished with %FAILURES% failure(s) at %TIME%. >> "%MASTER_LOG%"

if "%FAILURES%"=="0" (
    echo SUCCESS: All builds completed successfully.
) else (
    echo WARNING: One or more builds failed. Check the logs in build_logs\.
)

pause
exit /b %FAILURES%

:build_task
set "TASK_NAME=%~1"
set "PLATFORM=%~2"
set "COMMAND=%~3"
set "LOG_FILE=%~4"

echo [%TIME%] STARTING: %TASK_NAME%
echo ===== %TASK_NAME% Build Started ===== > "%LOG_FILE%"
echo Command: %COMMAND% >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

:: Run the build command and redirect all output to its specific log file
cmd /c "%COMMAND%" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [%TIME%] FAILED:   %TASK_NAME%
    echo ===== %TASK_NAME% Build FAILED ===== >> "%LOG_FILE%"
    echo [%TASK_NAME%] FAILED - Check %LOG_FILE% >> "%MASTER_LOG%"
    set /a FAILURES+=1
) else (
    echo [%TIME%] SUCCESS:  %TASK_NAME%
    echo ===== %TASK_NAME% Build SUCCESS ===== >> "%LOG_FILE%"
    echo [%TASK_NAME%] SUCCESS >> "%MASTER_LOG%"
)
goto :eof

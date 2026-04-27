@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

if not exist "build_logs" mkdir "build_logs"
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%%i
set "LOG=build_logs\windows_build_%TS%.log"

echo Lumina Windows build started %DATE% %TIME% > "%LOG%"
echo ===== START Windows release =====>> "%LOG%"
echo Command: flutter build windows --release --dart-define-from-file=.env >> "%LOG%"

echo Log: %CD%\%LOG%
echo.
echo Lumina Windows release build
echo ============================
echo Starting the Windows release build now.
echo A simple build log is being saved here:
echo %CD%\%LOG%
echo.
echo [%TIME%] START Windows release

flutter build windows --release --dart-define-from-file=.env >> "%LOG%" 2>&1

if errorlevel 1 (
  echo [%TIME%] FAIL  Windows release
  echo ===== FAIL Windows release =====>> "%LOG%"
  echo.
  echo FAILED: The Windows release build did not finish.
  echo Open this log to see the error:
  echo %CD%\%LOG%
  echo.
  pause
  exit /b 1
)

echo [%TIME%] OK    Windows release
echo ===== OK Windows release =====>> "%LOG%"
echo Artifact: %CD%\build\windows\x64\runner\Release\lumina_media.exe>> "%LOG%"
echo.
echo SUCCESS: The Windows release build completed.
echo App:
echo %CD%\build\windows\x64\runner\Release\lumina_media.exe
echo.
echo Full log:
echo %CD%\%LOG%
echo.
pause
exit /b 0

@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

if not exist "build_logs" mkdir "build_logs"
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%%i
set "LOG=build_logs\android_build_%TS%.log"
set "FAILURES=0"
set "DART_DEFINES="

if exist ".env" (
  for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
    if not "%%A"=="" if not "%%B"=="" (
      set "ENV_KEY=%%A"
      if /I "!ENV_KEY:~0,5!" NEQ "IPTV_" (
        set "DART_DEFINES=!DART_DEFINES! --dart-define=%%A=%%B"
      )
    )
  )
)

echo Lumina Android build started %DATE% %TIME% > "%LOG%"
if defined DART_DEFINES (
  echo Loaded .env values into dart defines.>> "%LOG%"
)
echo Log: %CD%\%LOG%
echo.

call :build_variant "Mobile release" "flutter build apk --release%DART_DEFINES%" "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\lumina-mobile-release.apk"
call :build_variant "Tablet release" "flutter build apk --release --dart-define=FORM_FACTOR=tablet%DART_DEFINES%" "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\lumina-tablet-release.apk"
call :build_variant "Emulator debug x64" "flutter build apk --debug --target-platform android-x64 --dart-define=FORM_FACTOR=emulator%DART_DEFINES%" "build\app\outputs\flutter-apk\app-debug.apk" "build\app\outputs\flutter-apk\lumina-emulator-debug.apk"
call :build_variant "Firestick release ARMv7" "flutter build apk --release --target-platform android-arm --dart-define=UI_MODE=tv --dart-define=FORM_FACTOR=firestick%DART_DEFINES%" "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\lumina-firestick-release.apk"
call :build_variant "Android TV release" "flutter build apk --release --dart-define=UI_MODE=tv --dart-define=FORM_FACTOR=tv%DART_DEFINES%" "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\lumina-android-tv-release.apk"

echo.>> "%LOG%"
echo Build finished with %FAILURES% failure(s).>> "%LOG%"
echo.
echo Build finished with %FAILURES% failure(s).
echo Full log: %CD%\%LOG%

if not "%FAILURES%"=="0" exit /b 1
exit /b 0

:build_variant
set "NAME=%~1"
set "COMMAND=%~2"
set "SOURCE=%~3"
set "DEST=%~4"

echo [%TIME%] START %NAME%
echo.>> "%LOG%"
echo ===== START %NAME% =====>> "%LOG%"
echo Command: flutter build for %NAME%>> "%LOG%"

cmd /c "%COMMAND%" >> "%LOG%" 2>&1
if errorlevel 1 (
  echo [%TIME%] FAIL  %NAME%
  echo ===== FAIL %NAME% =====>> "%LOG%"
  set /a FAILURES+=1
  goto :eof
)

if exist "%SOURCE%" (
  copy /Y "%SOURCE%" "%DEST%" >> "%LOG%" 2>&1
  if errorlevel 1 (
    echo [%TIME%] FAIL  %NAME% artifact copy
    echo ===== FAIL %NAME% artifact copy =====>> "%LOG%"
    set /a FAILURES+=1
    goto :eof
  )
  echo Artifact: %CD%\%DEST%>> "%LOG%"
) else (
  echo [%TIME%] FAIL  %NAME% missing artifact
  echo Missing artifact: %SOURCE%>> "%LOG%"
  set /a FAILURES+=1
  goto :eof
)

echo [%TIME%] OK    %NAME%
echo ===== OK %NAME% =====>> "%LOG%"
goto :eof

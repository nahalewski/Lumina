@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

if not exist "build_logs" mkdir "build_logs"
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%%i
set "LOG=build_logs\android_build_%TS%.log"
set "FAILURES=0"
set "DART_DEFINES="

:: ─── Auto-increment build number in pubspec.yaml ─────────────────────────────
echo Reading current version from pubspec.yaml...
for /f "tokens=2 delims= " %%L in ('findstr /r "^version:" pubspec.yaml') do set VERSION_LINE=%%L

:: Split version string (e.g. 1.0.0+5) into semver and build parts
for /f "tokens=1,2 delims=+" %%A in ("!VERSION_LINE!") do (
  set "SEMVER=%%A"
  set "CURRENT_BUILD=%%B"
)

if "!CURRENT_BUILD!"=="" set "CURRENT_BUILD=0"
set /a NEW_BUILD=!CURRENT_BUILD!+1

:: Rewrite pubspec.yaml with the new build number
powershell -NoProfile -Command ^
  "(Get-Content 'pubspec.yaml') -replace '^version: .*', 'version: !SEMVER!+!NEW_BUILD!' | Set-Content 'pubspec.yaml' -Encoding utf8"

echo Build number: !CURRENT_BUILD! ^-^> !NEW_BUILD! (version !SEMVER!+!NEW_BUILD!)
echo Build number incremented to !NEW_BUILD! > "%LOG%"

:: ─── Load .env variables ──────────────────────────────────────────────────────
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

echo Lumina Android build started %DATE% %TIME% >> "%LOG%"
echo Version: !SEMVER!+!NEW_BUILD! >> "%LOG%"
if defined DART_DEFINES (
  echo Loaded .env values into dart defines.>> "%LOG%"
)
echo Log: %CD%\%LOG%
echo.

:: Append --build-number to all flutter commands
set "BN=--build-number=!NEW_BUILD!"

call :build_variant "Mobile release"          "flutter build apk --release %BN%%DART_DEFINES%"                                                          "build\app\outputs\flutter-apk\app-release.apk"  "build\app\outputs\flutter-apk\lumina-mobile-release.apk"
call :build_variant "Tablet release"          "flutter build apk --release %BN% --dart-define=FORM_FACTOR=tablet%DART_DEFINES%"                         "build\app\outputs\flutter-apk\app-release.apk"  "build\app\outputs\flutter-apk\lumina-tablet-release.apk"
call :build_variant "Emulator debug x64"      "flutter build apk --debug  %BN% --target-platform android-x64 --dart-define=FORM_FACTOR=emulator%DART_DEFINES%" "build\app\outputs\flutter-apk\app-debug.apk"    "build\app\outputs\flutter-apk\lumina-emulator-debug.apk"
call :build_variant "Firestick release ARMv7" "flutter build apk --release %BN% --target-platform android-arm --dart-define=UI_MODE=tv --dart-define=FORM_FACTOR=firestick%DART_DEFINES%" "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\lumina-firestick-release.apk"
call :build_variant "Android TV release"      "flutter build apk --release %BN% --dart-define=UI_MODE=tv --dart-define=FORM_FACTOR=tv%DART_DEFINES%"    "build\app\outputs\flutter-apk\app-release.apk"  "build\app\outputs\flutter-apk\lumina-android-tv-release.apk"

:: ─── Stage the mobile APK as the update artifact ─────────────────────────────
set "UPDATE_APK=build\app\outputs\flutter-apk\lumina-mobile-release.apk"
if exist "!UPDATE_APK!" (
  set "UPDATE_DIR=update_staging"
  if not exist "!UPDATE_DIR!" mkdir "!UPDATE_DIR!"
  copy /Y "!UPDATE_APK!" "!UPDATE_DIR!\lumina.apk" >nul 2>&1
  :: Write update_info.json
  powershell -NoProfile -Command ^
    "@{ version='!SEMVER!'; build=!NEW_BUILD!; releaseNotes='Build !NEW_BUILD!'; fileName='lumina.apk' } | ConvertTo-Json | Set-Content '!UPDATE_DIR!\update_info.json' -Encoding utf8"
  echo Staged APK for distribution: %CD%\!UPDATE_DIR!\lumina.apk
  echo Staged APK: %CD%\!UPDATE_DIR!\lumina.apk>> "%LOG%"
  echo.
  echo To serve this update, copy the contents of !UPDATE_DIR!\ to your server's update folder
  echo (shown in Settings ^> Media Server ^> Android APK Update Distribution).
)

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
echo Command: %COMMAND%>> "%LOG%"

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

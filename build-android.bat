@echo off
rem ============================================================
rem  Android APK build script (ASCII path workaround)
rem  Dart AOT compiler (gen_snapshot) cannot handle non-ASCII
rem  project paths on Windows, so mirror the project to a FlowMoney-only
rem  directory. Do not share this cache with LinguaLoop or other Flutter apps.
rem  and build there. The mirror keeps its own build\ and .dart_tool\
rem  caches across runs (robocopy /MIR does not purge excluded dirs).
rem
rem  IMPORTANT: the APK must be built with --dart-define-from-file
rem  (injects FM_API_TOKEN) AND must contain flutter_assets (fonts!).
rem  History: a subst-drive version of this script silently produced
rem  APKs with an EMPTY flutter_assets dir (all icons rendered as
rem  boxes), and manual builds from the mirror without the define
rem  got 401 from the server. This script is the only supported path.
rem ============================================================
setlocal
set "PROJ=%~dp0"
set "MIRROR=C:\fm_build_flowmoney"

rem Flutter engine artifacts are hosted on Google by default, which is often
rem unreachable on the current network. Keep explicit user settings, otherwise
rem use the official China mirrors so Gradle fails fast instead of hanging.
if not defined FLUTTER_STORAGE_BASE_URL set "FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn"
if not defined PUB_HOSTED_URL set "PUB_HOSTED_URL=https://pub.flutter-io.cn"

rem Sync source to the ASCII-path mirror. Excluded dirs: .git is large and
rem unneeded; build/.dart_tool are mirror-local caches that must survive.
robocopy "%PROJ:~0,-1%" "%MIRROR%" /MIR /XD .git build .dart_tool .idea .codex-tmp .build-tools .gradle /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
rem robocopy: exit codes 0-7 are success
if errorlevel 8 (
  echo [ERROR] mirror sync failed, robocopy exit %errorlevel%
  exit /b 1
)

cd /d "%MIRROR%"
echo Building release APK from %MIRROR% ...
set "DEFINE_ARG="
if exist "%MIRROR%\server\app_build_env.json" set "DEFINE_ARG=--dart-define-from-file=server/app_build_env.json"
rem The user's installable baseline is arm64-only. Keeping the same ABI avoids
rem a 3x larger universal APK that some phone/WeChat file handlers misclassify.
call flutter build apk --release --target-platform android-arm64 %DEFINE_ARG% %*
if errorlevel 1 exit /b 1

rem Copy the APK back so the project-relative path stays valid.
if not exist "%PROJ%build\app\outputs\flutter-apk" mkdir "%PROJ%build\app\outputs\flutter-apk"
copy /y "%MIRROR%\build\app\outputs\flutter-apk\app-release.apk" "%PROJ%build\app\outputs\flutter-apk\" >nul

echo.
echo APK: %PROJ%build\app\outputs\flutter-apk\app-release.apk
endlocal

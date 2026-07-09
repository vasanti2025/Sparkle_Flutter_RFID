@echo off
REM Build/run helper when C: drive is full — uses E: for caches and temp files.
if not exist "E:\gradle_home" mkdir "E:\gradle_home"
if not exist "E:\pub_cache" mkdir "E:\pub_cache"
if not exist "E:\flutter_tmp" mkdir "E:\flutter_tmp"

set GRADLE_USER_HOME=E:\gradle_home
set PUB_CACHE=E:\pub_cache
set TEMP=E:\flutter_tmp
set TMP=E:\flutter_tmp

cd /d "%~dp0"
echo Stopping Gradle daemons...
call android\gradlew.bat --stop >nul 2>&1

echo Cleaning locked JNI CMake cache...
if exist "E:\pub_cache\hosted\pub.dev\jni-1.0.0\android\.cxx" (
  rmdir /s /q "E:\pub_cache\hosted\pub.dev\jni-1.0.0\android\.cxx" 2>nul
)

echo Using PUB_CACHE=%PUB_CACHE%
echo Using GRADLE_USER_HOME=%GRADLE_USER_HOME%
flutter pub get
if "%1"=="" (
  flutter run --target-platform android-arm64
) else (
  flutter %*
)

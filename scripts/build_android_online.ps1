# HoneyChain Android online demo build (Windows PowerShell)
#
# This script intentionally keeps API_BASE_URL build-time injected.
# The Flutter application must not hardcode a backend URL or secrets.
# Use this script when building an APK for a physical phone that should use
# the deployed HoneyChain FastAPI backend.

$ErrorActionPreference = "Stop"

$ApiBaseUrl = "https://honeychain-api.onrender.com"
$ApkPath = "build/app/outputs/flutter-apk/app-debug.apk"

Write-Host "Building HoneyChain with API_BASE_URL=$ApiBaseUrl"

flutter pub get
flutter build apk --debug "--dart-define=API_BASE_URL=$ApiBaseUrl"

if (-not (Test-Path $ApkPath)) {
    throw "APK was not produced at $ApkPath"
}

Write-Host "APK built: $ApkPath"

$adb = Get-Command adb -ErrorAction SilentlyContinue
if ($null -eq $adb) {
    Write-Host "adb was not found on PATH. APK build is complete; install it manually."
    exit 0
}

Write-Host "Checking Android devices..."
adb devices

Write-Host "Installing APK on the connected Android device..."
adb install -r $ApkPath

Write-Host "Done. The installed APK contains the deployed HoneyChain API_BASE_URL."

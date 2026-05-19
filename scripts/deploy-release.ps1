param(
  [string]$DeviceId = "R5KL306PE2L",
  [string]$Flutter = "C:\Users\dukim\tools\flutter\bin\flutter.bat",
  [string]$Adb = "C:\Users\dukim\AppData\Local\Android\Sdk\platform-tools\adb.exe"
)

$ErrorActionPreference = "Stop"

$apk = Join-Path $PSScriptRoot "..\build\app\outputs\flutter-apk\app-release.apk"

& $Flutter build apk --release

if (-not (Test-Path $apk)) {
  throw "Release APK was not created: $apk"
}

# Keep app data while replacing the APK. Do not use `flutter install --release`
# during development because it may uninstall the app first and erase SQLite data.
& $Adb -s $DeviceId install -r $apk

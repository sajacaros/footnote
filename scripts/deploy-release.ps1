param(
  # 연결된 기기가 하나면 비워 둬도 된다. 여러 대면 `adb devices`의 ID를 넣는다.
  [string]$DeviceId = "",
  [string]$Flutter = "flutter",
  [string]$Adb = "adb"
)

$ErrorActionPreference = "Stop"

$root = Join-Path $PSScriptRoot ".."
$apk = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
$config = Join-Path $root "config\app.json"

# 서버 주소 등 환경별 값은 config/app.json에 둔다(커밋하지 않음). 없으면 앱에서 설정한다.
if (Test-Path $config) {
  & $Flutter build apk --release "--dart-define-from-file=$config"
} else {
  & $Flutter build apk --release
}

if (-not (Test-Path $apk)) {
  throw "Release APK was not created: $apk"
}

# Keep app data while replacing the APK. Do not use `flutter install --release`
# during development because it may uninstall the app first and erase SQLite data.
if ($DeviceId) {
  & $Adb -s $DeviceId install -r $apk
} else {
  & $Adb install -r $apk
}

# Footnote Walk

산책의 경로, 사진, 메모를 한 번에 남기는 Android-first Flutter 앱입니다. GPS로 이동 경로를 기록하고, 산책 중 찍은 사진을 지도 위 위치와 함께 정리합니다.

<p align="center">
  <img src="docs/images/home.png" alt="Footnote Walk home screen" width="260" />
  <img src="docs/images/detail.png" alt="Footnote Walk detail screen" width="260" />
</p>

## 주요 기능

- 2초 간격 GPS 기록으로 산책 경로 저장
- 기록 중 화면을 벗어나도 Android foreground service로 위치 추적 유지
- 산책별 거리, 시간, 걸음 수, 사진 수 요약
- 걸음 수: Health Connect에서 산책 시간대의 걸음 수를 읽어 옴(삼성 헬스·토스 만보기 등과 같은 값)
- 최근 기록, 월별 기록, 통계 화면 제공
- 지도 위 이동 방향 표시
- 상세 지도에서 경로에 맞춘 자동 확대/축소, 과도한 확대 제한
- 사진 위치 마커와 사진 썸네일 표시
- 대표사진 설정: 사용자가 지정한 사진 우선, 없으면 첫 번째 사진
- 제목과 메모 편집
- GPX 파일 공유
- 현재 지도 화면 이미지 공유
- 기록 알림: 사용자가 정한 요일·시각에 알림을 띄우고, `기록 시작` 버튼으로 바로 경로 기록 시작
- 계정과 서버 동기화: 회원가입(관리자 승인제) 후 산책 기록·GPS·사진을 자체 백엔드로 업로드
- 지도 최대화(경로 모양에 맞춰 가로/세로), 처음 위치로, 북쪽 정렬, 사진 핀 묶음

## 화면 구성

### 홈

홈에서는 오늘의 산책 요약과 최근 산책 기록을 바로 확인할 수 있습니다. 각 기록 카드는 이동 경로 지도와 대표사진을 함께 보여줍니다.

- 사진이 있는 기록: `지도 + 대표사진`
- 사진이 없는 기록: 지도 전체 표시
- 카드나 지도 영역을 누르면 상세 화면으로 이동

### 상세

상세 화면은 이동 경로를 중심으로 구성되어 있습니다. 지도는 경로 전체가 보이도록 자동 조정되며, 같은 위치 근처에서 짧게 움직인 기록은 너무 확대되지 않도록 최대 줌을 제한합니다.

사진은 산책 시간대와 위치를 기준으로 연결할 수 있고, 대표사진을 직접 지정할 수 있습니다.

## 기술 스택

- Flutter / Dart
- Android
- `flutter_map` + `flutter_map_vector_tiles` with OpenFreeMap vector tiles
- `geolocator` for GPS tracking
- `image_picker` for camera capture
- `photo_manager` for gallery photo lookup and saving app-captured photos
- `sqflite` for local persistence
- `share_plus` for GPX and image sharing
- `flutter_local_notifications` + `timezone` for scheduled walk reminders
- `health` for Health Connect step counts

## 프로젝트 구조

```text
lib/
  models/
    walk_models.dart
    walk_reminder.dart
  screens/
    home_screen.dart
    record_walk_screen.dart
    reminder_settings_screen.dart
    walk_detail_screen.dart
  services/
    active_walk_service.dart
    gpx_exporter.dart
    location_tracker.dart
    photo_storage.dart
    session_photo_finder.dart
    share_card_exporter.dart
    walk_reminder_service.dart
    walk_repository.dart
  widgets/
    session_photo_manager_sheet.dart
    walk_map_preview.dart
    walk_photo_image.dart
```

## 데이터

앱은 로컬 SQLite 데이터베이스를 사용합니다.

```text
walk_sessions
track_points
walk_photos
walk_reminders
```

사진 원본은 SQLite에 저장하지 않습니다. DB에는 사진 경로와 메타데이터만 저장하고, 원본 파일은 Android 갤러리 또는 사용자가 선택한 위치에 남습니다.

## Android 권한

주요 권한은 `android/app/src/main/AndroidManifest.xml`에 포함되어 있습니다.

```xml
ACCESS_FINE_LOCATION
ACCESS_COARSE_LOCATION
CAMERA
INTERNET
READ_MEDIA_IMAGES
READ_MEDIA_VISUAL_USER_SELECTED
READ_EXTERNAL_STORAGE
WRITE_EXTERNAL_STORAGE
FOREGROUND_SERVICE
FOREGROUND_SERVICE_LOCATION
WAKE_LOCK
POST_NOTIFICATIONS
SCHEDULE_EXACT_ALARM
RECEIVE_BOOT_COMPLETED
```

## 실행

개발 환경: Flutter 3.47.5 (stable), Android SDK 36, JDK 17, Gradle 9.3.1 / AGP 9.1.0 / Kotlin 2.4.0

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <device-id>
```

### 동기화 서버 주소

서버 주소는 저장소에 넣지 않습니다. 두 가지 방법이 있습니다.

1. **앱에서 설정**: 로그인 화면의 `서버 변경`에서 주소를 입력하면 연결을 확인한 뒤 기기에 저장합니다.
2. **빌드 기본값**: `config/app.example.json`을 `config/app.json`으로 복사해 주소를 넣고 빌드합니다. `config/app.json`은 커밋되지 않습니다.

```bash
flutter run --dart-define-from-file=config/app.json
```

백엔드 구성과 배포는 [backend/README.md](backend/README.md)를 참고하세요.

WSL2(Linux)에서는 `~/tools/flutter`, `~/Android/Sdk`에 설치하고 `ANDROID_HOME`과 `PATH`를 설정합니다. 실기기는 무선 디버깅(`adb pair` / `adb connect`)으로 연결합니다.

개발 중 기기 배포:

```powershell
.\scripts\deploy-release.ps1
```

이 스크립트는 `adb install -r`로 APK만 덮어 설치합니다. 앱 데이터와 로컬 SQLite DB를 유지하려면 개발 중에는 `flutter install --release` 대신 이 스크립트를 사용하세요.

## 참고

- 배경지도는 [OpenFreeMap](https://openfreemap.org) Bright 벡터 스타일(키 불필요)을 쓰고, 라벨은 한글만 보이게 고쳐서 씁니다. 스타일을 불러오지 못하면 OpenStreetMap 기본 타일로 대신 그립니다.
- 위치 정확도는 기기 GPS, 절전 정책, 주변 환경의 영향을 받습니다.

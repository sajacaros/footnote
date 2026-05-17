# Footnote Walk

Android-first Flutter app for recording dog walking sessions with GPS routes, photos, map history, GPX export, and shareable map images.

## Features

- Start and end a walking session
- GPS route recording with local draft GPX updates
- Recording continues when leaving the recording screen while the app process is alive
- Add photos from the app camera during a session
- Attach gallery photos taken during the session time window
- Manage photo links after a session: attach or detach without deleting original files
- Browse walks by recent timeline, monthly calendar, and weekly/monthly stats
- View each walk on a simplified CARTO/OSM map with route and photo markers
- Share GPX files
- Share the currently visible map view as an image
- Delete walk records while keeping original photo files

## Tech Stack

- Flutter / Dart
- Android target
- `flutter_map` with CARTO Positron tiles based on OpenStreetMap data
- `geolocator` for GPS
- `image_picker` for camera capture
- `photo_manager` for time-window gallery photo lookup
- `media_store_plus` for saving app-captured photos to `Pictures/Footnote Walk`
- `sqflite` for local persistence
- `share_plus` for GPX and image sharing

## Project Structure

```text
lib/
  models/
    walk_models.dart
  screens/
    home_screen.dart
    record_walk_screen.dart
    walk_detail_screen.dart
  services/
    active_walk_service.dart
    gpx_exporter.dart
    location_tracker.dart
    photo_storage.dart
    session_photo_finder.dart
    share_card_exporter.dart
    walk_repository.dart
  widgets/
    session_photo_manager_sheet.dart
    walk_map_preview.dart
    walk_photo_image.dart
```

## Data Model

The app uses a local SQLite database:

```text
walk_sessions
track_points
walk_photos
```

Photos are not stored as blobs in SQLite. The DB stores photo paths and metadata only. Original photo files stay in Android gallery storage or wherever the user selected them from.

## Photo Behavior

- Photos taken inside the app are saved through Android MediaStore under `Pictures/Footnote Walk`.
- Photos selected from gallery are linked to the session by file path.
- Deleting a walk removes only DB records, not original image files.
- If a linked photo is deleted from the gallery, the app shows a missing-photo placeholder and lets the user remove the broken link.

## GPX

GPX export includes:

- route track points as `trk/trkseg/trkpt`
- linked photos as `wpt` waypoints

Active sessions also write a draft GPX file in app documents storage.

## Android Setup

Required manifest permissions are already included in:

```text
android/app/src/main/AndroidManifest.xml
```

Relevant permissions:

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
```

## Run

```powershell
$env:Path="C:\Users\dukim\tools\flutter\bin;$env:Path"
flutter pub get
flutter analyze
flutter test
flutter run -d <device-id>
```

Build and install debug APK:

```powershell
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

## Current Limitations

- Background tracking is not yet implemented as a native Android foreground service.
- Tracking continues after leaving the recording screen only while the Flutter app process remains alive.
- Gallery photo matching depends on Android media timestamps and user-granted photo permissions.
- Map image sharing captures the currently visible detail map area, not a polished share card.
- Tile usage should move to a production tile provider before public release.

## Next Steps

- Android foreground service for reliable screen-off/background recording
- Better GPS smoothing and noisy point filtering
- Optional EXIF GPS support for photo marker placement
- Backend sync with local-first, session-level upload
- Release signing configuration

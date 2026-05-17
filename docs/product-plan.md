# Product Plan

## Product Direction

Footnote Walk is an Android-first dog walking journal. The core experience is a map, not a feed: each walk becomes a session with a route, photo points, duration, distance, and GPX export.

## MVP User Flow

1. Open the app and see recent walks.
2. Browse walks by date.
3. Switch between list mode and map-thumbnail mode.
4. Tap a walk map thumbnail to open the session.
5. Inspect the full route and photo markers on the map.
6. Tap a photo marker or photo strip item to enlarge it.
7. Start a new walk from the floating action button.
8. End the walk and save it as one session.
9. Export the session as GPX.

## MVP Screens

- Home: today's summary, date chips, list/grid switch, walk cards with map thumbnails.
- Walk detail: large interactive map, route polyline, photo markers, stats, photo strip, GPX share.
- Recording: full-screen map, live route, distance/time panel, pause/resume, add photo, end walk.

## Next Engineering Milestones

1. Add Android foreground service for reliable screen-off recording.
2. Generate and persist small local thumbnails for faster list rendering.
3. Export GPX plus photos as a ZIP package.
4. Add route smoothing and GPS noise filtering.
5. Add monthly calendar and search.
6. Add optional dog profile and per-dog walk filters.

## Implemented In This Workspace

- SQLite source of truth for sessions, track points, and photos.
- `geolocator` location tracking in the recording screen.
- `image_picker` camera capture and local photo copy.
- Home reload after a saved walk.
- Photo markers support both network sample images and local camera files.

## Data Strategy

Use SQLite as the source of truth and GPX as an export format. This keeps the app fast for browsing, filtering, and map thumbnails while preserving compatibility with external apps.

## Tile Strategy

The prototype uses OpenStreetMap tiles for development. For a public app, use a production tile provider based on OSM data to avoid relying on the public OSM tile infrastructure.

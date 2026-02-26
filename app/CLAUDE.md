# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter golf tracking application called "ugly_slice" that helps golfers track their rounds, view course maps, and maintain scorecards. The app integrates with OpenStreetMap data via Overpass API to display golf course information including holes, tees, greens, and fairways.

## Development Commands

### Build and Run
- `flutter run` - Run the app in development mode
- `flutter build android` - Build Android APK
- `flutter build ios` - Build iOS app
- `flutter build linux` - Build Linux desktop app

### Code Quality
- `flutter analyze` - Run static analysis (uses `analysis_options.yaml` with flutter_lints)
- `flutter test` - Run widget tests (located in `test/`)
- `flutter pub get` - Install dependencies
- `flutter pub upgrade` - Upgrade dependencies

## Architecture Overview

### Navigation Structure
The app uses a bottom navigation bar with three main sections:
- **Play**: Course selection and round play (`play_page.dart`, `course_selection_page.dart`, `round_page.dart`)
- **Scorecards**: Historical round data and scorecard management (`scorecard_page.dart`)
- **Settings**: User preferences and configuration (`settings_page.dart`)

Entry point: `main.dart` → `MainScreen` widget with `BottomNavigationBar`

### Core Data Models (`lib/models/`)

#### Geographic Data
- **Course**: Golf course information parsed from OpenStreetMap/Overpass API data
  - Contains nodes, ways, relations from OSM
  - Parses holes, tees, greens, fairways from geographic data
  - Supports complex geometric calculations using `dart_jts` library
- **Hole**: Individual hole with par, handicap, pin location, tees, and boundaries
- **Tee**: Starting position with color, distance, course/slope ratings
- **Node/Way/Relation**: OpenStreetMap data structures for geographic features

#### Game Data
- **Round**: A played round linking player, course, date, and hole plays
- **HolePlay**: Individual hole performance with shots taken
- **Shot**: Individual stroke with start/end locations, club used, lie type
- **Player**: Basic player information
- **Club**: Golf club specifications (brand, type, loft, etc.)

### Key Features

#### Map Integration
- Uses `flutter_map` for interactive course visualization
- `geolocator` for GPS positioning
- Supports both standard and satellite tile layers
- Real-time distance calculations to targets
- Ruler tool for measuring distances on course

#### Course Data Management
- Loads course list from local JSON (`nz-course-compact.json`)
- Fetches detailed course data via Overpass API
- Caches course data locally using `path_provider`
- Supports both 9-hole and 18-hole courses

#### Multi-platform Support
Configured for:
- Android (`android/`)
- iOS (`ios/`)
- Linux (`linux/`)
- macOS (`macos/`)
- Windows (`windows/`)
- Web (`web/`)

## Asset Management
- Course data: `nz-course-compact.json` (New Zealand golf courses)
- Icons: `assets/pizza-slice.png` (app launcher icon)
- Flutter launcher icons configured via `flutter_launcher_icons` package

## Key Dependencies
- `flutter_map: ^8.2.2` - Interactive maps
- `latlong2: ^0.9.1` - Geographic coordinates
- `geolocator: ^10.1.0` - GPS positioning
- `http: ^1.6.0` - API requests to Overpass
- `dart_jts: ^0.3.0+1` - Geometric calculations
- `path_provider: ^2.1.5` - Local file storage
- `collection: ^1.19.1` - Collection utilities

## Development Notes

### Code Style
- Uses standard Flutter/Dart conventions as enforced by `flutter_lints`
- No custom lint rules beyond the package defaults

### Testing
- Basic widget test setup in `test/widget_test.dart`
- Note: The existing test references `MyApp` but should reference `MaterialApp` from `main.dart`

### Data Flow
1. Course selection from local JSON list
2. Detailed course data fetched from Overpass API or loaded from cache
3. Round creation with selected course and player
4. Real-time GPS tracking during play
5. Shot and score recording per hole
6. Scorecard generation and storage

### Geographic Calculations
The app handles complex golf course geometry:
- Hole boundaries and fairway definitions
- Distance calculations from current position to pins/targets
- Support for overlapping holes and shared fairways
- Tee selection based on color/difficulty ratings
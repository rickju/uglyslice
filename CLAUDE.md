## Project Overview

**ugly-slice** — Flutter golf tracking app for Android and iOS.

Helps golfers track rounds, view course maps (OpenStreetMap/Overpass API), record shots with GPS, detect swings via Apple Watch or android watch, and calculate WHS handicap.

- **Testing**: use location Wellington, NZ (Karori GC). use linux desktop app.
- **Target market**: Global

## Repository Structure

```
app/          Flutter app (Dart)
shared/       Shared Dart package (Round/Shot/Club models)
supabase/     Supabase migrations and config
```
## Architecture

### Navigation (bottom tab bar)
| Tab | Page | File |
|-----|------|------|
| Play | `CourseSelectionPage` | `course_selection_page.dart` |
| Scorecards | `RoundsListPage` | `rounds_list_page.dart` |
| Settings | `SettingsPage` | `settings_page.dart` |

Entry point: `main.dart` → `MainScreen` (bottom nav) → tab pages.

Auth gate: `AuthPage` (Supabase anonymous + Apple Sign-In).

### State management
Plain `setState` / `StatefulWidget`. No Riverpod or Bloc.

Global singletons in `main.dart`: `db` (AppDatabase), `syncService`, `courseSyncService`.

### Key pages
- **`round_page.dart`** — main round tracking: map (flutter_map), GPS, shot recording, +/- score input, hole navigation, Watch integration
- **`course_selection_page.dart`** — course list (sorted by proximity via IP geolocation), recent rounds panel
- **`round_scorecard_page.dart`** — per-round scorecard: Hole/Par/Score/+−/Putts/GIR/FIR/Clubs table
- **`settings_page.dart`** — WHS handicap card, course rating overrides, seed test data, sign out

### Models
- **`shared/`**: `HolePlay`, `Shot`, `Club`, `Player` (shared with Watch)
- **`app/lib/models/`**: `Round`, `Course`, `Hole`, `Tee` (parsed from OSM), `Scorecard`

### Data flow
1. Course list loaded from a local `assets/*.json` file (todo: file size concern?)

-  Lazy populate — don't block the UI on sync and let the user see an empty list with a.  should: show nearest courses first. should: show progressively while only partial list returned.

2. Detailed course geometry fetched from Overpass API and cached via Drift
3. Round created locally → synced to Supabase via `syncable` package
4. GPS position streamed via `geolocator`; Watch swing events via `WatchService`
5. On exit, `_buildHolePlaysFromStrokes()` saves only holes with user-entered scores

### Database
Drift (SQLite). Tables: `Rounds`, `Courses`, `CourseListTable`. Schema version 2.
DB file location: `~/Documents/ugly_slice.sqlite` (Linux), app data dir (Android/iOS).

### Apple Watch
SwiftUI watch app in `ios/WatchApp/` (4 Swift files). Registered as a companion target in `Runner.xcworkspace`. Communicates via `WatchConnectivity`:
- iPhone → Watch: hole number, par, distance to pin
- Watch → iPhone: swing detected (hit event)

## UI Guidelines

- Material 3, dark theme
- High contrast for outdoor visibility
- Minimum 48×48 tap targets (glove-friendly)
- Large score display on round page

## Code Style

- Standard `flutter_lints` — run `flutter analyze` before committing
- No unused imports or variables
- Prefer `const` constructors
- Use `debugPrint` for logging (stripped in release)

## Unit Tests

- All features and key functions should be testable headless (no Flutter app running)
- Test-First: Before refactoring logic, write or update a unit test first
- Verify: After any edit, run `flutter test` (in `app/`) to confirm tests pass
- Destructive testing: try to crash the logic via invalid inputs, simulated network delays, or concurrent operations
- Before modifying a feature, write failing unit tests covering edge cases (negative scores, empty input, out-of-range values), then implement until all tests pass

- unit test: from the point view of a user, without flutter ui, set up different scenarios, and check the result of our logic. i want to freely define/add/custom scenario in the future. I want to separate flutter view from our logic, so the unit test can check the result of core logic. like all numbers presented to the user 
  -- a ViewModel layer — pure Dart classes that hold all  display logic, extracted out of the Flutter widgets. Widgets just render what the VM  exposes.            


## Error Handling

## Backend

A background daemon work to keep course data up to date:

course data process passes: fetch, parse, enrich

- fetch json from overpass
- parse
- coure integrity check
- course enrich:
	-- Use AI and web search to fill gaps in Overpass data (hole numbers, course ratings, hole handicaps)
	- Scrape official club websites for missing metadata
	- AI agent to validate DB data integrity (tee/fairway/pin locations, boundaries, playing lines)
	- Monitor for newly opened or closed courses
	- Track Overpass JSON change history

## See Also

Also check `db.md` and `tee-naming.md`.

## Known Issues

- with royal wellington, 27 holes. overpass json confused our parser. todo: make sure daemon and parser can work with similar complicated courses
- todo: many 9holes course, a 18hole play means play the 9holes twice. sometimes with different tee or green, sometime sharing. mostlikely sharing fairway. should: reflect this in our data structure?
- todo: with overpass json, how to remove items that is a driver range or mini golf etc.





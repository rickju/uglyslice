
## Database structure and summary

### Overview

Two storage layers:
- **Local**: SQLite via Drift (`ugly_slice.sqlite`) — primary source of truth during a round
- **Remote**: Supabase PostgreSQL — sync for backup and multi-device; last-write-wins on `updated_at`

Schema version: **2** (Drift). Supabase has 6 migration files in `supabase/migrations/`.

---

### TABLE: `rounds`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | UUID v4 |
| `user_id` | TEXT? | Supabase auth user; nullable for anonymous/offline |
| `updated_at` | DATETIME | Sync conflict resolution — discard if older |
| `deleted` | BOOLEAN | Soft delete (default false) |
| `player_name` | TEXT | e.g. `"Rick"` |
| `player_handicap` | REAL | Snapshot at round start (default 0.0) |
| `course_id` | TEXT | OSM relation ID e.g. `"course_747473941"` |
| `course_name` | TEXT | Denormalized for display |
| `date` | DATETIME | Round start date |
| `status` | TEXT | `in_progress` \| `completed` |
| `data` | TEXT | JSON blob — see structure below |

**`data` JSON structure:**
```json
{
  "holePlays": [
    {
      "holeNumber": 1,
      "shots": [
        {
          "startLat": -41.288, "startLng": 174.689,
          "endLat": -41.285,   "endLng": 174.690,
          "lieType": "fairway",
          "clubType": "driver", "clubName": "Driver",
          "clubBrand": "TaylorMade", "clubNumber": "1", "clubLoft": 10.0,
          "isTeeShot": true, "penalty": false, "isRecovery": false
        }
      ]
    }
  ],
  "trail": [[-41.288, 174.689], [-41.287, 174.690]],
  "hitPositions": [[-41.288, 174.689]]
}
```

Key facts:
- `score` is not stored — it's `shots.length` per `HolePlay`
- `endLocation` on shots is optional (null = not yet chained)
- `trail` = GPS breadcrumb path for the whole round
- `hitPositions` = watch-detected swing locations
- Holes not played by the user are stored as `{"holeNumber": N, "shots": []}` (empty)

---

### TABLE: `courses`

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT PK | OSM relation ID e.g. `"course_747473941"` |
| `name` | TEXT | Course name |
| `course_doc` | TEXT | JSON — Course fields (boundary, teeInfos, etc.) |
| `holes_doc` | TEXT | JSON array — Hole definitions (par, pin, tees, fairways) |
| `updated_at` | INTEGER | Milliseconds since epoch |

Populated by `CourseSyncService` which fetches from Overpass API.

---

### TABLE: `course_list`

| Column | Type | Notes |
|--------|------|-------|
| `id` | INTEGER PK | OSM element ID |
| `name` | TEXT | Course name |
| `type` | TEXT | `node` \| `way` \| `relation` |
| `lat` | REAL | Centroid latitude |
| `lon` | REAL | Centroid longitude |
| `updated_at` | DATETIME | Added in schema v2 |

Lightweight index for course search and proximity sorting. Loaded from `assets/nz-course-compact.json` on first run.

---

### Local file storage

| File | Location | Purpose |
|------|----------|---------|
| `ugly_slice.sqlite` | `~/Documents/` (Linux), app data dir (Android/iOS) | Main DB |
| `course_ratings.json` | App documents dir | User-entered course/slope ratings for WHS handicap |

---

### Dart model hierarchy

```
Round
├── Player          (name, handicap)
├── Course          (id, name — stub; full geometry in courses table)
├── List<HolePlay>
│   └── List<Shot>
│       └── Club?   (name, brand, number, type, loft)
├── List<LatLng>    trail
└── List<LatLng>    hitPositions

ClubType: driver | wood | hybrid | iron | putter
LieType:  fairway | rough | sand | green
```

---

### Supabase sync

- Rounds with `user_id = null` are local-only until `fillMissingUserIdForLocalTables()` runs
- Outgoing sync uses `upsert(onConflict: 'id,user_id')` — requires unique constraint on Supabase `(id, user_id)`
- Incoming sync via Supabase Realtime; only inserts/replaces, never deletes local rows
- Soft-deleted rounds (`deleted = true`) are synced as-is; filtering happens in queries


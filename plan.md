# Backend Daemon: Course Info Updater

## Context

The Supabase `courses` table holds parsed OSM geometry for golf courses worldwide. Data quality is inconsistent: OSM rarely includes course/slope ratings or hole handicaps, geometry integrity issues exist silently, and the dataset drifts from reality as courses open/close/change. This daemon keeps the DB accurate and complete, running unattended.

**Deployment**: Local machine (`cron` / `dart run`) for now; designed to be portable to Cloud Run later.

---

## What Already Exists (`backend/`)

| File | Purpose |
|------|---------|
| `bin/cli.dart` | Interactive CLI (ingest-course, reparse, check-integrity, etc.) |
| `bin/fetch_course_list.dart` | Fetches course list from Overpass → compact JSON + SQLite |
| `lib/ingest_core.dart` | Fetch Overpass → parse → upsert Supabase; batch ingest functions |
| `lib/course_parser.dart` | Overpass JSON → `ParsedCourse` (holes, tees, greens, fairways) |
| `lib/course_integrity.dart` | Rule-based checks: hole count, par, green/tee presence, pin-in-green, routing length |
| `lib/raw_json_store.dart` | Append-only SQLite store of raw Overpass responses (history preserved) |
| `lib/overpass.dart` | Overpass data models (Node/Way/Relation) |
| `lib/supabase_client.dart` | Thin REST client (service-role key, `select`/`upsert`) |

---

## Four Jobs

| Job | Frequency | Description |
|-----|-----------|-------------|
| **Discover** | Weekly | Fetch course list from Overpass for all regions; add new courses to `course_list`; flag missing ones |
| **Ingest** | Daily | Re-fetch courses where Overpass data has changed (MD5 hash diff); parse + upsert `courses` |
| **Audit** | After every ingest | Run `checkIntegrity()` on updated courses; persist issues to `course_issues` table |
| **Enrich** | On demand / queue | Web search club website → scrape HTML → Claude Haiku extracts ratings/handicaps → patch `courses` |

---

## New Supabase Tables

### Migration 007 — `course_issues`
Stores integrity issues detected by the audit job. Auto-resolved when re-ingest fixes them.
- `course_id`, `severity` (error/warning), `message`, `hole_number`, `detected_at`, `resolved_at`

### Migration 008 — `enrich_queue`
Queue of courses needing enrichment (missing ratings, handicaps).
- `course_id`, `course_name`, `fields` (JSONB), `status` (pending/in_progress/done/failed)

### Migration 009 — `overpass_hash`
Column added to `courses` table. MD5 of raw Overpass response — used for change detection to avoid unnecessary re-ingests.

---

## New Files

| File | Purpose |
|------|---------|
| `backend/bin/daemon.dart` | Entry point; scheduler loop with configurable intervals |
| `backend/lib/scheduler.dart` | Job runner with error catching, retry backoff, structured logging |
| `backend/lib/enricher.dart` | Web search → HTML scrape → Claude Haiku extract → Supabase patch |
| `backend/lib/web_search.dart` | Brave Search API HTTP client |
| `backend/lib/claude_client.dart` | Claude API HTTP client (messages endpoint) |

## Modified Files

| File | Change |
|------|--------|
| `backend/lib/ingest_core.dart` | Add hash-based change detection; run integrity after ingest; write issues |
| `backend/lib/supabase_client.dart` | Add `insert()`, `patch()`, `delete()` methods |
| `backend/pubspec.yaml` | Add `crypto` dependency |
| `supabase/migrations/` | Add 007, 008, 009 |

---

## Enrichment Flow (per course)

```
1. web_search.dart  → Brave Search: "{name} golf scorecard ratings handicaps"
2. HTTP GET         → fetch top result URL (club official site)
3. Strip HTML       → extract plain text from response body
4. claude_client.dart → Claude Haiku: extract structured JSON (hole handicaps, tee ratings)
5. Validate         → 18 handicaps 1–18 unique, yardages 50–700m, ratings 60–80
6. Supabase patch   → update courses.holes_doc, courses.course_doc
7. enrich_queue     → mark as done
```

---

## Running the Daemon

```bash
# Install deps
cd backend && dart pub get

# Set env vars
export SUPABASE_URL=...
export SUPABASE_SERVICE_ROLE_KEY=...
export ANTHROPIC_API_KEY=...
export BRAVE_SEARCH_API_KEY=...

# Dry run (no writes)
dart run bin/daemon.dart --dry-run

# Run once (all jobs)
dart run bin/daemon.dart --once

# Run continuously (scheduler loop)
dart run bin/daemon.dart

# Add to crontab for daily ingest
# 0 2 * * * cd /path/to/backend && dart run bin/daemon.dart --once >> /var/log/ugly_slice_daemon.log 2>&1
```

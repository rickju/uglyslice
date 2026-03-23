# Tee Platform Design

## Problem

Golf courses worldwide use wildly different tee naming conventions.
Hard-coding `red / white / blue` breaks for courses that use numbers,
roman numerals, proper names, or gender labels.

**Core principle:** decouple *display name* from *difficulty order*.

---

## Tee Data Model

| Field | Type | Example | Notes |
|---|---|---|---|
| `id` | UUID | `tee_001` | |
| `name` | String | `"Gold"`, `"Tee 1"`, `"Championship"` | What the user sees |
| `hex_color` | String | `"#FFD700"` | For rendering the colour dot |
| `tee_type` | Enum | `color \| number \| name \| pro` | Which naming scheme the course uses |
| `sort_order` | Integer | `1, 2, 3…` | Far → near; **never sort alphabetically** |
| `gender_hint` | Enum | `mens \| ladies \| universal` | Advisory only |
| `rating` | Double | `72.4` | Course rating |
| `slope` | Integer | `131` | Slope rating |
| `total_distance` | Integer | `6800` | In yards (or metres) |

---

## Naming Schemes

### Traditional Colors
Most common. Name maps directly to a standard colour dot.

> Red · Yellow · White · Blue · Black

### Numeric / Roman Numeral
Common in Europe and private clubs.

> 1, 2, 3, 4 — or — I, II, III, IV

Colour is secondary; UI can default to grey and show the number prominently.

### Member-Specific Names
Reflects difficulty tiers rather than colours.

> Championship · Tournament · Member · Forward

---

## UI Rendering

Always render from `hex_color` (dot) + `name` (label), regardless of scheme:

- **Colour scheme** → `● Blue`
- **Numeric scheme** → `● Tee II`
- **Named scheme**  → `● Tiger`

---

## Sorting

Sort by `sort_order` or `total_distance` (longest = furthest back), never alphabetically.

Optionally add `is_active` to hide tees closed for winter or maintenance.

---

## Current Model vs Design

| Design | Current (`TeeInfo`) | Gap |
|---|---|---|
| `name` | `name` | ✓ |
| `hex_color` | `color` (string) | No hex convention enforced |
| `rating` / `slope` | `courseRating` / `slopeRating` | ✓ |
| `total_distance` | `yardage` | ✓ |
| `tee_type` | — | Missing |
| `sort_order` | — | Missing; could derive from `yardage` |
| `gender_hint` | — | Missing; unlikely in OSM data |

`tee_type`, `sort_order`, and `gender_hint` are the gaps.
`sort_order` is the most impactful — derive from `yardage` descending until explicit data is available.

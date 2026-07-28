---
name: analyze-weekly-workouts
description: Use when the user wants to review how a completed week of training actually went against the plan (e.g. "how did last week go", "analyze my training", "compare planned vs actual pace"). Reads the confirmed spec from specs/weekly-workouts/, downloads the matching completed activities via the garmin MCP server, and writes a planned-vs-actual comparison to data/weekly-workouts/.
---

# Analyzing a completed week's workouts

Goal: for a week that's already been planned (a file exists in
`specs/weekly-workouts/`) and has now finished, pull the runner's actual
completed activities from Garmin Connect and compare them against what was
planned — pace, distance, duration — and save that comparison to
`data/weekly-workouts/`.

This skill only reads from Garmin (activities, splits) — it never builds,
schedules, or modifies a workout. That's `creating-garmin-workout`'s job,
and is a separate concern.

## Step 1 — Validate the MCP connection

Same check as `creating-garmin-workout` Step 1: confirm `garmin` tools
(e.g. `get_full_name`, `get_activities_by_date`) are loaded, call
`get_full_name`, and handle a stale/expired token the same way (retry once,
then tell the user to re-run `garmin-mcp-auth` themselves if the refresh
token is dead). Don't proceed to Step 2 until this succeeds.

## Step 2 — Pick which week(s) to analyze

List `specs/weekly-workouts/*.md`. A week is eligible once its Sunday has
already passed (don't analyze a week still in progress). For each eligible
spec file, check whether a same-named file already exists in
`data/weekly-workouts/` — if so, it's already been analyzed; skip it
unless the user explicitly asks to redo it.

- If the user named a specific week (a date, "last week", etc.), resolve
  that to its spec file.
- If exactly one eligible, not-yet-analyzed week exists, just use it.
- If more than one is eligible and unanalyzed, ask the user which week(s)
  to run rather than silently processing all of them — this is normally a
  weekly cadence, so a backlog usually means something was skipped and is
  worth surfacing rather than assuming.

## Step 3 — Read the spec

Parse the matched `specs/weekly-workouts/MM-DD-YYYY.md` file. It already
distinguishes (per `extract-workouts` Step 3's classification):

- **Workout days** — full Warm-up/Main set/Cool-down breakdown with
  resolved paces, named `MM/DD/YYYY`.
- **Easy/recovery days** — date, distance, resolved pace, no name (no
  Garmin workout was built for these).
- **Off days** — nothing planned; skip entirely, don't look for an
  activity.

## Step 4 — Match each planned running day to a completed activity

For each planned running day's date, call `get_activities_fordate(date)`
(or `get_activities_by_date` narrowed to that single day) filtered to
running.

- **Workout days**: a structured workout built by `creating-garmin-workout`
  and completed on the watch produces a Garmin Connect activity
  auto-named `"<device/location> - MM/DD/YYYY"` (confirmed 2026-07-28,
  e.g. workout `"07/21/2026"` → completed activity `"Aspen -
  07/21/2026"`) — match on the `MM/DD/YYYY` substring first. If exactly
  one running activity exists that day regardless of name, treat it as the
  match too.
- **Easy/recovery days**: no such name to match against — if exactly one
  running activity exists that day, use it.
- **Multiple candidates, no clear match**: ask the user which activity is
  the right one rather than guessing.
- **No activity found** for a planned running day: record it as **missed**
  — don't error, don't skip the rest of the week.
- An activity on an **off** day is unplanned — note it in the report but
  don't score it against anything.

## Step 5 — Pull actual data

- **Easy/recovery days**: `get_activity(activity_id)` is enough — overall
  `distance_meters`, `duration_seconds`, `avg_speed_mps`, `avg_hr_bpm`.
- **Workout days**: call `get_activity_typed_splits(activity_id)`. For a
  workout completed as built, this returns phase-tagged splits in
  chronological order — confirmed types: `INTERVAL_WARMUP`,
  `INTERVAL_ACTIVE` (one per main-set rep), `INTERVAL_RECOVERY` (one per
  recovery jog), `INTERVAL_COOLDOWN` — each with its own `distance`,
  `duration`, `averageSpeed` (m/s), `averageHR`/`maxHR`.
  - Map `INTERVAL_ACTIVE` splits to planned main-set reps **in order**. For
    an alternating-pace plan (e.g. odd reps @ MP, even reps @ HM), rep *N*
    from Step 3's spec maps to the *N*th `INTERVAL_ACTIVE` split.
  - Map `INTERVAL_WARMUP` → planned warm-up, `INTERVAL_COOLDOWN` → planned
    cool-down.
  - If a plan step had no distinct recovery pace called out (e.g. a
    straight MP block followed immediately by an MP+ block with no jog
    between), there may be no `INTERVAL_RECOVERY` split between the
    corresponding `INTERVAL_ACTIVE` splits — that's expected, not an error.
  - If `get_activity_typed_splits` doesn't return any `INTERVAL_*` types
    (the run wasn't executed against the structured workout on the watch,
    or the device didn't tag it), fall back to `get_activity_splits`
    (auto-lap km/mile splits) for a best-effort comparison, and say in the
    report that the phase-level match is approximate rather than exact.

## Step 6 — Compare planned vs. actual

Convert `averageSpeed`/`avg_speed_mps` (m/s) to pace: `1609.344 /
speed_mps` = seconds per mile, format `M:SS`. For each planned segment
(whole easy day, or warm-up/each main-set rep/cool-down for a workout day):

- Planned pace (or range) vs. actual pace, and the delta.
- Planned distance/duration (end condition) vs. actual distance/duration.
- Carry `averageHR`/`maxHR` through as supporting context where available
  — not the primary comparison, but useful for judging effort vs. pace
  (e.g. a rep hit pace but at a much higher HR than the rest).

Also roll up a weekly total: planned weekly mileage vs. actual completed
mileage (missed days count as 0 actual), and how many of the planned
running days were completed vs. missed.

## Step 7 — Write the analysis file

Save to `data/weekly-workouts/MM-DD-YYYY.md`, same Monday-dated filename as
the spec file it analyzes. Include:

- A per-day table: planned vs. actual distance and pace, delta, missed/
  unplanned flags.
- For each workout day, the phase-by-phase breakdown from Step 6 (mirroring
  the Warm-up/Main set/Cool-down shape of the spec it's compared against).
- The weekly mileage roll-up.
- A short plain-language summary of what stands out (e.g. "MP reps ran
  8-12 sec/mi faster than target," "missed Friday's easy run," "long run
  cool-down drifted slow, likely fatigue").

Commit and push just this one new/updated file to `origin main`. Check
`git status`/`git diff --cached` first and stage only this file by path —
don't sweep in unrelated pending changes in the repo.

## Step 8 — Report back

Summarize for the user: which week was analyzed, where the file was
saved, the weekly mileage roll-up, and the two or three most notable
planned-vs-actual findings. Flag any missed days or activities that
couldn't be confidently matched.

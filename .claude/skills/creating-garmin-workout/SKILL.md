---
name: creating-garmin-workout
description: Use when the user asks to create, build, or schedule a structured workout (run, walk/run intervals, strength, etc.) on Garmin Connect. Validates the `garmin` MCP connection first, then builds and optionally schedules the workout via the garmin MCP tools.
---

# Creating a Garmin Connect workout

Goal: turn a workout spec into a structured workout on Garmin Connect,
synced to the user's watch, using the `garmin` MCP server
([Taxuspt/garmin_mcp](https://github.com/Taxuspt/garmin_mcp)).

## Step 1 — Validate the MCP connection

Do this before anything else. The `garmin` MCP server is registered via
`claude mcp add` and authenticates using OAuth tokens cached at
`~/.garminconnect` (not a password Claude ever handles).

1. Confirm the `garmin` tools are actually loaded in this session — look for
   tools like `get_full_name`, `get_workouts`, `create_run_workout`. If none
   are present, the server likely wasn't loaded because it was registered
   *after* this session started. Tell the user to start a new session (MCP
   servers load at session start) and stop here.
2. Call `get_full_name`. This is the same lightweight call the auth CLI uses
   to verify a session — cheap and side-effect-free.
   - **Success** (returns a name) — connection is good, continue to Step 2.
   - **Auth/401 error** — the cached access token is stale. `python-garminconnect`
     normally refreshes it transparently from the stored refresh token on the
     next call, so retry `get_full_name` once. If it still fails, the refresh
     token itself is likely dead (garth tokens last ~6 months). Tell the user
     to re-run authentication themselves:
     ```
     uvx --python 3.12 --from git+https://github.com/Taxuspt/garmin_mcp garmin-mcp-auth
     ```
     Do not ask the user to paste their Garmin email/password into the chat —
     that command prompts for credentials locally and they stay out of this
     conversation entirely, per the credential-handling rules in the global
     CLAUDE.md.
   - **Rate-limited (429)** — Garmin is throttling the IP. Tell the user and
     stop; don't retry in a loop.
3. Only proceed to Step 2 once `get_full_name` has returned successfully.

## Step 2 — Input contract

This skill is client-agnostic — it doesn't matter whether a workout spec
comes from a human typing details inline, from another skill, or from a
spec file on disk. Treat it like an API: any caller handing over the
following shape is equally valid, and this skill has no dependency on
where it came from.

**Per workout:**

- **Date** and **name** (`MM/DD/YYYY`, zero-padded — or use a name already
  given if the input supplies one).
- **Structure**, broken into three phases:
  - **Warm-up** — a target pace (or HR zone/effort, if that's what the
    input gives instead — pace is the common case).
  - **Main set** — one or more segments, each with its own end condition
    (distance or time, whichever the input specifies for that segment) and
    its own target pace.
  - **Cool-down** — a target pace.
- Optional: a scheduling date.

If the input is incomplete or a segment's pace/distance/time is ambiguous,
ask rather than inventing numbers — this applies whether a human is
driving interactively or the input came from somewhere else and is missing
a field.

## Step 3 — Check for an existing workout first

Before uploading, check whether this workout already exists — automatic
callers (e.g. a pipeline re-triggered off the same source) can otherwise
create silent duplicates, since `upload_workout`/`upload_workouts` has no
idempotency of its own (unlike `schedule_workout`, which is a safe no-op if
already scheduled for that date).

1. If a scheduling date was given, call `get_scheduled_workouts(date, date)`
   for that date — anything returned means a workout is already scheduled
   that day.
2. Call `get_workouts()` (full library summary list) and check for a name
   match against this workout's name.

If either check finds a match, stop and ask the user: **skip** this day
(leave the existing workout alone), **replace** it (`delete_workout` on the
old `workout_id`, then continue to Step 4 with the new spec), or **create
anyway** (an intentional second workout — proceed to Step 4 unmodified). Only
skip this check silently when neither call finds anything.

## Step 4 — Build the workout

**The four high-level builder tools cannot represent this.** Read directly
from `garmin_mcp` source (`workout_builders.py`): `create_run_workout` and
`create_walk_run_workout` hardcode warmup/cooldown as **time-based**
(`conditionTypeId: 2`) and only ever emit `heart.rate.zone` targets — there
is no parameter path to a lap-button end condition or a pace target. So
they only apply to a plain HR-zone/no-pace session with no lap-button
requirement. Every workout with a real pace target (the normal case) goes
through raw JSON via `upload_workout`, built as exactly three phases:

- **Warm-up** — `ExecutableStepDTO`, `stepType {1, "warmup"}`,
  `endCondition {1, "lap.button"}` (include a placeholder
  `endConditionValue`, e.g. `1.0` — Garmin's schema wants a non-null value
  even though it's ignored for a lap-button end), `targetType {6,
  "pace.zone"}` with `targetValueOne`/`targetValueTwo` = the warm-up pace
  range in m/s (see conversion below).
- **Main set** — one or more `ExecutableStepDTO` steps (or a
  `RepeatGroupDTO` wrapping them, for repeated reps), each with
  `endCondition {3, "distance"}` (meters — miles × 1609.344, km × 1000) or
  `{2, "time"}` (seconds), matching whichever the input specifies for that
  segment, and `targetType {6, "pace.zone"}` with that segment's own pace
  range in m/s. For an alternating multi-pace rep pattern (e.g. odd reps at
  one pace, even at another), use a `RepeatGroupDTO` whose child steps
  cover one full "odd+even" pair, repeated `numberOfIterations` times —
  don't flatten it into reps all forced onto one pace.
- **Cool-down** — same shape as warm-up, `stepType {2, "cooldown"}`.

**Pace → m/s**: `targetValueOne`/`targetValueTwo` = `1609.344 /
seconds_per_mile`. **Confirmed** (2026-07-26): uploaded a real workout with
this conversion — including a `RepeatGroupDTO` with alternating per-rep
paces — and `get_workout_by_id` returned the exact same
`target_value_low`/`target_value_high` and `end_condition_value`
(distance/time) that were sent, with the 5-iteration repeat count intact.
Still worth a quick `get_workout_by_id` check after upload as a sanity
check, but the m/s unit itself is no longer an open question.

**Slot order matters for display, independent of the m/s math above**:
Garmin Connect's UI reads `targetValueOne` then `targetValueTwo` and
converts each straight to a pace number, in that order, without re-sorting
— and since pace is the *inverse* of speed, naively putting the
numerically-lower speed value in `targetValueOne` (as an early version of
this note said) makes the *slower* pace display first, e.g. "7:29 - 6:30"
(highest-lowest — confirmed wrong via real Garmin Connect UI on
2026-07-26). For a pace range to display conventionally as
lowest-highest (e.g. "6:30 - 7:29"), put the **faster pace's speed (higher
m/s) in `targetValueOne`, the slower pace's speed (lower m/s) in
`targetValueTwo`** — the opposite of what the field names suggest. This
only matters for actual ranges; for an exact single-pace target (e.g. a
goal-pace rep with no range), `targetValueOne` and `targetValueTwo` are
just the same value and slot order is moot.

**Known Garmin ID gotchas** — the numeric ID is authoritative, not the key
string; a mismatch means Garmin silently reinterprets it as whatever the ID
maps to:

- End conditions: `lap.button=1, time=2, distance=3, calories=4, power=5,
  heart.rate=6, iterations=7, fixed.rest=8, fixed.repetition=9, reps=10,
  training.peaks.tss=11`. (Heart-rate end conditions must use `6`, not `4`
  which is calories.)
- Step types: `warmup=1, cooldown=2, interval=3, recovery=4`.
- Target types: `no.target=1, power.zone=2, heart.rate.zone=4, pace.zone=6`
  (id `6` is sport-context-dependent — running/swim get `"pace.zone"`,
  cycling gets `"power.between"`).
- `RepeatGroupDTO` steps must include `endCondition {conditionTypeId: 7,
  conditionTypeKey: "iterations"}` plus `numberOfIterations` — omitting
  `conditionTypeId` silently corrupts the repeat group (Garmin falls back
  to an unrelated condition and drops the iteration count).

Each call returns `{"status": "success", "workout_id": ...}` (or an error)
— capture the `workout_id` for the next step.

## Step 5 — Schedule it (if a date was given)

- Single workout: `schedule_workout(workout_id, calendar_date)` with
  `calendar_date` as `YYYY-MM-DD`.
- Multiple workouts across a week: `schedule_week` (builder tools' variant)
  or `schedule_workouts` with a list of `{workout_id, calendar_date}` pairs.

If no date was given, skip this step — leave the workout created but
unscheduled, and say so.

## Step 6 — Report back

Summarize plainly:

- Workout name and `workout_id`.
- Structure (warm-up/main set/cool-down, paces) in a sentence or two.
- Scheduled date, or "not scheduled" if Step 5 was skipped.
- Whether an existing-workout collision was found in Step 3, and what was
  done about it (skipped / replaced / created anyway).
- Remind the user it'll show up on their watch after the next sync.

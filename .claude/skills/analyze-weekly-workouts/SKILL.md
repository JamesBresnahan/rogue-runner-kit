---
name: analyze-weekly-workouts
description: Use when the user wants to review how a week of training actually went against the plan — a completed week or one still in progress (e.g. "how did last week go", "how's this week looking so far", "analyze my training", "compare planned vs actual pace", "was the heat a factor"). Reads the confirmed spec from specs/weekly-workouts/, downloads the matching completed activities via the garmin MCP server, pulls hourly temperature/dew point via the weather MCP server to compute a Hadley heat-stress score for each run, shows a planned-vs-actual comparison, and asks before saving it to data/weekly-workouts/ in git.
---

# Analyzing a completed week's workouts

Goal: for a week that's already been planned (a file exists in
`specs/weekly-workouts/`), whether it's finished or still in progress,
pull the runner's actual completed activities from Garmin Connect and
compare them against what was planned — pace, distance, duration, and
heat stress via the Hadley score (see
`references/hadley-score.md`) — then offer to save that comparison to
`data/weekly-workouts/`.

This skill only reads from Garmin (activities, splits) and weather
history — it never builds, schedules, or modifies a workout. That's
`creating-garmin-workout`'s job, and is a separate concern.

## Step 1 — Validate the MCP connections

- `garmin`: confirm tools (e.g. `get_full_name`, `get_activities_by_date`)
  are loaded, call `get_full_name`, and handle a stale/expired token the
  same way as `creating-garmin-workout` Step 1 (retry once, then tell the
  user to re-run `garmin-mcp-auth` themselves if the refresh token is
  dead).
- `weather`: confirm its tools (e.g. `weather_archive`) are loaded. It
  needs no auth — Open-Meteo's archive is free and keyless — so there's no
  token-refresh case to handle, just confirm the server itself is
  reachable (e.g. a minimal test call). If the `weather` MCP isn't loaded
  at all, it likely needs registering (see `references/hadley-score.md`)
  and a session restart — tell the user and continue with everything
  except the Hadley-score portion, rather than blocking the whole
  analysis on it.

Don't proceed to Step 2 until the `garmin` check succeeds; a missing
`weather` connection degrades gracefully instead of blocking.

## Step 2 — Pick which week to analyze

List `specs/weekly-workouts/*.md`. Any week whose Monday has arrived (its
spec file exists) is a valid target — complete **or still in progress**.
For a spec file that's already been analyzed (a same-named file already
exists in `data/weekly-workouts/`), treat it as re-analyzable rather than
skipping it outright: a prior in-progress run's file is expected to change
as more days complete, so only flag it to the user as "already analyzed"
when the target week is complete.

- If the user named a specific week/day/period (a date, "last week",
  "this week", "today", etc.), resolve that to the corresponding spec
  file — a single day resolves to the week containing it.
- If the user didn't specify anything, **ask** which week/day/period to
  analyze — do this even if only one spec file exists. Don't silently
  default to "the one available week."
- Once resolved, compare today's date to that week's Sunday to determine
  whether the target week is **complete** or **in-progress**. Carry this
  flag through — it doesn't gate anything in Steps 3-7, but Step 8 asks
  about it explicitly either way.

## Step 3 — Read the spec

Parse the matched `specs/weekly-workouts/MM-DD-YYYY.md` file. It already
distinguishes (per `extract-workouts` Step 3's classification):

- **Workout days** — full Warm-up/Main set/Cool-down breakdown with
  resolved paces, named `MM/DD/YYYY`.
- **Easy/recovery days** — date, distance, resolved pace, no name (no
  Garmin workout was built for these).
- **Off days** — nothing planned; skip entirely, don't look for an
  activity.

## Parallelizing across multiple days

Steps 4-6 repeat per planned running day and are independent of each other
(each day's activity match, split pull, and weather lookup don't depend on
any other day's). When a week has more than one day left to process,
prefer spinning up parallel sub-agents — one per day — to do Steps 4-6,
rather than working through every day serially in one thread.

**Cap concurrency on anything calling the `garmin` MCP** to avoid tripping
its rate limiting (see Step 1's 429 handling) — don't fan out one agent per
day unboundedly. A handful of days at once (a typical week) is fine; throttle
if there are more. The `weather` MCP call in Step 6 isn't Garmin-backed and
isn't a concern here.

A single day or an already-mostly-analyzed week (one or two days left) is
fine to just do inline — this is about avoiding serial work once there's
real day-parallel work to do, not a blanket rule to always spin up agents.

## Step 4 — Match each planned running day to a completed activity

For each planned running day, first compare its date to today's date:

- **Date is in the future** (only possible for an in-progress week): skip
  the Garmin lookup entirely — there's nothing to match yet. Record it as
  **not yet run**, distinct from a **missed** day below.
- **Date is today or in the past**: continue as follows.

Call `get_activities_fordate(date)` (or `get_activities_by_date` narrowed
to that single day) filtered to running.

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
  `distance_meters`, `duration_seconds`, `avg_speed_mps`, `avg_hr_bpm`,
  `max_hr_bpm`, `elevation_gain_meters`, `elevation_loss_meters`. Also pull
  `get_activity_splits(activity_id)` for per-mile `avg_hr_bpm`,
  `elevation_gain_meters`, `elevation_loss_meters` — needed for the
  terrain/HR-trend check in Step 7, not just the Hadley lat/lon lookup.
- **Workout days**: call `get_activity_typed_splits(activity_id)`. For a
  workout completed as built, this returns phase-tagged splits in
  chronological order — confirmed types: `INTERVAL_WARMUP`,
  `INTERVAL_ACTIVE` (one per main-set rep), `INTERVAL_RECOVERY` (one per
  recovery jog), `INTERVAL_COOLDOWN` — each with its own `distance`,
  `duration`, `averageSpeed` (m/s), `averageHR`/`maxHR`, `elevationGain`,
  `elevationLoss`.
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
  - When a single typed split covers more than one planned pace segment
    (e.g. Garmin recorded "2mi @ MP then 2mi @ MP+30-40s" as one merged
    `INTERVAL_ACTIVE` block instead of two), fall back to
    `get_activity_splits`'s per-mile/per-lap laps and use their
    `workout_step_index` field (when present) to split the block back into
    its planned sub-segments — don't just report the merged block's single
    average pace as if it were one planned segment.
  - `get_activity_splits`' per-lap `elevation_gain_meters`/
    `elevation_loss_meters` and `avg_hr_bpm` (finer-grained than the
    typed-split phase totals) are what Step 7's terrain/HR check needs —
    pull them for any workout day with more than one rep/mile in a phase,
    not just to patch a merged-split case.

## Step 6 — Pull weather and compute the Hadley score

Skip this step entirely for a day recorded as **missed**, **not yet run**,
or **unplanned off-day activity** — there's no completed run to contextualize,
or (missed) no run happened. Skip it too if Step 1 found the `weather` MCP
unavailable — degrade gracefully, the rest of the analysis doesn't depend
on it.

For every other matched activity (workout and easy/recovery days alike),
follow `references/hadley-score.md` in full:

1. Get the activity's representative lat/lon from its first split
   (`get_activity_splits` or `get_activity_typed_splits`).
2. Get its local start time and duration from `get_activity` and derive
   the local-hour range the run spans.
3. Call the `weather` MCP's archive tool for that date/location, hourly
   `temperature_2m` and dew-point (or relative-humidity-derived dew point)
   in Fahrenheit.
4. Compute the Hadley score (`temp°F + dewpoint°F`) for each spanned hour
   and map each to its pace-adjustment band from the chart.
5. If the archive has no data yet for that date (recent-activity lag),
   note the Hadley-score section as unavailable for that day and move on
   — don't block or error the rest of the analysis.

## Step 7 — Compare planned vs. actual

Convert `averageSpeed`/`avg_speed_mps` (m/s) to pace: `1609.344 /
speed_mps` = seconds per mile, format `M:SS`. For each planned segment
(whole easy day, or warm-up/each main-set rep/cool-down for a workout day):

- Planned pace (or range) vs. actual pace, and the delta.
- Planned distance/duration (end condition) vs. actual distance/duration.
- Where Step 6 produced a Hadley-score range for that day, note the
  expected heat-driven pace-adjustment band alongside the observed
  planned-vs-actual delta (per `references/hadley-score.md`'s "Computing
  and reporting" section) — framed as a plausible contributing factor, not
  a definitive explanation; fatigue, terrain, and effort are still in
  play.

**Terrain and HR — use both to judge *why* a pace missed, not just *that* it missed:**

- **Terrain**: for any segment with more than one rep/mile, compute net
  elevation change (`elevationGain - elevationLoss`) as a % of that
  rep/mile's distance, and check whether the worst-paced reps/miles are
  also the most uphill ones (and the best-paced ones the most downhill).
  A pace miss that lines up with grade is terrain, not fitness — don't let
  a hilly mile read as an unexplained slowdown.
- **HR as a fitness-ceiling check**: compare the segment's avg/max HR
  against the runner's known effort ceiling for that kind of work (e.g.
  a day this runner *did* hit a given target pace, if one exists earlier
  in the same week — see Tuesday-vs-Thursday in this file's own history
  for the pattern) and against `workout_feel`/`workout_rpe` from
  `get_activity` if present (Borg CR10 ×10, so `70` = RPE 7/10). If HR and
  RPE both show headroom — well under a comparable hit-target day, RPE
  rated no higher than a session that succeeded — a pace miss reads as
  terrain/heat/pacing-execution, not a fitness limiter: say so plainly
  rather than defaulting to "fatigue" as the explanation. If HR is pinned
  near max and RPE is high, that's the opposite signal — the runner
  likely didn't have more to give that day.
- **Within-run HR trend distinguishes fatigue from an intentional ease**:
  HR climbing while pace slows across a segment reads as fatigue forcing
  the slowdown. HR *dropping* while pace slows (e.g. the closing mile of a
  long run) more often reads as the runner consciously backing off, not
  losing the ability to hold pace — don't default to "fatigue" for every
  late-run fade without checking which pattern the HR trend actually
  shows.

Also roll up a weekly total: planned weekly mileage vs. actual completed
mileage so far (both missed and not-yet-run days count as 0 actual, but
keep them labeled separately — don't let "not yet run" read as a miss),
and how many of the planned running days were completed, missed, or not
yet run.

## Step 8 — Write the file, show it, then ask about git

1. **Always write** the analysis to `data/weekly-workouts/MM-DD-YYYY.md`,
   same Monday-dated filename as the spec file it analyzes — this is a
   plain local file write, regardless of completeness and before any git
   decision. For an in-progress week that's been analyzed before, this
   overwrites the prior local version with the latest snapshot.

   Include in the file:
   - A per-day table: planned vs. actual distance and pace, delta,
     missed/not-yet-run/unplanned flags.
   - For each workout day, the phase-by-phase breakdown from Step 7
     (mirroring the Warm-up/Main set/Cool-down shape of the spec it's
     compared against).
   - Where available, each day's Hadley-score range and expected
     pace-adjustment band from Step 6/7.
   - The weekly mileage roll-up (through today, for an in-progress week).
   - A short plain-language summary of what stands out (e.g. "MP reps ran
     8-12 sec/mi faster than target," "missed Friday's easy run," "long
     run cool-down drifted slow, likely fatigue," "Saturday's slower pace
     lines up with a Hadley score in the 131-140 band").

2. **Show the same analysis** in the chat response — don't make the user
   open the file to see what was found.

3. **Then ask**: "Would you like to save this analysis to git?" — ask this
   every time, for both complete and in-progress weeks; completeness
   doesn't change whether the question gets asked, only how the user is
   likely to answer it (an in-progress week's file will keep changing as
   more days complete, so they may reasonably say no until the week
   finishes — but that's their call each time).
   - **Yes**: check `git status`/`git diff --cached` first, stage only
     this one file by path, commit, and push to `origin main`. Don't
     sweep in unrelated pending changes in the repo.
   - **No**: leave the file as an uncommitted local change. Don't commit
     or push anything.

## Step 9 — Report back

Summarize for the user: which week was analyzed (and whether it was
complete or still in progress), where the file was saved, the weekly
mileage roll-up, and the two or three most notable planned-vs-actual
findings — including any notable Hadley-score/heat context. Flag any
missed days, not-yet-run days, activities that couldn't be confidently
matched, or days where the `weather` MCP had no archive data yet. State
plainly whether the file ended up committed+pushed or left as a local
uncommitted change, based on the answer to Step 8's question — and for an
in-progress week, mention that re-running the analysis later will
overwrite this same local file as more days complete.

---
name: extract-workouts
description: Use when the user pastes/shares email text containing one or more days of structured workouts (e.g. a weekly training plan digest) and wants them extracted into Garmin workout specs. Parses the email, resolves paces against the user's pace chart, and presents the parsed workout(s) for confirmation; does not itself build or schedule anything on Garmin.
---

# Extracting workouts from an email

If the user just pasted a full weekly training-plan email with no other
specific instruction, prefer invoking `weekly-training-pipeline` instead —
it chains this skill together with `star-strava-routes` and
`creating-garmin-workout` for the full email-to-watch flow. Use this skill
directly only for a narrower ask (just extract/parse, no building).

Goal: given the text of an email pasted into the conversation (typically a
week of training, sometimes just a few days), parse out each individual
workout into a spec matching what `creating-garmin-workout`'s "gather the
workout spec" step needs — without touching any Garmin tools. This skill
only extracts and confirms; building/scheduling is a separate concern.

## Step 1 — Check known formats

Look in `references/` for a file matching this email's source/layout (one
file per distinct format, e.g. `references/trainingpeaks.md`). If one
matches, follow its field-mapping notes for this step, including any pace
chart it points to. If none matches, fall back to generic parsing in Step 2,
and flag the email as an unrecognized format in the final report so the
user can decide whether to add a reference for it (see
`references/README.md`).

## Step 2 — Extract each workout entry

Scan the email for individual workout entries — there could be a full week
or just a handful of days, don't assume a fixed count. For each entry, pull
out:

- **Date** — the calendar date this workout falls on.
- **Type** — easy run, interval/tempo run, walk/run intervals, strength, or
  custom.
- **Structure** — warmup/cooldown length, work/rest intervals and repeats,
  target pace or HR zone (Z1–Z5) or power zone, distance vs. duration based.

Match these to `creating-garmin-workout`'s builder-tool categories
(`create_run_workout`, `create_walk_run_workout`, `create_z2_walk_workout`,
`create_strength_workout`) where possible, so the output vocabulary lines up
for whatever consumes it later.

Don't invent structure that isn't in the email — if a field is ambiguous or
missing, flag it rather than guessing.

## Step 3 — Classify each day

Every entry falls into one of three buckets:

- **Off** — the runner doesn't run this day at all. No spec needed, no
  Garmin workout.
- **Easy/recovery** — a single pace for the entire run, no intervals or
  pace changes (regardless of distance). These do **not** need a Garmin
  workout built — note the date, distance, and pace informationally only.
- **Workout** — has real structure: intervals, pace changes, a defined
  warm-up/main-set/cool-down shape (quality runs, medium-long runs with
  pickups, long runs with embedded goal-pace segments, etc.). These need a
  full Garmin-workout spec — continue to Step 4 and Step 5 for these.

## Step 4 — Resolve paces

If the matching `references/` file (from Step 1) points to a pace chart,
read it and resolve every pace label used in a **workout**-classified entry
(marathon pace, half-marathon pace, 10k/5k pace, threshold pace, easy pace,
etc.) into an actual pace range, using the runner's current goal race time
to pick the right row/column. Put the resolved range directly in the spec —
don't hand off a bare label like "MP" with no pace attached.

If no pace chart is on file, or a label doesn't map cleanly to any column,
flag it rather than guessing at numbers.

Resolving paces needs inputs like the runner's training group and current
goal race time — the matching `references/` file may split these into a
**persisted runner profile** (check its file first, only ask if missing or
changed) versus questions to **ask fresh every week** (things like exact
mileage that genuinely vary). Follow whatever split that reference
specifies rather than re-asking everything from scratch each time.

## Step 5 — Break workout entries into Warm-up / Main set / Cool-down

For every entry classified as a **workout** in Step 3, structure the spec
explicitly as:

- **Warm-up** — with its resolved pace.
- **Main set** — the intervals/reps/pace-segments, each with its resolved
  pace.
- **Cool-down** — with its resolved pace.

Don't leave these implicit in a single paragraph — call each one out by
name so whatever builds the Garmin workout later can map it directly to
workout steps.

## Step 6 — Name each workout

For every **workout**-classified entry, name it `MM/DD/YYYY` using its own
calendar date, zero-padded — this is the name that will show up on the
watch. This overrides any name given in the source email. Easy/recovery and
off days don't get a Garmin workout name since no workout is built for them.

## Step 7 — Present parsed specs for confirmation

List every parsed entry:

- **Workout** days — date, name, classification, and the full Warm-up/Main
  set/Cool-down breakdown with resolved paces.
- **Easy/recovery** days — date, distance, and resolved pace, noted as "no
  Garmin workout needed."
- **Off** days — just the date, noted as skipped.

Also list anything flagged in Steps 1/2/4 as unrecognized-format, ambiguous,
or an unresolved pace. Ask the user to confirm or correct before considering
the extraction done.

## Step 8 — Save the confirmed spec

Once the user confirms (or corrects and re-confirms) the parsed week, write
the final spec to a markdown file in the runner's own repo, at
`specs/weekly-workouts/MM-DD-YYYY.md`, named for the **Monday** (first
training day) of that week — e.g. a week starting Monday 07/27/2026 is
`specs/weekly-workouts/07-27-2026.md`. Include everything from the Step 7
presentation: resolved paces, easy-day distances/paces, and each workout
day's full Warm-up/Main set/Cool-down breakdown.

Commit and push that one file to `origin main` in that repo. Check
`git status`/`git diff --cached` first and commit only this specific file
by path — don't sweep in any other pending changes that happen to be
staged or modified in that repo.

If the matching `references/` file defines a persisted runner-profile file
(see Step 4) and any of its fields were newly created or changed during
this run, write/update that file too (same repo) and include it in the
same commit alongside the weekly spec file.

This skill does not call any Garmin MCP tools and does not invoke
`creating-garmin-workout` itself — chaining confirmed **workout**-classified
specs into building and scheduling is left to a separate orchestrating
skill. Saving the confirmed spec to the runner's own repo is still within
this skill's job, since it's just persisting the extraction's own output.

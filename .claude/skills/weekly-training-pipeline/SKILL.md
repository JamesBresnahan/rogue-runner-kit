---
name: weekly-training-pipeline
description: Use when the user pastes/shares a full weekly training-plan email (e.g. the Rogue Running coach email) with no other specific instruction. Orchestrates the whole flow end to end — stars any Strava routes in the email, extracts/resolves/confirms the week's workout specs (via extract-workouts), then builds and schedules the resulting workouts on Garmin Connect (via creating-garmin-workout). For a narrower ask (just star routes, just extract a spec, just build one workout), use star-strava-routes, extract-workouts, or creating-garmin-workout directly instead.
---

# Weekly training-email pipeline

Goal: turn a pasted weekly training email into workouts live on the user's
Garmin watch, chaining three existing skills so the user doesn't have to
invoke each one by hand. This skill does no parsing or building itself —
it only sequences the other three and consolidates their reports.

## Step 1 — Star any Strava routes (no gate)

Scan the email for `strava.com/routes/<id>` links and invoke
`star-strava-routes` with the email text. Do this first and immediately —
starring is safe and idempotent (it already checks "already starred" before
acting), so it doesn't need to wait on anything else in this pipeline.

## Step 2 — Extract, resolve, and confirm the week (the pipeline's one gate)

Invoke `extract-workouts` with the full email text. Let it run its full
flow as documented in its own `SKILL.md` — format detection, pace
resolution (including its persisted-runner-profile-vs-ask-fresh split, see
its matching `references/` file), classification, and presenting the
parsed week for the user's confirmation before saving.

Do not add a second confirmation step here — `extract-workouts`' own
Step 7 (present for confirmation) *is* this pipeline's single pause point.
Nothing in Step 3 below runs until that confirmation has happened and
`extract-workouts` reports the spec (and, if applicable, the runner
profile) saved and pushed.

## Step 3 — Build and schedule each workout day

For every entry the confirmed spec classified as **workout** (not
easy/recovery, not off), invoke `creating-garmin-workout` once per entry,
passing that day's date, name, and full Warm-up/Main-set/Cool-down
breakdown exactly as confirmed in Step 2. Let each invocation run its own
full flow, including its MCP-connection check (Step 1) and its
existing-workout duplicate check (Step 3) — don't hoist either of those up
into this pipeline, they're already handled per-invocation.

If a given day's build/schedule fails or is skipped (connection lost,
duplicate found and user chose skip, etc.), keep going with the remaining
days rather than aborting the whole pipeline, and carry the failure/skip
into the final report.

## Step 4 — Consolidated report

Summarize the whole run in one place, pulling from what each sub-skill
already reported:

- Strava routes: which were newly starred vs. already starred, and any
  non-route links skipped.
- Extraction: easy/recovery days (date, distance, pace, no workout built)
  and off days, the saved spec file path, and the runner-profile file path
  if it was created or updated this run.
- Garmin: for each workout day — name, `workout_id`, scheduled date, and
  whether a duplicate-check collision was hit (and what was done about it:
  skipped / replaced / created anyway).
- If anything failed partway through (e.g. Garmin connection dropped after
  routes+spec succeeded), say exactly what completed and what didn't —
  never imply full success when part of the pipeline didn't run.
- Close with the same reminder `creating-garmin-workout` gives: workouts
  show up on the watch after its next sync with Garmin Connect — there's
  no separate push step.

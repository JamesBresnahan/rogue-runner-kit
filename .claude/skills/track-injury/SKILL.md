---
name: track-injury
description: Use when the user reports or mentions pain, soreness, an ache, a tweak, or any injury connected to their running (e.g. "my knee's been hurting", "I tweaked something Thursday", "IT band is acting up again", "my knee's still sore", "the knee thing is gone now") — whether raised on its own or mid-flow inside an `analyze-weekly-workouts` session (which should invoke this skill directly rather than just noting the mention). Logs each report as a dated check-in against the workout(s) around it (with special attention to the previous 1-2 days, since running pain often doesn't show up until 24-48 hours later), tracks how the same issue progresses across follow-up reports over time, and — only once there's enough tracking data across multiple workouts, not from a single report — starts checking for repeat patterns (same body part, same workout type, same onset lag). Asks before saving to data/injury-log/injury-log.md in git. Tracking and pattern-spotting only — never diagnoses or prescribes treatment.
---

# Tracking a reported running injury

Goal: log every report the user makes about pain, soreness, or an injury
connected to their running as a dated check-in, let the same issue be
tracked across multiple check-ins as it progresses (better/worse/gone),
and only start looking for what might be causing it once there's enough
history across multiple workouts to say anything meaningful — a single
report is a data point, not something to correlate yet.

This skill only tracks and correlates. It never diagnoses a condition,
never prescribes treatment or rehab, and never modifies the training plan
on its own — see "Scope boundary" at the end.

## Input contract

Client-agnostic, same pattern as `creating-garmin-workout`: this skill
doesn't care whether the report came from the user typing it directly, or
from mid-flow in another skill — most commonly `analyze-weekly-workouts`,
which should invoke this skill directly when an injury comes up rather
than just noting the mention in its own report.

If invoked from `analyze-weekly-workouts` (or anywhere activity data for
the relevant days was already fetched this session), reuse that data —
activity IDs, paces, terrain/HR context already pulled — rather than
re-fetching it in Step 3. Only pull fresh data for whatever wasn't already
gathered.

## Step 1 — Find or open an episode

Read `data/injury-log/injury-log.md` if it exists (see Step 4 for its
format). Each tracked issue lives under its own **episode** — one
body-part-and-timeframe thread that can span many check-ins.

- If there's an **open** episode for the same (or clearly related) body
  part, treat this report as a **follow-up check-in** on that episode —
  don't open a new one.
- Otherwise, this is a **new episode**.
- If the user's report sounds like resolution ("it's gone now," "hasn't
  bothered me in a week"), that's still a follow-up check-in — mark the
  episode **resolved** in Step 4 rather than closing it silently.

## Step 2 — Capture this check-in

**New episode** — ask for (or extract from what the user already said)
whatever's missing:

- **Body part / location** — as specific as the user can give.
- **Onset** — when the pain actually started, not just when they're
  mentioning it now. Always ask directly if not already given ("when did
  you first notice this?") — report date and onset date are often
  different, and onset date is what Step 3 needs.
- **Severity** and **description**, in the user's own words/scale — don't
  force either into a scale they didn't use.

**Follow-up check-in** — ask (or extract) how it's changed since the last
check-in: better / worse / same / gone, current severity, and whether
anything new happened workout-wise since then.

**Safety check, either case**: if what's described sounds like it needs
prompt medical attention — can't bear weight, sudden sharp/severe pain,
significant swelling, numbness — say so plainly and suggest seeing a
professional now, rather than proceeding through the rest of this
tracking flow as if it were routine.

## Step 3 — Identify the workout(s) around this check-in

If this session hasn't already validated the `garmin` MCP connection
(e.g. this skill was invoked standalone, not from inside
`analyze-weekly-workouts`), do that check first — same as
`analyze-weekly-workouts` Step 1.

For a **new episode**, use the **onset date** from Step 2. For a
**follow-up**, use whatever date the user is reporting *from* now (today,
or whenever they say the change happened) — a follow-up can still surface
a fresh aggravating workout, not just the original onset.

1. **That day's own workout**, if the runner ran that day — pull its type
   (workout/easy/off) from `specs/weekly-workouts/`, and its execution
   detail (pace, terrain, HR) from the matching `data/weekly-workouts/`
   analysis file if one exists, or pull fresh via the `garmin` MCP
   (`get_activities_fordate`, `get_activity`,
   `get_activity_typed_splits`/`get_activity_splits`) the same way
   `analyze-weekly-workouts` Steps 4-5 do, if not.
2. **The 1-2 day(s) immediately before it** — pull the same, even if that
   day itself looks unremarkable. Running pain frequently doesn't show up
   until a day or two after the workout that actually caused it, so a
   hard interval or long run two days prior is often the more relevant
   match.
3. Note the **workout type** for each day pulled (interval, tempo,
   medium-long w/ pickups, long run, easy/recovery, off) — this is the
   main axis Step 5's pattern check eventually runs against.

If Garmin has no activity for a candidate day, that's fine — record it as
a rest/off day, don't treat it as missing data.

## Step 4 — Log the check-in

Create `data/injury-log/injury-log.md` if it doesn't exist yet, with this
header:

```
# Injury Log

Running injury/pain reports, tracked as dated check-ins under one episode
per body-part-and-timeframe thread. Correlation only starts once there's
enough history across multiple workouts — see the `track-injury` skill's
Step 5 gate. Tracking and pattern-spotting only — not medical advice. See
that skill's "Scope boundary" for what this file is and isn't used for.
```

**New episode** — append a new episode section:

```
## Episode: <body part> — opened YYYY-MM-DD (status: open)

- **Onset**: YYYY-MM-DD (however precisely the user gave it)
- **Onset-day workout**: <date, type, brief pace/terrain/HR note, or "off/no run">
- **Day(s) before onset**: <date(s), type(s), brief note(s)>

### Check-ins
- YYYY-MM-DD: <severity, description, trend if known>
```

**Follow-up** — append a new line under that episode's `### Check-ins`
list, and if this check-in surfaced a fresh nearby workout (Step 3), note
it inline:

```
- YYYY-MM-DD: <better/worse/same/gone, severity, description; workout context if a new one is relevant>
```

If the check-in marks resolution, change the episode header's status to
`resolved` rather than deleting anything — resolved episodes still count
toward Step 5's pattern check.

Keep everything terse — this file gets re-read in full each time Step 5
runs, so favor short factual lines over prose paragraphs.

## Step 5 — Check for patterns (only once there's enough data)

**Gate first.** Count the distinct **check-ins** (dated reports the user
actually made) across the *entire* log, all episodes combined — not the
workout-context days mentioned inside them. A single report that happens
to reference several nearby days (onset day, day before, a worse day
later that same week) is still one check-in, not several — don't let
richly-detailed context from one report satisfy the gate on its own. If
there are **fewer than 3 distinct check-ins**, stop here — don't attempt
correlation. Say plainly in Step 6 that this is logged but there isn't
enough tracking history yet to say anything about causes, and roughly how
much more it'd take (a couple more check-ins, ideally tied to different
workouts).

Once the gate is cleared, check the new entry against the full log:

- **Same body part reported more than once** — how many times, and what's
  common across those episodes' onset-day/day-before workout types?
- **Same workout type preceding onset or a flare-up** — e.g. three
  separate instances (across one or more episodes) each followed an
  interval or tempo session within 1-2 days, regardless of body part.
- **Consistent onset/flare lag** — e.g. pain repeatedly shows up two days
  after a long run rather than the next day.

Only call something a pattern if it's actually there across **multiple**
independent instances — don't reach for a correlation the data doesn't
support yet, even past the gate.

## Step 6 — Report back, then ask about git

1. Show the logged check-in, and either the pattern-check findings from
   Step 5 or the "not enough data yet" note if the gate wasn't cleared.
2. Restate plainly: this is tracking and correlation only, not a
   diagnosis and not medical advice. If pain is persistent, worsening, or
   the Step 2 safety check was tripped, say a sports medicine professional
   or PT is the right next step, not this log.
3. **Ask**: "Want me to save this to git?" — same pattern as
   `analyze-weekly-workouts` Step 8: **yes** → check `git status`/
   `git diff --cached`, stage only `data/injury-log/injury-log.md`, commit,
   push to `origin main`; **no** → leave it as an uncommitted local change.

## Scope boundary

This skill tracks reports and, once there's enough history, surfaces
correlations in the data — it does not diagnose conditions, does not
prescribe treatment or rehab, and does not modify any scheduled or planned
workout on its own. Even once Step 5's gate is cleared, treat any
correlation as a plausible pattern worth mentioning, not a conclusion —
this is still a small, self-reported dataset. If a pattern suggests the
user might want to adjust upcoming training around it, say what the data
shows and let the user decide — don't silently skip, alter, or flag a
future workout as a result of this skill running.

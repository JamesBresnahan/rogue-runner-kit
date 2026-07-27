# Rogue Running weekly coach email

**Source:** Weekly training-plan email from Rogue Running (Austin) coach
Cathy. Sent Sundays, opens with "Happy Sunday!" or similar, signed "Cheers!
Cathy." Covers the upcoming Monday–Sunday.

## Layout

The email has two parts:

1. **Club announcements** (gear orders, volunteer asks, race sign-up
   reminders, upcoming events, coupon codes, "Thought of the Week", etc.) —
   not workout content, ignore entirely for extraction.
2. **"Here is what we have for training this week:"** — the actual
   day-by-day plan. Everything relevant is under this heading.

## Date mapping

The email is sent on a Sunday; "Monday" in the plan is the calendar day
immediately after the send date, through the following "Sunday" six days
later.

## Per-day structure

- **Monday / Wednesday / Friday** — generic recovery: "Recovery pace run @ a
  low HR and then stretch/foam roll." No distance/duration is ever given in
  the email itself — always ask the runner (see Standing Questions).
- **Tuesday — "Quality Run X–Y miles"** — a warmup (drills + strides on a
  named warmup route) followed by a main set that **differs by training
  group** (Marathon / Half / 5k-10k / Return-to-training), each with its own
  rep scheme, pace, and recovery, on a named workout route. The email only
  gives a mileage *range* for the day, not an exact number.
- **Thursday — "Medium Long Run"** — same structure for every group (an easy
  run with a fixed set of pickups, e.g. "9 × 90" @ HM / 90" easy" mid-run,
  on a named route). Also only given as a mileage *range*.
- **Saturday — "Long Run"** — broken out **per specific goal race** (e.g.
  Grand Traverse, Berlin, Twin Cities, Chicago, Columbus, Marine Corps,
  Indy, Portland Half, Valencia, 5k/10k, "All others"), each with its own
  distance and workout. Usually has a start-time note (e.g. "starts at
  5:30am"). Includes a standing fallback line for runners not yet at full
  build-up mileage — do 2mi more than their most recent long run, easy pace
  — but doesn't specify how to scale a *workout* version down, only the
  fallback of dropping the workout and going easy.
- **Sunday** — "Recovery (rest, very easy recovery run, or cross train).
  Listen to your body." Optional/ambiguous by design — confirm whether the
  runner treats this as rest or as a run.

## Which days need a Garmin workout

Per `SKILL.md` Step 3's classification:

- **Monday / Wednesday / Friday / Sunday** (whichever the runner actually
  runs) — single-pace recovery/easy days. **No Garmin workout needed** —
  just note distance + resolved pace.
- **Tuesday / Thursday / Saturday** — quality run, medium-long run w/
  pickups, long run w/ goal-pace segments. **Always need a full Garmin
  workout spec**, broken into Warm-up / Main set / Cool-down per
  `SKILL.md` Step 5.
- Any day the runner doesn't run at all is **off** — nothing needed.

## Pace chart

Path: `specs/resources/ROGUE TRAINING PACES.xlsx`, relative to the repo
root (the runner's own clone of their `rogue-runner-kit` fork).

It's a single sheet, one row per discrete "Marathon Goal Time" in ~5-minute
steps (2:44, 2:49, 2:54, 2:59, …), each row carrying every other pace as a
McMillan-style equivalent for that fitness level — there's no separate
"half marathon goal time" input; the paired `hMGT`/`hMGP` columns on the
same row already give the equivalent half-marathon time/pace.

**Row selection:** the runner's goal time rarely lands on an exact row.
Take the two rows straddling it and **linearly interpolate** every pace
column by the fractional position between them (e.g. a goal 1 minute past
a row that's 5 minutes before the next one interpolates 20% of the way).
Convert each `M:SS` pace to seconds, interpolate, convert back, round to
the nearest second.

**Column → workout-label mapping:**

| Email says | Chart column | Notes |
|---|---|---|
| MP (marathon pace) | `MGP` (Marathon Goal Pace) | |
| HM (half-marathon pace/effort) | `hMGP` | same row as MP, not a separate goal |
| 10k pace | `10K` | |
| 5k pace | `5K` | |
| Mile pace | `Mile` | |
| LT / lactate threshold | `Lactate Threshold` | |
| AT / aerobic threshold | `Aerobic Threshold` | |
| Groove intervals | `Groove Intervals (LT-1)` | faster interval work, if ever prescribed |
| VO2max work | `VO2 MAX (LT-2)` | |
| Speed work | `Speed (LT-3)` | |
| "easy long run pace" (long-run days only) | `Long Runs: Range ` | the general range column, distinct from EZ/Recovery below |
| Brisk / Steady / Moderate long run effort | `BRISK LR: AT+1` / `STEADY LR: AT+2` / `MODERATE LR: AT+3` | only if the email names one of these instead of plain "easy" |
| **Warm-up** pace (any workout day), Monday's easy day | `EZ Runs` (header note: "warm up & Monday & occasional TR days") | also used for short jog/recovery segments *between* reps within a workout |
| **Cool-down** pace (any workout day), Wed/Fri/Sun easy days | `Recovery Runs` (header note: "cool down, Wed/Fri/Sun runs") | |
| MP+N" (e.g. "MP+30-40\"") | `MGP` + N seconds/mile | additive offset, always slower |

Strides given as % effort (e.g. "4×100 @ 60/70/80/90%") aren't on the chart
at all — leave them as effort percentages, don't force a pace onto them.

## Standing questions

Split between a **persisted runner profile** (stable across weeks — check
the file, only ask about a field if it's missing or something signals it
changed) and questions to **ask fresh every week** (things the email only
gives as a range, or that change week to week regardless).

### Persisted runner profile

Path: `specs/resources/runner-profile.md` (sibling to the pace-chart
xlsx). Markdown, one field per line. Read it first; only ask
about a field below if the file doesn't exist, the field is missing from
it, or the email/user says something changed (new race, updated goal time,
new schedule). After confirming, write/update the file per
`extract-workouts` `SKILL.md` Step 8.

1. **Training group** — Marathon / Half / 5k-10k / Return-to-training?
   (resolves Tuesday's exact rep scheme/paces)
2. **Target race** — which named race from Saturday's list? (resolves
   Saturday's exact structure)
3. **Current goal race time** — drives every resolved pace via the chart
   above.
4. **Which days the runner actually runs** — the email assumes
   Mon/Tue/Wed/Thu/Fri/Sat/Sun, but a runner may skip a day (e.g. no
   Wednesday) and run on Sunday instead. Confirm the actual run days.
5. **Saturday scaling, if not at full prescribed mileage** — whether to
   (a) keep all quality-work reps and trim the easy warmup/cooldown miles,
   or (b) keep the full easy warmup/cooldown volume and drop to fewer
   quality reps.

Suggested file shape:

```markdown
# Runner Profile

- Training group: Marathon
- Target race: Columbus Marathon
- Goal race time: 2:50:00
- Run days: Mon, Tue, Thu, Fri, Sat, Sun (skips Wed)
- Saturday-scaling preference: (a) trim easy volume, keep quality reps

Last updated: 2026-07-26
```

### Ask fresh every week

These genuinely vary week to week even with a stable profile — always ask,
never carry over from a prior week:

1. **Weekly goal mileage** — total miles for the week.
2. **Exact Tuesday mileage** — the email only gives a range.
3. **Exact Thursday mileage** — the email only gives a range.
4. **Exact Saturday mileage** — the email only gives a range, and long-run
   distance progresses week to week through a training block.
5. **Distributing remaining weekly mileage across the easy days** — after
   Tuesday, Thursday, and Saturday are fixed, split what's left evenly
   across the remaining easy days (Mon/Fri/Sun, or whichever apply) to hit
   the weekly goal. If the split isn't a clean number, present the rounding
   options (e.g. round every day down, round every day up, or one uneven
   day) and let the runner pick — including which specific day absorbs any
   remainder.

## Worked example (week of 2026-07-27)

Marathon group, targeting Columbus Marathon, goal marathon time **2:50:00**,
weekly goal 52mi, Tuesday 11mi, Thursday 11mi, runs Sunday instead of
Wednesday.

Goal time falls between the chart's 2:49 row and 2:54 row → interpolated
20% of the way toward the 2:54 row:

| Pace | Value |
|---|---|
| MP (MGP) | 6:29/mi |
| HM (hMGP) | 6:10/mi |
| EZ Runs (warm-up / Monday / in-workout recovery jogs) | 6:30–7:29/mi |
| Recovery Runs (cool-down / Wed-Fri-Sun easy days) | 7:43–8:27/mi |
| Long Runs: Range (easy long-run pace) | 6:36–7:45/mi |
| MP+30-40" | 6:59–7:09/mi |

Easy/recovery days (no Garmin workout needed):

| Day | Miles | Pace |
|---|---|---|
| Mon 07/27 | 5 | EZ Runs 6:30–7:29/mi |
| ~~Wed 07/29~~ | — | Skipped — no run |
| Fri 07/31 | 5 | Recovery Runs 7:43–8:27/mi |
| Sun 08/02 | 4 | Recovery Runs 7:43–8:27/mi |

Workout days (full Garmin-workout spec, Warm-up/Main set/Cool-down):

**07/28/2026 — Interval (11mi total)**
- Warm-up: easy jog @ EZ Runs 6:30–7:29/mi, + drills + 4×100m strides at
  60/70/80/90% effort (effort-based, no chart pace), jog-back recovery.
- Main set: 10×1k, odd reps @ MP 6:29/mi, even reps @ HM 6:10/mi, 1' jog
  recovery @ EZ Runs 6:30–7:29/mi between each rep.
- Cool-down: easy @ Recovery Runs 7:43–8:27/mi, filling remaining mileage
  to 11mi total.

**07/30/2026 — Medium-long run w/ pickups (11mi total)**
- Warm-up: easy @ EZ Runs 6:30–7:29/mi.
- Main set: 9×90" @ HM 6:10/mi / 90" easy @ EZ Runs 6:30–7:29/mi, mid-run.
- Cool-down: easy @ Recovery Runs 7:43–8:27/mi, filling remaining mileage
  to 11mi total.

**08/01/2026 — Long run, Columbus scaled (Option B, 16mi total, 5:30am
start)**
- Warm-up: 8mi @ Long Runs: Range 6:36–7:45/mi.
- Main set: 2mi @ MP 6:29/mi, then 2mi @ MP+30-40" 6:59–7:09/mi.
- Cool-down: 4mi @ Long Runs: Range 6:36–7:45/mi.

Total weekly mileage: 5+11+11+5+16+4 = 52mi. (51 → 11−11−16=13, 13÷3 wasn't
clean; runner bumped goal to 52 → 14÷3 still not clean → accepted uneven
5/5/4 with Sunday taking the short day, rather than bumping to 53 for a
clean 5/5/5.)

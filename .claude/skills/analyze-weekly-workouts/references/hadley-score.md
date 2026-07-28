# Hadley score (heat stress) reference

## Formula

```
Hadley score = Air Temperature (°F) + Dew Point (°F)
```

Both inputs must be in Fahrenheit — the band table below only makes sense
in that unit (a Celsius sum would almost never clear the lower bands).

## Pace-adjustment chart

| Hadley score | Pace adjustment |
|---|---|
| 100 or less | No pace adjustment |
| 101–110 | 0% to 0.5% slower |
| 111–120 | 0.5% to 1.0% slower |
| 121–130 | 1.0% to 2.0% slower |
| 131–140 | 2.0% to 3.0% slower |
| 141–150 | 3.0% to 4.5% slower |
| 151–160 | 4.5% to 6.0% slower |
| 161–170 | 6.0% to 8.0% slower |
| 171–180 | 8.0% to 10.0% slower |
| Above 180 | Hard running not recommended |

Given as a range per band — when reporting, pick a point estimate (e.g.
midpoint) only if a single number is needed for a delta comparison;
otherwise just cite the band.

## Pulling the hourly data (`weather` MCP, `weather_archive` tool)

Source: [cmer81/open-meteo-mcp](https://github.com/cmer81/open-meteo-mcp)
(npm `open-meteo-mcp-server`), backed by Open-Meteo's free, keyless
historical archive (ERA5 reanalysis, 1940–present, hourly resolution).
Registered as the `weather` MCP server in `docker/entrypoint.sh`, same
idempotent-registration pattern as `garmin`. Unlike `garmin`, there's no
separate auth step — the archive API needs no key.

**Verify the exact tool/parameter names via the loaded tool schema** the
first time this is used in a session (`ToolSearch` for `weather_archive`
or similar) — the notes below reflect the package's public docs as of
2026-07-28, not a live call against this repo's registration.

- **Location**: use the activity's own GPS coordinates, not a
  geocoded city name — pull `startLatitude`/`startLongitude` from the
  first entry returned by `get_activity_splits` or
  `get_activity_typed_splits` (`get_activity` itself doesn't include
  lat/lon). Running routes are local enough that one representative
  point is fine — ERA5 grid resolution is ~9km, well below meaningful
  route variation for this purpose.
- **Date/hour range**: derive from the activity's `start_time_local` and
  `duration_seconds` (from `get_activity`) — request the full local-hour
  range the run's elapsed time actually spans (e.g. a run from 6:58am to
  8:04am covers the 6:00, 7:00, and 8:00 local hours).
- **Variables**: request hourly `temperature_2m` and `dew_point_2m` (or
  the closest equivalent the tool exposes — some Open-Meteo wrappers
  expose `relative_humidity_2m` instead of a direct dew-point variable;
  if only relative humidity is available, dew point can be derived from
  temperature + relative humidity via the Magnus formula rather than
  going without).
- **Units**: request Fahrenheit output directly if the tool supports a
  `temperature_unit` parameter — simpler than converting from Celsius
  after the fact.
- **Recent-activity gap**: Open-Meteo's ERA5 archive can lag several days
  behind real time. If a query for a very recent activity's date comes
  back empty, say so in the report rather than treating it as an error —
  the Hadley-score section for that day is just unavailable yet, the rest
  of the planned-vs-actual comparison still stands on its own.

## Computing and reporting

For each hour the run spans, compute that hour's Hadley score and map it
to a band. Report:

- The band(s)/range spanned across the run (e.g. "121–130 at the start,
  climbing to 131–140 by the finish").
- The corresponding expected pace-adjustment band(s).
- How that compares to the observed planned-vs-actual pace delta from the
  main comparison (Step 7 of `SKILL.md`) — e.g. "actual pace was ~2.3%
  slower than planned; expected heat-driven adjustment for this run's
  conditions was 1.0%–2.0%, so heat plausibly explains most but not all of
  the gap" — without asserting a stronger causal claim than the data
  supports (other factors — fatigue, terrain, effort — are still in play).

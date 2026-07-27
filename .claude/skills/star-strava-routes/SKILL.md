---
name: star-strava-routes
description: Use when the user pastes/shares email text (e.g. a Strava weekly digest) and asks to star the Strava routes mentioned in it. Opens Chrome, logs into strava.com via Google if needed, and stars each linked route.
---

# Starring Strava routes from an email

If the user just pasted a full weekly training-plan email with no other
specific instruction, prefer invoking `weekly-training-pipeline` instead —
it chains this skill together with `extract-workouts` and
`creating-garmin-workout` for the full email-to-watch flow. Use this skill
directly only for a narrower ask (just star the routes, nothing else).

Goal: given the text of an email pasted into the conversation, find any
Strava route links in it and star them on strava.com by driving the real
site through the Chrome extension — not the Strava API.

Note: this is a deliberate exception to the general credential-handling
guidance in this repo's `CLAUDE.md` and the `integration-setup` skill, both
of which steer toward token/API-based access and away from Claude driving
browser logins on the user's behalf. That guidance still applies to other
integrations; this flow is explicitly interactive/browser-driven because
starring a route has to happen through the site's UI.

Because it needs the local logged-in browser session, this skill can only
run interactively in a session with browser access — it cannot be run as a
durable cloud-scheduled routine (no browser there), and session-local
`CronCreate` scheduling isn't reliable for it either (only fires between
turns, lost when the session ends). Flag this if the user ever asks to
automate it on a recurring schedule.

## Step 1 — Extract Strava links from the email text

Scan the pasted email text for `strava.com` URLs. Classify each:

- **Route link** — path contains `/routes/<id>` — this gets starred.
- **Anything else** (activities, segments, clubs, athlete profiles, etc.) —
  leave alone, but note it was skipped in the final report.

## Step 2 — Load Chrome tools

Load every Chrome tool you'll need in one batched `ToolSearch` call:

```
ToolSearch with query "select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__tabs_create_mcp,mcp__claude-in-chrome__find"
```

Then call `tabs_context_mcp` first to see what tabs already exist, per
standing instructions. Don't reuse tab IDs from a prior/other session —
create a new tab unless the user explicitly asks to reuse one.

## Step 3 — Ensure logged into Strava

Navigate to `strava.com`. If not logged in, choose "Log in with Google" (or
"Sign up with Google" if that's the button shown).

Select the Google account named in the `$GOOGLE_ACCOUNT_EMAIL` environment
variable (populated from `/run/secrets/static/google_account_email` — set
during `first-run-setup`). If that variable is unset or empty, ask the user
which Google account they use for Strava rather than guessing, and suggest
they add it via `first-run-setup` so future runs don't need to ask.

Avoid triggering native browser `alert`/`confirm`/`prompt` dialogs during
login — they block all further automation. If one appears anyway, stop and
tell the user rather than continuing blind.

## Step 4 — Visit each route link and star it

For each link classified as a route in Step 1:

1. Navigate to the route's URL.
2. Check whether it's already starred (skip the click if so — this should
   be idempotent, not toggle an already-starred route to unstarred).
3. Otherwise, click "Star".

If a page doesn't load, an element can't be found, or a click doesn't
register after 2-3 attempts, stop and ask the user rather than retrying
indefinitely or guessing at alternate selectors.

## Step 5 — Report results

Summarize for the user:

- Routes newly starred.
- Routes that were already starred (no action taken).
- Any Strava links found in the email that were skipped because they
  weren't routes.

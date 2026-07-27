---
name: integration-setup
description: Use whenever the user asks to connect, integrate, or set up programmatic/API access to a third-party service (e.g. "connect me to X", "get API access to Y", "set up a token for Z", "I need you to be able to use my <service> account"). Walks through the token-based setup pattern without ever handling the user's raw password.
---

# Setting up API access to a third-party service

Goal: get durable, token-based programmatic access to a service, without ever
handling the user's raw password or submitting login/consent forms on their
behalf.

## Step 1 — Determine what kind of API the service offers

- **Official OAuth2 / token API** (most mainstream services: Strava, GitHub,
  Google, etc.) — go to Step 2a.
- **No self-serve personal API**, only an official partner/developer program
  aimed at businesses (e.g. Garmin Connect) — go to Step 2b.
- **No official API at all**, only unofficial/reverse-engineered libraries
  that replay a normal login — go to Step 2b, and flag the ToS risk
  explicitly.

## Step 2a — Official OAuth2 flow

1. The user creates the API application themselves in their account settings
   on the service's site (this requires their login — don't do it for them).
   Give them the exact URL and the fields they'll need to fill in.
2. The user completes the browser authorize/consent step themselves and gives
   you the resulting authorization code (or, if it's a simple personal access
   token flow, the token itself).
3. You handle the token exchange (authorization code → access + refresh
   token), and write the wrapper scripts/config that use it.

## Step 2b — Unofficial / partner-program access

- If a business-oriented developer program exists and is a realistic fit,
  say so and let the user decide if they want to pursue it (usually slow,
  may not approve individuals).
- Otherwise, identify the common unofficial library for the service. The
  user runs the *initial login* locally, themselves, in their own terminal —
  this mints a cached token/session file. You never see or type the
  password; you only consume the resulting token file afterward.
- Explicitly flag that unofficial access usually violates the service's ToS
  in some technical sense, even though it's widely used by hobbyists — let
  the user make an informed call.

## Step 3 — Storage

Follow the credential-handling convention in the global `CLAUDE.md`: write
the token to `/run/secrets/tokens/` (or `/run/secrets/static/` for
long-lived values like client IDs/secrets needed to mint or refresh a
token), named `<service>_<credential-type>`. Never store secrets in-repo, in
a project's `.env`, or in shell rc files. If the token expires, also write a
`<service>_<credential-type>_expires_at` companion file, and run
`load-secrets.sh` so it's live for the rest of the session.

## Step 4 — Build the actual integration

Once the token is available and stored, write the scripts/functions for the
specific actions requested (e.g. "star a route," "create a workout," "pull
activity history"), using the stored token — this part is a normal coding
task.

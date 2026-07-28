---
name: first-run-setup
description: Use when the user is setting up this repo for the first time, asks to verify their setup, or when weekly-training-pipeline/extract-workouts/creating-garmin-workout/star-strava-routes fails because a credential, MCP connection, or resource file is missing. Walks through connecting GitHub, Strava, and Garmin, and checking for required local files, one step at a time, without ever handling a raw password.
---

# First-run setup for the running pipeline

Goal: get a brand-new fork of this repo from "just cloned" to "ready to
paste a weekly coach email," by checking each prerequisite in order and
walking the user through fixing whatever's missing — conversationally, in
plain language, one step at a time. Safe to re-run any time (e.g. "check my
setup") since every step first checks whether it's already done before
asking the user to do anything.

Don't skip ahead to later steps if an earlier one isn't resolved — several
later steps (in particular Step 4, the GitHub PAT) need to be sorted before
anything can be persisted.

## Step 1 — Confirm the environment is wired up

Check that `/run/secrets/static` and `/run/secrets/tokens` both exist and
are writable (`test -w`). If either is missing, this container wasn't
launched correctly — tell the user to re-run `setup.sh` from the repo root
on their host machine rather than trying to fix it from inside this
session.

## Step 2 — GitHub PAT (needed to save weekly specs back to this repo)

Check whether `$GITHUB_PAT` is already set (it will be, on every run after
the first, once `bin/load-secrets.sh` has loaded it). If it's set, skip to
Step 3.

If not set:

1. Tell the user to open
   `https://github.com/settings/personal-access-tokens/new` in their
   browser themselves (don't navigate there for them — this is their
   GitHub login).
2. Tell them exactly what to fill in: **Repository access** → "Only select
   repositories" → their own fork of this repo. **Permissions** →
   Repository permissions → Contents → **Read and write**. Everything else
   left at its default (no access).
3. Ask them to paste the resulting token into the conversation. This is a
   token, not a password — pasting it here is the same pattern GitHub's own
   UI expects (compare to `integration-setup`'s general token-handling
   pattern, if that skill is available).
4. Write it to `/run/secrets/static/github_pat` (create the file with
   exactly the token's contents, no trailing formatting).
5. Run `bash bin/load-secrets.sh` (from the repo root) so it's live in this
   session immediately.
6. Verify with `git ls-remote origin` from the repo root — a successful
   listing confirms the PAT works and is scoped correctly. A permission
   error means the PAT's repository/permission selection was wrong; walk
   the user back through step 2.

## Step 3 — Which Google account for Strava

`star-strava-routes` logs into strava.com via "Log in with Google," and
needs to know which Google account to pick when more than one is available
in the browser.

Check whether `/run/secrets/static/google_account_email` exists. If not,
ask the user for the email address of the Google account they use to log
into Strava, write it to that file, and run `bash bin/load-secrets.sh`.

This is just an identifier, not a credential — no OAuth app or API token is
needed for Strava anywhere in this pipeline (`star-strava-routes` drives
the real strava.com site through the browser, not the Strava API).

## Step 4 — Chrome extension connected

Load the Chrome MCP tools and confirm the extension is reachable:

```
ToolSearch with query "select:mcp__claude-in-chrome__tabs_context_mcp"
```

Then call `tabs_context_mcp`. If it errors or times out, tell the user to
install/enable the Claude Code Chrome extension (they'll need to do this
themselves — it's a browser-side install) and try again. Don't proceed
past this step silently; `star-strava-routes` will otherwise fail later
with a less obvious error.

## Step 5 — Garmin Connect

The `garmin` MCP server needs a cached login session to start at all — with
no session yet, it fails to even connect, so its tools (`get_full_name`,
`get_workouts`, `create_run_workout`) won't be loaded this session, not even
as deferred tools. **That's the expected state before the very first Garmin
login below, not a sign container setup is broken** — only treat it as a
setup problem if it's still missing after completing the login and starting
a genuinely new session (see step 3).

1. If the `garmin` tools ARE loaded, call `get_full_name`. A successful
   response with a name means Garmin is already authenticated — skip to
   Step 6.
2. If the tools aren't loaded at all, or `get_full_name` errors, tell the
   user to open a **second terminal** into this same running container —
   `docker compose exec claude-agent bash` from the repo's `docker/`
   directory on their host — and run, in that second terminal themselves:
   ```
   GARMINTOKENS=/run/secrets/tokens/garmin_oauth_tokens \
   GARMINTOKENS_BASE64=/run/secrets/tokens/garmin_oauth_tokens_base64 \
   uvx --python 3.12 --from git+https://github.com/Taxuspt/garmin_mcp --with "mcp<2" garmin-mcp-auth
   ```
   The `GARMINTOKENS`/`GARMINTOKENS_BASE64` env vars point the login at the
   host-backed `/run/secrets/tokens` bind mount instead of `garmin_mcp`'s
   own default (`~/.garminconnect`, inside the container-managed
   `rogue-runner-agent-home` volume) — otherwise the resulting tokens
   wouldn't survive `docker volume rm`/`docker compose down -v` or a move
   to a different machine the way every other credential in this repo
   does. `--with "mcp<2"` works around an upstream bug: `garmin_mcp` pins
   `mcp>=1.28.1` with no upper bound, and the `mcp` package's `2.0.0`
   release dropped the module it imports (`mcp.server.fastmcp`), so
   without the pin this command crashes with
   `ModuleNotFoundError: No module named 'mcp.server.fastmcp'` before it
   ever prompts for credentials.

   This prompts for their Garmin email/password interactively in that
   terminal — never paste Garmin credentials into this conversation, and
   don't run this command via a Bash tool call yourself, since both would
   route the password through this session instead of staying local to the
   user's own terminal.
3. MCP servers only connect at session start, so completing the login above
   will **not** make the tools appear in this same running conversation —
   retrying `get_full_name` here won't work. Once the user confirms they've
   finished the login, tell them to exit this session and run `./setup.sh`
   again to start a fresh one (the cached login persists in the container's
   own storage across restarts, so this login step only has to happen
   once), then continue this checklist there and confirm `get_full_name`
   succeeds in that new session.

## Step 6 — Pace chart on file

Check whether `specs/resources/` (any filename containing "PACE" or
matching `*.xlsx`, case-insensitive) exists. This is Rogue Running's own
pace-chart document — not something this repo ships, since it isn't ours to
redistribute.

If missing, tell the user: `specs/resources/` is a normal folder in the
repo they cloned onto their own computer (this container's copy is a
direct bind mount of that same folder, not a separate copy) — they can
just save or drag their own pace-chart file (the one they already have
access to as a Rogue Running member) straight into it from Finder/File
Explorer, no git or terminal commands needed. Pause here until it's
present — `extract-workouts` can't resolve paces without it.

## Step 7 — Summary

Once every step above is resolved, tell the user plainly: setup is
complete, and they can paste their weekly coach email into the
conversation any time to run the full pipeline
(`weekly-training-pipeline`). If anything above was skipped or is still
unresolved, say exactly what's still missing rather than declaring success.

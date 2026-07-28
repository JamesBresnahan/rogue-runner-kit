# rogue-runner-kit

Turn your weekly Rogue Running coach email into starred Strava routes and
structured workouts scheduled straight onto your Garmin watch — no manual
copying of paces or intervals required.

## What this does

Every week, your coach's email describes that week's runs — easy days,
quality workouts, a long run — usually with a mileage range and named
paces (marathon pace, threshold, etc.) rather than exact numbers. Paste
that email into a conversation with Claude and it will:

1. Star any Strava routes mentioned in the email.
2. Work out the exact paces for your goal race and fitness level, and
   confirm the full week's plan with you before saving anything.
3. Build and schedule each workout day directly on your Garmin Connect
   account, so it shows up on your watch.

It runs inside an isolated container that only ever has access to your own
credentials (stored on your own machine) and your own copy of this repo —
nothing else on your computer.

## What you need first

- **Docker Desktop** installed and running —
  [download it here](https://www.docker.com/products/docker-desktop/) if
  you don't have it.
- **A Strava account.**
- **A Garmin Connect account**, with a watch that syncs to it.
- **The Claude Code Chrome extension**, installed and signed in to your
  Chrome browser (used only for starring Strava routes — everything else
  runs headless in the container).
- A **GitHub account** (to hold your own copy of this repo and your
  week-by-week training data).

You don't need to know git, Docker, or anything technical beyond copying
and pasting a few commands — the setup walks you through the rest
conversationally.

## Quick start

1. Click **Use this template** at the top of this repo's GitHub page. This
   gives you your own copy of this repo — your training data stays in
   *your* copy, never in this one.
2. Open a terminal (on a Mac: search for "Terminal" in Spotlight; on
   Windows: search for "PowerShell"). Paste in the clone command from your
   new repo's green **Code** button, e.g.:
   ```
   git clone https://github.com/YOUR-USERNAME/rogue-runner-kit.git
   cd rogue-runner-kit
   ```
3. Run:
   ```
   ./setup.sh
   ```
   The first time, it'll ask for your name/email (used for git commits)
   and then build and start everything.
4. It'll hand you off to a guided setup conversation with Claude — just
   follow along. It walks you through connecting GitHub, Strava, and
   Garmin one at a time, telling you exactly what to click and where. The
   Garmin step needs one manual action in a second terminal — see
   "Garmin login (one-time)" below.
5. Once it says you're set up, paste your weekly coach email into the
   conversation any time you want that week's workouts built.

Run `./setup.sh` again any time you want to start a new session — it
remembers your setup and just launches from there.

## Garmin login (one-time)

The Garmin side needs one manual, one-time step the setup conversation
can't do for you — it prompts for your Garmin email, password, and MFA
code directly, and those should never be typed into the chat.

1. Keep your `./setup.sh` session running. Open a **second terminal**, `cd`
   into this repo's `docker/` directory, and run:
   ```
   docker compose exec claude-agent bash
   ```
2. Inside that shell, run:
   ```
   uvx --python 3.12 --from git+https://github.com/Taxuspt/garmin_mcp garmin-mcp-auth
   ```
3. It'll prompt for your Garmin email, password, and MFA code (if you have
   2FA on) right there in that terminal.
4. MCP connections are only made when a session starts, so this won't take
   effect in your *current* conversation — exit it and run `./setup.sh`
   again to start a fresh one. The login is cached and persists across
   restarts, so you only need to do this once, ever.

## Pace chart

The Rogue Running pace chart isn't included in this repo — it's the
club's own material, not something we redistribute. `specs/resources/` is
a normal folder inside the copy of this repo you cloned onto your own
computer (the container sees that exact folder directly, not a separate
copy) — when the setup conversation asks for it, just save or drag your
own copy (the one you already have access to as a member) straight into
`specs/resources/` from Finder/File Explorer. No git or terminal commands
needed.

---

## Technical details

For the curious — none of this is required reading to get started.

**Isolation model.** Everything runs inside a single Docker container,
built fresh from this repo. It mounts only three things from your machine:
`~/agent-secrets/{static,tokens}` (your own credentials, nothing else),
the clone of this repo you're running `setup.sh` from (a direct bind mount
— what lets you drop files like the pace chart straight into
`specs/resources/` in a normal Finder/Explorer window), and a Docker-
managed volume for the container's own home directory (where things like
your cached Garmin login persist). It never sees your Documents,
Downloads, or any other project on your machine.

**Credential storage.** Credentials are written to
`~/agent-secrets/static/` (long-lived values like your GitHub PAT) or
`~/agent-secrets/tokens/` (things that expire and refresh) on your host
machine, and mounted read/write into the container at
`/run/secrets/static` and `/run/secrets/tokens`. Full conventions are
documented in this repo's own `CLAUDE.md`.

**Network.** The container runs with host networking rather than a fully
isolated network namespace — this is what lets it reach the Claude Code
Chrome extension on your machine, which is needed to star Strava routes
through the real site (not an API). Filesystem and credential isolation
above are unaffected by this.

**Skills.** Everything Claude knows about this pipeline lives in
`.claude/skills/` in this repo, loaded automatically by Claude Code — no
separate configuration or sync step. `first-run-setup` is also the skill
you'd invoke later if you ever want to re-verify your setup (just ask
Claude to "check my setup").

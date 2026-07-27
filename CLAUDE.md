# Standing guidance for this repo

Loaded automatically by Claude Code from this repo's root whenever a
session runs here. Applies to every skill in `.claude/skills/`.

## Credential handling for third-party integrations

Never handle a user's raw password or secret directly.

- **Storage location:** credentials live on the host under `~/agent-secrets/`
  and are mounted into the container as two directories: `/run/secrets/static`
  (long-lived static values — client IDs/secrets, PATs) and
  `/run/secrets/tokens` (OAuth access/refresh tokens, sessions). Never store
  secrets in-repo, in a project's `.env`, or in shell rc files.
- **Tokens over static credentials:** always prefer minting a token (OAuth
  access/refresh token, session, API key from a login) into `tokens/` over a
  raw username/password. Only put something in `static/` when it's needed to
  mint or refresh a token (`client_id` / `client_secret`) or no token flow
  exists for that service.
- **Naming convention:** filename is `<service>_<credential-type>`, lowercase,
  underscore-separated — e.g. `github_pat`, `google_account_email`. Each
  file's contents become an env var of the same name, uppercased (e.g.
  `github_pat` → `$GITHUB_PAT`), so a credential can be found from either its
  filename or its expected env var name.
- **Reload timing:** `bin/load-secrets.sh` re-reads both directories and
  re-exports every file as an env var. Claude Code normally snapshots the
  shell environment once at session start and every command in that session
  re-sources that static snapshot instead of live `~/.bashrc` — so a plain
  `~/.bashrc` hook alone would only pick up a credential added *before* a
  session starts, not one added mid-session. To close that gap,
  `load-secrets.sh` also patches the current session's own snapshot file
  directly, so running it once makes a newly-added credential visible to
  every following command in the session immediately, no restart needed.
  `docker/entrypoint.sh` wires `~/.bashrc` to source it for new shells, and
  runs it once directly at container boot.
- **Expiry tracking:** any token that expires gets a companion file,
  `<service>_<credential-type>_expires_at` (Unix timestamp or ISO 8601), in
  the same `tokens/` directory. Check it before using a token — if it's
  missing, expired, or within a few minutes of expiring, refresh proactively
  rather than waiting for a 401.
- **Auto-renewal:** when a token is expired or rejected, automatically run
  that service's refresh flow, overwrite the file(s) under
  `/run/secrets/tokens/` in place, then run `bash bin/load-secrets.sh` so the
  refreshed value is live for the rest of the session immediately. Only ask
  the user to re-authorize if the refresh itself fails (refresh token
  revoked/expired) or no refresh flow exists for that service.
- **Official OAuth/token APIs:** the user creates the API application and
  completes the browser consent/authorize step themselves, since that
  requires their login. Only handle the token exchange, never the
  consent/login step itself.
- **No self-serve personal API** (e.g. Garmin Connect): prefer an unofficial
  library where the user runs the initial login locally, themselves, to mint
  a cached session — normalized into `/run/secrets/tokens/` per the naming
  convention above — rather than pursuing an official developer/partner
  program built for businesses, which is usually slow and the wrong fit for
  personal use.

## Scheduling and time resolution

- Always check the actual current time before resolving a relative or
  ambiguous time in a scheduling request. If the resolved time has already
  passed, ask for clarification rather than silently rolling it forward to
  the next occurrence.
- Cloud-scheduled routines (the `schedule` skill / `RemoteTrigger`) run in an
  isolated sandbox with **no** access to the local browser session, saved
  logins, or credentials. `star-strava-routes` specifically cannot run this
  way, since it needs the local logged-in browser — only use cloud
  scheduling for parts of this pipeline that don't need local state (e.g. a
  bare push notification).
- Tasks that need the logged-in local browser (or other local session state)
  need the session-local `CronCreate` tool instead — but that only fires
  between turns while the session is idle, and is lost entirely if the
  session ends. Surface that caveat up front rather than letting the user
  assume it behaves like a durable cron job.

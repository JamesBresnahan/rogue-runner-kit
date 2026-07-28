#!/bin/bash
set -euo pipefail

REPO_DIR="/workspace/rogue-runner-kit"

load_secrets_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    local name
    name="$(basename "$f" | tr '[:lower:]' '[:upper:]')"
    export "$name"="$(cat "$f")"
  done
}

load_secrets_dir /run/secrets/static
load_secrets_dir /run/secrets/tokens

# garmin-mcp-auth (run manually, see README "Garmin login") and the garmin
# MCP server both write into GARMINTOKENS, but neither one reliably creates
# that subdirectory itself. Pre-create it once here, at container boot,
# rather than relying on the auth tool or a manual step in a second
# terminal to do it — this only runs once per container start, well before
# the user ever gets a shell.
mkdir -p /run/secrets/tokens/garmin_oauth_tokens
chmod 700 /run/secrets/tokens/garmin_oauth_tokens

if [ -n "${GITHUB_PAT:-}" ]; then
  git config --global credential.helper store
  echo "https://x-access-token:${GITHUB_PAT}@github.com" > "$HOME/.git-credentials"
  chmod 600 "$HOME/.git-credentials"
  export GH_TOKEN="${GITHUB_PAT}"

  # Repos cloned with SSH-style remotes (git@github.com:...) would otherwise
  # bypass the credential store above and need an ssh binary/key we don't
  # provision here. Rewrite them to HTTPS transparently so every remote uses
  # the PAT, without ever editing an individual repo's own git config.
  git config --global url."https://github.com/".insteadOf "git@github.com:"
  git config --global --add url."https://github.com/".insteadOf "ssh://git@github.com/"
fi

if [ -n "${GIT_USER_NAME:-}" ]; then
  git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "${GIT_USER_EMAIL:-}" ]; then
  git config --global user.email "$GIT_USER_EMAIL"
fi

# Wire new shells (e.g. a second `docker compose exec` terminal opened for
# garmin-mcp-auth) to pick up secrets added mid-session too, same pattern
# load-secrets.sh itself documents.
BASHRC="$HOME/.bashrc"
MARKER="# rogue-runner-kit: load agent-secrets"
if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
  {
    echo ""
    echo "$MARKER"
    echo "[ -f \"$REPO_DIR/bin/load-secrets.sh\" ] && source \"$REPO_DIR/bin/load-secrets.sh\""
  } >> "$BASHRC"
fi

# $REPO_DIR is a bind mount of the user's own host clone (see
# docker-compose.yml) — always already present, nothing to clone here.
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "$REPO_DIR doesn't look like a git repo — check docker-compose.yml's" >&2
  echo "bind mount and that you're running this from inside your clone." >&2
  exit 1
fi

# Register the garmin MCP server once, idempotently (remove then re-add so
# re-running this never leaves a stale duplicate registration). User scope
# so the *registration* lives in the persisted home volume — the actual
# OAuth tokens do not: GARMINTOKENS/GARMINTOKENS_BASE64 below point
# garmin_mcp at the host-backed /run/secrets/tokens bind mount instead of
# its own default (~/.garminconnect, inside the container-managed
# rogue-runner-agent-home volume), so a re-auth's tokens survive
# `docker volume rm`/`docker compose down -v` like every other credential
# in this repo. first-run-setup Step 5 and creating-garmin-workout use the
# same env vars when telling the user to run garmin-mcp-auth themselves.
if command -v claude >/dev/null 2>&1; then
  claude mcp remove garmin -s user >/dev/null 2>&1 || true
  # --with "mcp<2" pins the mcp SDK below the mcp==2.0.0 release, which
  # dropped mcp.server.fastmcp and breaks garmin_mcp (pins mcp>=1.28.1 with
  # no upper bound) — without this pin, uvx resolves the latest mcp and the
  # server fails to import (ModuleNotFoundError: mcp.server.fastmcp).
  claude mcp add garmin -s user \
    -e GARMINTOKENS=/run/secrets/tokens/garmin_oauth_tokens \
    -e GARMINTOKENS_BASE64=/run/secrets/tokens/garmin_oauth_tokens_base64 \
    -- uvx --python 3.12 --from git+https://github.com/Taxuspt/garmin_mcp --with "mcp<2" garmin-mcp \
    >/dev/null 2>&1 || echo "warning: failed to register garmin MCP server" >&2

  # Same pattern for the weather MCP server (cmer81/open-meteo-mcp, npm
  # package open-meteo-mcp-server). Open-Meteo's archive API is free and
  # keyless, so unlike garmin there's no separate auth step — registration
  # alone is enough. Base image is node:22-slim, so npx is already present.
  # Use --package= rather than -p: `claude mcp add`'s own arg parser treats
  # a bare -p in the trailing args as a global flag and fails with "unknown
  # option '-s'".
  claude mcp remove weather -s user >/dev/null 2>&1 || true
  claude mcp add weather -s user -- npx -y --package=open-meteo-mcp-server open-meteo-mcp-server \
    >/dev/null 2>&1 || echo "warning: failed to register weather MCP server" >&2
fi

cd "$REPO_DIR"

# When launched bare (no flags/prompt of its own), offer to resume one of
# the last 10 sessions for this repo instead of always starting fresh.
offer_session_picker() {
  local project_dir="$HOME/.claude/projects/-workspace-rogue-runner-kit"
  [ -d "$project_dir" ] || return 0
  [ -t 0 ] || return 0

  local files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(ls -t "$project_dir"/*.jsonl 2>/dev/null | head -10)
  [ "${#files[@]}" -eq 0 ] && return 0

  echo "Recent sessions:"
  echo "  0) Start a fresh session"
  local i=1 f sid title_line title prompt_line prompt ts summary
  for f in "${files[@]}"; do
    sid="$(basename "$f" .jsonl)"
    title_line="$(grep '"type":"ai-title"' "$f" | tail -1 || true)"
    title="$(printf '%s' "$title_line" | jq -r '.aiTitle // empty' 2>/dev/null || true)"
    if [ -n "$title" ]; then
      summary="$title"
    else
      prompt_line="$(grep '"type":"last-prompt"' "$f" | tail -1 || true)"
      prompt="$(printf '%s' "$prompt_line" | jq -r '.lastPrompt // empty' 2>/dev/null || true)"
      summary="${prompt:0:60}"
    fi
    ts="$(date -r "$f" '+%Y-%m-%d %H:%M')"
    printf "  %d) [%s] %s\n" "$i" "$ts" "$summary"
    i=$((i + 1))
  done

  local choice
  read -r -p "Choice [0]: " choice || choice=0
  case "$choice" in
    '' | *[!0-9]*) choice=0 ;;
  esac

  if [ "$choice" != "0" ] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ]; then
    SELECTED_SESSION_ID="$(basename "${files[$((choice - 1))]}" .jsonl)"
  fi
}

SELECTED_SESSION_ID=""
if [ "${1:-}" = "claude" ]; then
  offer_session_picker
  if [ -n "$SELECTED_SESSION_ID" ]; then
    set -- "$@" --resume "$SELECTED_SESSION_ID"
  fi
fi

exec "$@"

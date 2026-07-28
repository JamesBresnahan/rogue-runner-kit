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
  git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
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

# Clone the user's own fork on first boot; the named workspace volume
# persists it across later `docker compose run` invocations, so this only
# actually clones once per volume, not once per launch.
if [ ! -d "$REPO_DIR/.git" ]; then
  if [ -z "${ROGUE_RUNNER_FORK_URL:-}" ]; then
    echo "ROGUE_RUNNER_FORK_URL is not set and $REPO_DIR isn't already cloned." >&2
    echo "Re-run setup.sh from the repo root on your host machine." >&2
    exit 1
  fi
  git clone "$ROGUE_RUNNER_FORK_URL" "$REPO_DIR"
fi

# Register the garmin MCP server once, idempotently (remove then re-add so
# re-running this never leaves a stale duplicate registration). User scope
# so it lives in the persisted home volume, not committed to the repo.
if command -v claude >/dev/null 2>&1; then
  claude mcp remove garmin -s user >/dev/null 2>&1 || true
  claude mcp add garmin -s user -- uvx --python 3.12 --from git+https://github.com/Taxuspt/garmin_mcp garmin-mcp \
    >/dev/null 2>&1 || echo "warning: failed to register garmin MCP server" >&2
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

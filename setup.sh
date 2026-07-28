#!/usr/bin/env bash
# One script to set up (first run) and launch (every run) the running
# pipeline. Safe to re-run any time — it only asks questions once and
# reuses docker/.env after that.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "== rogue-runner-kit setup =="
echo

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker isn't installed. Install Docker Desktop, then run this script again:"
  echo "  https://www.docker.com/products/docker-desktop/"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "The 'docker compose' plugin isn't available (it ships with current"
  echo "Docker Desktop). Install/update Docker Desktop, then run this script again."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but doesn't seem to be running. Start Docker Desktop"
  echo "(just open the app), then run this script again."
  exit 1
fi

mkdir -p "$HOME/agent-secrets/static" "$HOME/agent-secrets/tokens"
chmod 700 "$HOME/agent-secrets" "$HOME/agent-secrets/static" "$HOME/agent-secrets/tokens"

ENV_FILE="docker/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "First-time setup — a few quick questions."
  echo
  echo "If you haven't already: click 'Use this template' at the top of this"
  echo "repo's GitHub page to get your own copy, then come back here with its URL."
  echo
  read -r -p "Your forked repo's clone URL (e.g. https://github.com/you/rogue-runner-kit.git): " FORK_URL
  read -r -p "Your name (used for git commits in your own repo): " GIT_NAME
  read -r -p "Your email (used for git commits): " GIT_EMAIL

  {
    echo "ROGUE_RUNNER_FORK_URL=$FORK_URL"
    echo "GIT_USER_NAME=$GIT_NAME"
    echo "GIT_USER_EMAIL=$GIT_EMAIL"
  } > "$ENV_FILE"
  echo
  echo "Saved to $ENV_FILE (not committed to git)."
else
  echo "Using existing configuration in $ENV_FILE."
  echo "(Delete that file and re-run this script if you want to reconfigure.)"
fi
echo

echo "Building the container image — first run only, takes a few minutes..."
docker compose -f docker/docker-compose.yml --env-file "$ENV_FILE" build

echo
echo "Starting Claude..."
exec docker compose -f docker/docker-compose.yml --env-file "$ENV_FILE" run --rm claude-agent claude --chrome

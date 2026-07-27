#!/usr/bin/env bash
# Loads per-credential files from the mounted agent-secrets directories into
# environment variables. Sourced by ~/.bashrc (wired by docker/entrypoint.sh)
# so every new shell picks up credentials added or renewed since the
# container started, and run directly by docker/entrypoint.sh for the
# container's initial boot environment.
#
# Claude Code snapshots the shell env once per session
# (~/.claude/shell-snapshots/snapshot-bash-*.sh) and every command in that
# session re-sources the static snapshot rather than live ~/.bashrc, so a
# credential added mid-session would otherwise sit invisible until a new
# session starts. To fix that, this script also patches the *current*
# session's snapshot file directly (found via /proc/$$/cmdline, which names
# it) so every subsequent command in the same session picks up the change
# immediately.

load_secrets_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  local f name
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f" | tr '[:lower:]' '[:upper:]')"
    export "$name"="$(cat "$f")"
  done
}

patch_session_snapshot() {
  local snapshot pid
  for pid in "$$" "$PPID"; do
    snapshot="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -oE '/[^ ]*/shell-snapshots/snapshot-bash-[^ ]*\.sh' | head -n1)"
    [ -n "$snapshot" ] && break
  done
  [ -n "$snapshot" ] && [ -w "$snapshot" ] || return 0

  local tmp dir f name value
  tmp="$(mktemp)"
  cp "$snapshot" "$tmp"
  for dir in /run/secrets/static /run/secrets/tokens; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
      [ -f "$f" ] || continue
      name="$(basename "$f" | tr '[:lower:]' '[:upper:]')"
      value="$(cat "$f")"
      grep -v "^export ${name}=" "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
      printf 'export %s=%q\n' "$name" "$value" >> "$tmp"
    done
  done
  cat "$tmp" > "$snapshot"
  rm -f "$tmp"
}

load_secrets_dir /run/secrets/static
load_secrets_dir /run/secrets/tokens
patch_session_snapshot

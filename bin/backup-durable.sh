#!/usr/bin/env bash
# memvault — "on-the-fly" backup of durable local state to the cloud vault.
#
# Wired to the Claude Code `Stop` hook → runs after EVERY assistant response, INSIDE the
# Claude Code process, which already holds Full Disk Access. That is the whole trick: a
# launchd/cron job CANNOT write to a cloud folder on macOS (TCC → "Operation not permitted"),
# but a hook inherits Claude Code's FDA and can. Fast + idempotent (rsync copies only diffs).
set -euo pipefail
source "${CLAUDE_VAULT_CONFIG:-$HOME/.config/memvault/config.sh}"

mkdir -p "$VAULT_DIR/memory" 2>/dev/null || true

# Memories: ~/.claude/projects/*/memory  →  vault/memory/<project>/
for mem in "$CLAUDE_DIR"/projects/*/memory; do
  [ -d "$mem" ] || continue
  proj="$(basename "$(dirname "$mem")")"
  rsync -a --exclude '.DS_Store' "$mem/" "$VAULT_DIR/memory/$proj/" 2>/dev/null || true
done

# Global instructions
[ -f "$CLAUDE_DIR/CLAUDE.md" ] && cp "$CLAUDE_DIR/CLAUDE.md" "$VAULT_DIR/CLAUDE.md" 2>/dev/null || true

exit 0

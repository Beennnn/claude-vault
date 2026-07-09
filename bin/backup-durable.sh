#!/usr/bin/env bash
# memvault — "on-the-fly" backup of durable local state to the cloud vault.
#
# Wired to the Claude Code `Stop` hook → runs after EVERY assistant response, INSIDE the
# Claude Code process, which already holds Full Disk Access. That is the whole trick: a
# launchd/cron job CANNOT write to a cloud folder on macOS (TCC → "Operation not permitted"),
# but a hook inherits Claude Code's FDA and can. Fast + idempotent (rsync copies only diffs).
set -euo pipefail
source "${CLAUDE_VAULT_CONFIG:-$HOME/.config/memvault/config.sh}"

# Map a Claude Code project key (cwd path with '/'→'-', e.g. -Users-benoitbesson-dev-ha) to a
# SHORT, human vault name. Deterministic, no hand-maintained table:
#   -<home>-dev-ha              → ha       (first segment after 'dev-')
#   -<home>-dev-iris-iris-ui    → iris     (sub-repos roll up to their group)
#   -<home>-perso               → perso
#   -<home>-dev                 → _general (the catch-all, drained over time)
vault_name() {
  local key="$1" home_prefix rel
  home_prefix="${HOME//\//-}"          # /Users/benoitbesson → -Users-benoitbesson
  rel="${key#"$home_prefix"}"; rel="${rel#-}"
  case "$rel" in
    dev)   echo "_general" ;;
    dev-*) rel="${rel#dev-}"; echo "${rel%%-*}" ;;
    "")    echo "_home" ;;
    *)     echo "${rel%%-*}" ;;
  esac
}

# Memories: ~/.claude/projects/<key>/memory  →  vault/projects/<name>/memory/
# Skip tombstone-only dirs (frozen/migrated projects whose only .md is MEMORY.md).
for mem in "$CLAUDE_DIR"/projects/*/memory; do
  [ -d "$mem" ] || continue
  [ "$(find "$mem" -maxdepth 1 -name '*.md' ! -name MEMORY.md 2>/dev/null | head -1)" ] || continue
  name="$(vault_name "$(basename "$(dirname "$mem")")")"
  mkdir -p "$VAULT_DIR/projects/$name/memory" 2>/dev/null || true
  rsync -a --exclude '.DS_Store' "$mem/" "$VAULT_DIR/projects/$name/memory/" 2>/dev/null || true
done

# Global instructions
[ -f "$CLAUDE_DIR/CLAUDE.md" ] && cp "$CLAUDE_DIR/CLAUDE.md" "$VAULT_DIR/CLAUDE.md" 2>/dev/null || true

exit 0

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
  local key="$1" home_prefix rel name pair
  home_prefix="${HOME//\//-}"          # /Users/benoitbesson → -Users-benoitbesson
  rel="${key#"$home_prefix"}"; rel="${rel#-}"
  case "$rel" in
    dev)   name="_general" ;;
    dev-*) rel="${rel#dev-}"; name="${rel%%-*}" ;;
    "")    name="_home" ;;
    *)     name="${rel%%-*}" ;;
  esac
  # Declared nesting (PROJECT_NESTING="child:parent …"): a child project's vault dir nests under
  # its parent → projects/<parent>/<child>/. Lets a general project (e.g. 'pro') contain an active
  # sub-project (e.g. 'iris') while iris stays its own Claude project on disk.
  for pair in ${PROJECT_NESTING:-}; do
    [ "${pair%%:*}" = "$name" ] && { echo "${pair#*:}/$name"; return; }
  done
  echo "$name"
}

# Memories: ~/.claude/projects/<key>/memory  →  vault/projects/<name>/memory/
# Skip tombstone-only dirs (frozen/migrated projects whose only .md is MEMORY.md).
for mem in "$CLAUDE_DIR"/projects/*/memory; do
  [ -d "$mem" ] || continue
  [ "$(find "$mem" -maxdepth 1 -name '*.md' ! -name MEMORY.md 2>/dev/null | head -1)" ] || continue
  name="$(vault_name "$(basename "$(dirname "$mem")")")"
  mkdir -p "$VAULT_DIR/projects/$name/memory" 2>/dev/null || true
  # --delete: the vault memory dir is a PURE MIRROR of the source memory dir, so a memory the
  # user deletes/moves must disappear from the vault too. Without it, rsync is additive-only and
  # stale copies pile up forever (a deleted memory silently survives in the backup). Safe here
  # because nothing but the source's own .md files is ever expected under vault/.../memory/.
  rsync -a --delete --exclude '.DS_Store' "$mem/" "$VAULT_DIR/projects/$name/memory/" 2>/dev/null || true
done

# Global instructions
[ -f "$CLAUDE_DIR/CLAUDE.md" ] && cp "$CLAUDE_DIR/CLAUDE.md" "$VAULT_DIR/CLAUDE.md" 2>/dev/null || true

# ~/dev governance anchors the relocator intentionally leaves in place (the DEV_ROOT/CLAUDE.md
# structure doc + declared DEV_ANCHOR_DIRS like perso/pro): they're exempt from quarantine AND
# not caught by the memory loop above → they'd fall through the cracks and never reach the vault.
# Back them up explicitly so a disk failure can't lose the one local copy.
[ -f "$DEV_ROOT/CLAUDE.md" ] && cp "$DEV_ROOT/CLAUDE.md" "$VAULT_DIR/dev-CLAUDE.md" 2>/dev/null || true
for a in ${DEV_ANCHOR_DIRS:-}; do
  [ -d "$DEV_ROOT/$a" ] || continue
  name="$(vault_name "${DEV_ROOT//\//-}-$a")"     # perso → projects/perso, pro → projects/pro
  mkdir -p "$VAULT_DIR/projects/$name" 2>/dev/null || true
  # anchors are non-code by declaration → mirror their top-level loose files; nested git repos
  # (e.g. a symlink to a real repo) back themselves up and are skipped by -type f.
  find "$DEV_ROOT/$a" -maxdepth 1 -type f ! -name '.DS_Store' -exec cp {} "$VAULT_DIR/projects/$name/" \; 2>/dev/null || true
done

# ── Coverage self-check — the systematic guard against "falls through the cracks" holes ───────
# Every cp/rsync above is best-effort (|| true) so a cloud-folder hiccup or TCC denial never
# blocks an assistant response. The flip side: a failure is SILENT. This block re-asserts that
# every durable we own actually reached the vault, printing a ⚠ UNBACKED line for any miss. That
# output is captured by relocate.sh into memvault.log, so a gap surfaces at the next SessionStart
# instead of being discovered only after a disk failure. The invariant it enforces: anything the
# relocator leaves in DEV_ROOT (its exemptions: DEV_ROOT/CLAUDE.md + DEV_ANCHOR_DIRS) is backed up.
missing=0
_assert() {                       # <local-src> <vault-dst that must exist>
  [ -e "$1" ] || return 0         # nothing to back up → not a gap
  [ -e "$2" ] && return 0
  echo "  ⚠ UNBACKED: ${1/#$HOME/\~} (expected ${2/#$HOME/\~})"; missing=1
}
_assert "$DEV_ROOT/CLAUDE.md" "$VAULT_DIR/dev-CLAUDE.md"
for a in ${DEV_ANCHOR_DIRS:-}; do
  [ -d "$DEV_ROOT/$a" ] || continue
  name="$(vault_name "${DEV_ROOT//\//-}-$a")"
  while IFS= read -r f; do _assert "$f" "$VAULT_DIR/projects/$name/$(basename "$f")"; done \
    < <(find "$DEV_ROOT/$a" -maxdepth 1 -type f ! -name '.DS_Store' 2>/dev/null)
done
# Memories: any source dir holding a real memory (.md ≠ MEMORY.md) must have a non-empty mirror.
for mem in "$CLAUDE_DIR"/projects/*/memory; do
  [ -d "$mem" ] || continue
  [ "$(find "$mem" -maxdepth 1 -name '*.md' ! -name MEMORY.md 2>/dev/null | head -1)" ] || continue
  name="$(vault_name "$(basename "$(dirname "$mem")")")"
  [ -n "$(find "$VAULT_DIR/projects/$name/memory" -maxdepth 1 -name '*.md' 2>/dev/null | head -1)" ] \
    || { echo "  ⚠ UNBACKED memories: ${mem/#$HOME/\~} (expected vault/projects/$name/memory/)"; missing=1; }
done
[ "$missing" -eq 0 ] && echo "  [backup] coverage OK — all durables mirrored to vault" || true

exit 0

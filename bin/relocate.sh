#!/usr/bin/env bash
# memvault — session-start relocator + catch-up backup.
#
# Wired to the Claude Code `SessionStart` hook (inherits Full Disk Access). It:
#   1. backs up durable local state (memories → vault/projects/<name>/memory/, + CLAUDE.md) by
#      delegating to backup-durable.sh (single source of the vault layout + name mapping);
#   2. QUARANTINES any non-git file that drifted into DEV_ROOT → vault/_relocated/<date>/ —
#      DEV_ROOT is meant to hold git repos ONLY, so a stray non-git file there is a policy
#      violation, not something to mirror. Nothing is deleted. Files touched in the last 5 min
#      are skipped (don't grab a concurrent session's work); dotdirs + CLAUDE.md are ignored.
#   3. flags repos that are not committed / not pushed (backup gap).
source "${CLAUDE_VAULT_CONFIG:-$HOME/.config/memvault/config.sh}"
LOG="$CLAUDE_DIR/memvault.log"
stamp="$(date '+%Y-%m-%d %H:%M:%S')"

# Exempt declared non-code launch anchors (DEV_ANCHOR_DIRS, e.g. 'perso') from quarantine: they
# live in DEV_ROOT without being git repos on purpose, just to give a non-code project a cwd.
_anchor_filter() {
  [ -z "${DEV_ANCHOR_DIRS:-}" ] && { cat; return; }
  local pat=""; for a in $DEV_ANCHOR_DIRS; do pat="${pat:+$pat|}$DEV_ROOT/$a/"; done
  grep -Ev "^($pat)" || true
}

{
  echo "=== $stamp relocate/backup ==="

  # 1. Catch-up backup of durables (memories + CLAUDE.md) — delegated to backup-durable.sh
  bash "$(dirname "$0")/backup-durable.sh" && echo "  [1] durables backed up → vault/projects/<name>/memory"

  # 2. Quarantine stray non-git files that drifted into DEV_ROOT (git-only zone)
  for root in "$DEV_ROOT" ${EXTRA_DEV_ROOTS:-}; do
    [ -d "$root" ] || continue
    find "$root" -type d -exec test -e '{}/.git' ';' -prune -o -type f ! -name '.DS_Store' -mmin +5 -print 2>/dev/null \
      | grep -vx "$root/CLAUDE.md" | grep -v "/\\.[^/]*/" | _anchor_filter | while IFS= read -r f; do
        rel="${f#"$root"/}"
        dest="$VAULT_DIR/_relocated/$(date +%Y%m%d-%H%M)/$rel"    # git-only zone → quarantine
        mkdir -p "$(dirname "$dest")"
        mv "$f" "$dest" && echo "  [2] RELOCATED $(basename "$root")/$rel → ${dest#"$VAULT_DIR"/}"
      done
  done

  # 3. Flag repos not fully backed up
  while IFS= read -r r; do
    ( cd "$r" 2>/dev/null || exit 0
      name="${r#"$DEV_ROOT"/}"
      [ -n "$(git status --porcelain 2>/dev/null)" ] && echo "  [3] ⚠ $name : UNCOMMITTED changes"
      if [ -n "$(git remote 2>/dev/null)" ] && [ -z "$(git branch -r --contains HEAD 2>/dev/null)" ]; then
        echo "  [3] ⚠ $name ($(git branch --show-current)) : HEAD NOT PUSHED"
      fi )
  done < <(find "$DEV_ROOT" ${EXTRA_DEV_ROOTS:-} -name .git -maxdepth 4 2>/dev/null | sed 's|/\.git$||')
  echo "=== done ==="
} >> "$LOG" 2>&1
command -v osascript >/dev/null && grep -q "RELOCATED" <(tail -20 "$LOG") && \
  osascript -e "display notification \"Non-git files relocated into the vault (mirrored)\" with title \"memvault\"" 2>/dev/null || true

# Auto-push committed work + snapshot WIP to refs/backup (no-op unless AUTO_PUSH=true)
bash "$(dirname "$0")/push-repos.sh" 2>/dev/null || true
exit 0

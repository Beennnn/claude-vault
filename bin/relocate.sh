#!/usr/bin/env bash
# memvault — session-start relocator + catch-up backup.
#
# Wired to the Claude Code `SessionStart` hook (inherits Full Disk Access). It:
#   1. backs up durable local state (memories + CLAUDE.md) to the vault;
#   2. MIRRORS the git-repo hierarchy of DEV_ROOT into the vault (same top-level groups), and
#      RELOCATES any non-git file that drifted into DEV_ROOT to the MATCHING group folder in the
#      vault — so the vault stays organized exactly like your code tree. Loose files at the
#      DEV_ROOT root (no group) go to vault/_relocated/<date> (quarantine). Nothing is deleted.
#      Files modified in the last 5 min are skipped (don't grab a concurrent session's work).
#   3. flags repos that are not committed / not pushed (backup gap) — never auto-pushes.
source "${CLAUDE_VAULT_CONFIG:-$HOME/.config/memvault/config.sh}"
LOG="$CLAUDE_DIR/memvault.log"
stamp="$(date '+%Y-%m-%d %H:%M:%S')"

{
  echo "=== $stamp relocate/backup ==="

  # 1. Catch-up backup of durables
  mkdir -p "$VAULT_DIR/memory"
  for mem in "$CLAUDE_DIR"/projects/*/memory; do
    [ -d "$mem" ] || continue
    proj="$(basename "$(dirname "$mem")")"
    rsync -a --exclude '.DS_Store' "$mem/" "$VAULT_DIR/memory/$proj/"
  done
  [ -f "$CLAUDE_DIR/CLAUDE.md" ] && cp "$CLAUDE_DIR/CLAUDE.md" "$VAULT_DIR/CLAUDE.md"
  echo "  [1] durables backed up → vault"

  # 2. Mirror the repo hierarchy + relocate stray non-git into the MATCHING group folder
  for root in "$DEV_ROOT" ${EXTRA_DEV_ROOTS:-}; do
    [ -d "$root" ] || continue
    # 2a. mirror DEV_ROOT's top-level groups as vault folders (parallel structure)
    for g in "$root"/*/; do
      [ -d "$g" ] || continue
      mkdir -p "$VAULT_DIR/$(basename "$g")"
    done
    # 2b. relocate stray files (outside any repo), preserving their group path
    find "$root" -type d -exec test -e '{}/.git' ';' -prune -o -type f ! -name '.DS_Store' -mmin +5 -print 2>/dev/null \
      | grep -vx "$root/CLAUDE.md" | grep -v "/\\.[^/]*/" | while IFS= read -r f; do
        rel="${f#"$root"/}"
        grp="${rel%%/*}"
        if [ "$grp" != "$rel" ] && [ -d "$root/$grp" ]; then
          dest="$VAULT_DIR/$rel"                                  # ~/dev/<group>/x → vault/<group>/x
        else
          dest="$VAULT_DIR/_relocated/$(date +%Y%m%d-%H%M)/$rel"  # loose at dev root → quarantine
        fi
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

#!/usr/bin/env bash
# claude-vault — session-start relocator + catch-up backup.
#
# Wired to the Claude Code `SessionStart` hook (inherits Full Disk Access). It:
#   1. backs up durable local state (memories + CLAUDE.md) to the vault — catches anything a
#      previous session's Stop hook missed (crash, manual edit outside a session);
#   2. RELOCATES any non-git content that drifted into DEV_ROOT → vault/_relocated/<date>
#      (quarantine, never deleted) so tier 1 stays "git repos only";
#   3. flags repos that are not committed / not pushed (backup gap) — never auto-pushes
#      (that is a human judgement call).
source "${CLAUDE_VAULT_CONFIG:-$HOME/.config/claude-vault/config.sh}"
LOG="$CLAUDE_DIR/claude-vault.log"
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

  # 2. Relocate stray non-git out of DEV_ROOT (files that sit OUTSIDE any repo)
  for root in "$DEV_ROOT" ${EXTRA_DEV_ROOTS:-}; do
    [ -d "$root" ] || continue
    stray="$(find "$root" -type d -exec test -e '{}/.git' ';' -prune -o -type f ! -name '.DS_Store' -print 2>/dev/null \
      | grep -vx "$root/CLAUDE.md" || true)"
    if [ -n "$stray" ]; then
      quar="$VAULT_DIR/_relocated/$(date +%Y%m%d-%H%M)"
      echo "$stray" | while IFS= read -r f; do
        rel="${f#"$root"/}"
        mkdir -p "$quar/$(dirname "$rel")"
        mv "$f" "$quar/$rel" && echo "  [2] RELOCATED $(basename "$root")/$rel → _relocated/"
      done
      command -v osascript >/dev/null && osascript -e "display notification \"Non-git files relocated from $(basename "$root") to the vault\" with title \"claude-vault\"" 2>/dev/null || true
    fi
  done

  # 3. Flag repos not fully backed up (uncommitted or unpushed)
  flagged=0
  while IFS= read -r r; do
    ( cd "$r" 2>/dev/null || exit 0
      name="${r#"$DEV_ROOT"/}"
      [ -n "$(git status --porcelain 2>/dev/null)" ] && echo "  [3] ⚠ $name : UNCOMMITTED changes"
      if [ -n "$(git remote 2>/dev/null)" ] && [ -z "$(git branch -r --contains HEAD 2>/dev/null)" ]; then
        echo "  [3] ⚠ $name ($(git branch --show-current)) : HEAD NOT PUSHED to any remote"
      fi )
  done < <(find "$DEV_ROOT" ${EXTRA_DEV_ROOTS:-} -name .git -maxdepth 4 2>/dev/null | sed 's|/\.git$||')

  echo "=== done ==="
} >> "$LOG" 2>&1
exit 0

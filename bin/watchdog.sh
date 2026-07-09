#!/usr/bin/env bash
# claude-vault — passive policy watchdog (runs via launchd, BETWEEN sessions).
#
# Unlike the hooks, launchd has NO Full Disk Access → it cannot read/write the cloud vault
# (TCC). So this watchdog only checks what is verifiable LOCALLY and NON-cloud:
#   - every repo under DEV_ROOT is committed AND pushed (else code is not backed up);
#   - no non-git content is sitting in DEV_ROOT.
# On a violation it fires a desktop notification + logs. The actual fixing (relocation, cloud
# backup) is done by the hooks, which run with Claude Code's FDA.
source "${CLAUDE_VAULT_CONFIG:-$HOME/.config/claude-vault/config.sh}"
LOG="$CLAUDE_DIR/claude-vault-watchdog.log"
issues=()

# Repos: committed + pushed (HEAD reachable from a remote → backed up)
while IFS= read -r r; do
  ( cd "$r" 2>/dev/null || exit 0 )
  cd "$r" 2>/dev/null || continue
  name="${r#"$DEV_ROOT"/}"
  [ -n "$(git status --porcelain 2>/dev/null)" ] && issues+=("$name: uncommitted")
  if [ -z "$(git remote 2>/dev/null)" ]; then
    issues+=("$name: NO remote → not backed up")
  elif [ -z "$(git branch -r --contains HEAD 2>/dev/null)" ]; then
    issues+=("$name ($(git branch --show-current)): HEAD not pushed")
  fi
done < <(find "$DEV_ROOT" ${EXTRA_DEV_ROOTS:-} -name .git -maxdepth 4 2>/dev/null | sed 's|/\.git$||')

# DEV_ROOT hygiene: no non-git files outside repos
nongit="$(find "$DEV_ROOT" -type d -exec test -e '{}/.git' ';' -prune -o -type f ! -name '.DS_Store' -print 2>/dev/null \
  | grep -vx "$DEV_ROOT/CLAUDE.md" | grep -v '/\.claude/' | head -5 || true)"
[ -n "$nongit" ] && issues+=("non-git in $(basename "$DEV_ROOT"): $(echo "$nongit" | tr '\n' ' ')")

ts="$(date '+%Y-%m-%d %H:%M:%S')"
if [ ${#issues[@]} -eq 0 ]; then
  echo "[$ts] OK — policy respected" >> "$LOG"
else
  echo "[$ts] ⚠ ${#issues[@]} violation(s):" >> "$LOG"
  printf '  - %s\n' "${issues[@]}" >> "$LOG"
  command -v osascript >/dev/null && osascript -e "display notification \"${issues[*]}\" with title \"⚠ claude-vault watchdog\" sound name \"Basso\"" 2>/dev/null || true
fi
exit 0

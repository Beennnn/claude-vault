#!/usr/bin/env bash
# memvault — auto-push (opt-in via AUTO_PUSH=true). Called by the watchdog (launchd) and the
# SessionStart relocator. `git push` is a NETWORK op — no Full Disk Access needed — so it works
# from launchd. Two levels, both SAFE:
#
#   1. COMMITTED-but-unpushed work on a NON-protected branch  → pushed to origin/<branch>
#      (normal push; main/master are skipped to honour "never push to main directly").
#
#   2. UNCOMMITTED work (tracked + untracked)  → snapshotted to  refs/backup/<branch>  on the
#      remote, WITHOUT touching your working tree / index / HEAD (uses a throwaway index). A
#      custom ref (not refs/heads/*) means: NO CI trigger, NO branch-list clutter, nothing to
#      clean up — yet it's fully recoverable:
#         git fetch origin 'refs/backup/*:refs/backup/*'
#         git log refs/backup/<branch>      # inspect / cherry-pick / checkout
#
# So nothing local ever stays un-backed: commits go to their branch, WIP goes to a hidden ref.
source "${CLAUDE_VAULT_CONFIG:-$HOME/.config/memvault/config.sh}"
[ "${AUTO_PUSH:-false}" = "true" ] || exit 0
[ -n "${GIT_SSH_KEY:-}" ] && export GIT_SSH_COMMAND="ssh -i $GIT_SSH_KEY -o IdentitiesOnly=yes"
LOG="$CLAUDE_DIR/memvault-push.log"

{
  echo "=== $(date '+%F %T') auto-push ==="
  while IFS= read -r gd; do
    repo="${gd%/.git}"
    cd "$repo" 2>/dev/null || continue
    name="${repo#"$DEV_ROOT"/}"
    [ -n "$(git remote 2>/dev/null)" ] || continue          # no remote → nothing to push
    branch="$(git branch --show-current 2>/dev/null)"

    # 1. committed but not on any remote → push the branch (skip protected)
    if [ -z "$(git branch -r --contains HEAD 2>/dev/null)" ]; then
      case "$branch" in
        main|master) echo "  ⚠ $name : commits sur '$branch' NON auto-poussés (protégé)" ;;
        "")          : ;;                                    # detached HEAD → handled as wip below
        *)           git push origin "HEAD:refs/heads/$branch" >/dev/null 2>&1 \
                       && echo "  ⬆ $name:$branch poussé" || echo "  ✗ $name:$branch push refusé" ;;
      esac
    fi

    # 2. uncommitted (tracked+untracked) → refs/backup/<branch>, non-intrusive snapshot
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
      ti="$(mktemp)"
      GIT_INDEX_FILE="$ti" git read-tree HEAD 2>/dev/null
      GIT_INDEX_FILE="$ti" git add -A 2>/dev/null
      tree="$(GIT_INDEX_FILE="$ti" git write-tree 2>/dev/null)"
      rm -f "$ti"
      if [ -n "$tree" ]; then
        c="$(git commit-tree "$tree" -p HEAD -m "memvault wip backup $(date '+%F %T')" 2>/dev/null)"
        [ -n "$c" ] && git push -f origin "$c:refs/backup/${branch:-detached}" >/dev/null 2>&1 \
          && echo "  💾 $name : WIP → refs/backup/${branch:-detached}"
      fi
    fi
  done < <(find "$DEV_ROOT" ${EXTRA_DEV_ROOTS:-} -name .git -maxdepth 4 -type d 2>/dev/null | sed 's|/\.git$||')
  echo "=== done ==="
} >> "$LOG" 2>&1
exit 0

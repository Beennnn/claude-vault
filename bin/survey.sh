#!/usr/bin/env bash
# memvault — OPTIONAL disk survey (opt-in via SURVEY_ROOTS). It only *reports* — never moves.
# At session start Claude uses the output to ASK you how to protect each finding, offering the
# three strategies in docs/strategies.md: (a) relocate into the vault, (b) have the cloud client
# back up the folder in place, (c) symlink a fixed-location folder into the vault.
#
# It surfaces two kinds of risk:
#   • durable files sitting OUTSIDE every backed-up zone;
#   • git repos ANYWHERE outside DEV_ROOT that are uncommitted or unpushed (code at risk).
#
# What counts as "not user data" is driven by two community-maintained lists you can extend via
# PR (see CONTRIBUTING.md):  rules/ignore-dirs.txt (folder names) and rules/ignore-paths.txt
# (path substrings). Add a false positive there and the whole community benefits.
source "${CLAUDE_VAULT_CONFIG:-$HOME/.config/memvault/config.sh}"
[ -z "${SURVEY_ROOTS:-}" ] && exit 0

REPORT="$CLAUDE_DIR/memvault-survey.txt"
STAMP="$CLAUDE_DIR/.memvault-survey.stamp"
[ "${1:-}" != "--force" ] && [ -f "$STAMP" ] && [ -z "$(find "$STAMP" -mmin +1440 2>/dev/null)" ] && exit 0
touch "$STAMP"
RULES="${MEMVAULT_RULES:-$(cd "$(dirname "$0")/../rules" 2>/dev/null && pwd)}"

# --- folder-name prune list = rules/ignore-dirs.txt + SURVEY_IGNORE_NAMES (handles spaces) ---
names=()
[ -f "$RULES/ignore-dirs.txt" ] && while IFS= read -r ln; do
  [[ "$ln" =~ ^[[:space:]]*(#|$) ]] || names+=("$ln")
done < "$RULES/ignore-dirs.txt"
for n in ${SURVEY_IGNORE_NAMES:-}; do names+=("$n"); done
nameargs=(); for n in "${names[@]}"; do nameargs+=( -name "$n" -o ); done; nameargs+=( -false )

# --- path-substring excludes = rules/ignore-paths.txt ---
igfile="$(mktemp)"; [ -f "$RULES/ignore-paths.txt" ] && grep -vE '^[[:space:]]*(#|$)' "$RULES/ignore-paths.txt" > "$igfile"

# --- already-backed-up zone prefixes ---
zregex="$(printf '%s\n' $BACKED_UP_ZONES 2>/dev/null | sed 's#[][^$.*/\\]#\\&#g' | paste -sd'|' -)"

# --- 1) durable files outside any backed-up zone ---
: > "$REPORT"
for root in $SURVEY_ROOTS; do
  [ -d "$root" ] || continue
  find "$root" \( -type d \( "${nameargs[@]}" \) -prune \) -o \( -type f ! -name '.DS_Store' -mmin +5 -print \) 2>/dev/null
done \
  | { [ -n "$zregex" ] && grep -vE "^($zregex)(/|\$)" || cat; } \
  | { [ -s "$igfile" ] && grep -vFf "$igfile" || cat; } \
  | grep -vE "^$HOME/\.[^/]+\$" | head -3000 >> "$REPORT"
rm -f "$igfile"

# --- 2) git repos outside DEV_ROOT that are dirty / unpushed (code at risk) ---
atrisk=""
for root in $SURVEY_ROOTS; do
  while IFS= read -r gd; do
    repo="${gd%/.git}"
    case "$repo/" in "$DEV_ROOT"/*) continue ;; esac
    inside=$( cd "$repo" 2>/dev/null && {
      [ -n "$(git status --porcelain 2>/dev/null)" ] && { echo dirty; exit; }
      [ -n "$(git remote 2>/dev/null)" ] && [ -z "$(git branch -r --contains HEAD 2>/dev/null)" ] && echo unpushed
    } )
    [ -n "$inside" ] && atrisk="$atrisk ${repo#$HOME/}($inside)"
  done < <(find "$root" -maxdepth 5 -name .git -type d 2>/dev/null)
done

# --- report ---
n=$(wc -l < "$REPORT" 2>/dev/null | tr -d " "); n=${n:-0}
msg=""
if [ "${n:-0}" -gt 0 ]; then
  folders=$(sed "s|^$HOME/||" "$REPORT" | awk -F/ 'NF>1{print $1"/"$2} NF==1{print $1}' | sort | uniq -c | sort -rn | head -12 | awk '{printf "%s(%s) ",$2,$1}')
  msg="$n durable file(s) outside any backed-up zone, in: $folders"
fi
[ -n "$atrisk" ] && msg="$msg${msg:+ | }git repos NOT backed up (outside ~/dev):$atrisk"
[ -n "$msg" ] && echo "🔎 memvault survey: $msg — ask the user PER ITEM how to protect it (relocate / cloud-backup-in-place / symlink; for repos: commit+push or move into ~/dev). Full file list: $REPORT"
exit 0

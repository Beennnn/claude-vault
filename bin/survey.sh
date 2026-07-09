#!/usr/bin/env bash
# memvault — OPTIONAL disk survey.
#
# Finds durable local files that sit OUTSIDE every backed-up zone, so that at session start
# Claude can ASK you how to protect them. It only *reports* — it never moves anything. Claude
# then offers, per finding (see docs/strategies.md):
#   (a) relocate it into the vault;
#   (b) have your cloud client back up its folder IN PLACE (e.g. Google Drive "mirror a folder
#       from your computer") — best when the folder is fine where it is (Downloads, Desktop…);
#   (c) SYMLINK a location-constrained folder into the vault — best when an app requires the
#       folder at a fixed path but you want it continuously synced to the cloud.
#
# Opt-in: set SURVEY_ROOTS in config.sh (empty = disabled). Throttled to once/day.
source "${CLAUDE_VAULT_CONFIG:-$HOME/.config/memvault/config.sh}"
[ -z "${SURVEY_ROOTS:-}" ] && exit 0

REPORT="$CLAUDE_DIR/memvault-survey.txt"
STAMP="$CLAUDE_DIR/.memvault-survey.stamp"
[ "${1:-}" != "--force" ] && [ -f "$STAMP" ] && [ -z "$(find "$STAMP" -mmin +1440 2>/dev/null)" ] && exit 0
touch "$STAMP"

# Directory names to prune entirely (heavy / regenerable / not user data)
nameargs=(); for n in ${SURVEY_IGNORE_NAMES:-}; do nameargs+=( -name "$n" -o ); done
nameargs+=( -false )

# Regex of already-backed-up path prefixes to exclude
zregex="$(printf '%s\n' $BACKED_UP_ZONES 2>/dev/null | sed 's#[][^$.*/\\]#\\&#g' | paste -sd'|' -)"

: > "$REPORT"
for root in $SURVEY_ROOTS; do
  [ -d "$root" ] || continue
  find "$root" \( -type d \( "${nameargs[@]}" \) -prune \) -o \( -type f ! -name '.DS_Store' -mmin +5 -print \) 2>/dev/null
done | { [ -n "$zregex" ] && grep -vE "^($zregex)(/|\$)" || cat; } \
     | grep -vE "^$HOME/\.[^/]+\$" | head -3000 >> "$REPORT"   # drop home-root dotfiles (config/secrets)

n=$(grep -c . "$REPORT" 2>/dev/null || echo 0)
if [ "${n:-0}" -gt 0 ]; then
  folders=$(sed "s|^$HOME/||" "$REPORT" | awk -F/ 'NF>1{print $1"/"$2} NF==1{print $1}' | sort | uniq -c | sort -rn | head -12 | awk '{printf "%s(%s) ",$2,$1}')
  echo "🔎 memvault survey: $n local file(s) outside any backed-up zone, in: $folders — ask the user PER FOLDER how to protect it: (a) move to the vault, (b) have the cloud back up the folder in place, (c) symlink a fixed-location folder into the vault. Full list: $REPORT"
fi
exit 0

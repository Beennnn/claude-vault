#!/usr/bin/env bash
# memvault — installer. Idempotent: safe to re-run.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

# --- 1. config -----------------------------------------------------------------------------
if [ ! -f "$here/config.sh" ]; then
  echo "→ no config.sh yet — copying config.example.sh; EDIT it then re-run ./install.sh"
  cp "$here/config.example.sh" "$here/config.sh"
  exit 1
fi
# shellcheck source=/dev/null
source "$here/config.sh"
: "${CLAUDE_DIR:?}" "${DEV_ROOT:?}" "${VAULT_DIR:?}"

SHARE="$HOME/.local/share/memvault"
CONFIG_DST="$HOME/.config/memvault/config.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "→ installing scripts to $SHARE/bin"
mkdir -p "$SHARE/bin" "$(dirname "$CONFIG_DST")" "$VAULT_DIR/memory"
cp "$here"/bin/*.sh "$SHARE/bin/"; chmod +x "$SHARE"/bin/*.sh
cp -R "$here/rules" "$SHARE/"                 # community ignore rules (survey reads ../rules)
cp "$here/config.sh" "$CONFIG_DST"

# --- 2. merge Claude Code hooks (Stop + SessionStart) --------------------------------------
echo "→ wiring hooks into $SETTINGS"
python3 - "$SETTINGS" "$SHARE" <<'PY'
import json, sys, os
settings_path, share = sys.argv[1], sys.argv[2]
d = json.load(open(settings_path)) if os.path.exists(settings_path) else {}
hooks = d.setdefault("hooks", {})
def ensure(event, cmd, asy=True):
    arr = hooks.setdefault(event, [])
    if not arr:
        arr.append({"hooks": []})
    entry = arr[0].setdefault("hooks", [])
    if not any(h.get("command") == cmd for h in entry):
        entry.append({"type": "command", "command": cmd, "timeout": 30, "async": asy})
def ensure_matched(event, matcher, cmd):
    arr = hooks.setdefault(event, [])
    block = next((b for b in arr if b.get("matcher") == matcher), None)
    if block is None:
        block = {"matcher": matcher, "hooks": []}
        arr.append(block)
    entry = block.setdefault("hooks", [])
    if not any(h.get("command") == cmd for h in entry):
        entry.append({"type": "command", "command": cmd, "timeout": 15, "async": True})
ensure("Stop",         f"bash {share}/bin/backup-durable.sh")
ensure("SessionStart", f"bash {share}/bin/relocate.sh")
ensure("SessionStart", f"bash {share}/bin/survey.sh", asy=False)  # sync: output reaches Claude
ensure_matched("PostToolUse", "Write|Edit", f"bash {share}/bin/backup-on-write.sh")
json.dump(d, open(settings_path, "w"), indent=2)
print("  hooks OK (Stop + SessionStart×2 + PostToolUse)")
PY

# --- 3. launchd watchdog -------------------------------------------------------------------
echo "→ installing launchd watchdog (every 3h + at login)"
PLIST="$HOME/Library/LaunchAgents/com.memvault.watchdog.plist"
sed -e "s|__VAULT_BIN__|$SHARE/bin|g" -e "s|__VAULT_CONFIG__|$CONFIG_DST|g" \
    "$here/launchd/com.memvault.watchdog.plist.template" > "$PLIST"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

# --- 4. policy in CLAUDE.md ----------------------------------------------------------------
if ! grep -q "memvault policy" "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
  echo "→ appending policy to $CLAUDE_DIR/CLAUDE.md"
  printf '\n' >> "$CLAUDE_DIR/CLAUDE.md"
  cat "$here/CLAUDE.md.snippet" >> "$CLAUDE_DIR/CLAUDE.md"
fi

# --- 5. first backup + report --------------------------------------------------------------
CLAUDE_VAULT_CONFIG="$CONFIG_DST" bash "$SHARE/bin/backup-durable.sh" || true
cat <<EOF

✅ memvault installed.
   Tier 1 (code)     : $DEV_ROOT        → git repos, pushed
   Tier 2 (vault)    : $VAULT_DIR       → cloud-synced, off-machine
   Tier 3 (local)    : $CLAUDE_DIR      → disposable; memories+CLAUDE.md backed up to vault
   Hooks             : Stop (on-the-fly backup) + SessionStart (catch-up + relocate)
   Watchdog          : com.memvault.watchdog (launchd, 3h + login)

Tip (Google Drive/iCloud): mark $VAULT_DIR "Available offline" so it is never evicted.
EOF

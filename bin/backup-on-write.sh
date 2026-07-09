#!/usr/bin/env bash
# memvault — immediate backup when a durable file is WRITTEN, mid-response.
#
# Wired to the Claude Code `PostToolUse` hook (matcher Write|Edit). The `Stop` hook only fires
# when Claude finishes responding, so during a LONG response the on-the-fly backup would wait.
# This closes that gap: the instant Claude writes a memory or CLAUDE.md, it is mirrored — no
# need to interrupt the response. Cheap: it only fires for durable paths, and rsync copies diffs.
source "${CLAUDE_VAULT_CONFIG:-$HOME/.config/memvault/config.sh}" 2>/dev/null || exit 0
f="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"
case "$f" in
  "$CLAUDE_DIR"/projects/*/memory/*|"$CLAUDE_DIR"/CLAUDE.md)
    exec bash "$(dirname "$0")/backup-durable.sh" ;;
esac
exit 0

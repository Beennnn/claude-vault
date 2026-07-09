#!/usr/bin/env bash
# memvault — configuration.
# Copy this file to  config.sh  and edit the paths for your machine.
# install.sh copies it to  ~/.config/memvault/config.sh  (read by every script).

# --- Tier 3 : Claude Code's own data directory (where memories + CLAUDE.md live) ---
CLAUDE_DIR="${HOME}/.claude"

# --- Tier 1 : root that contains ONLY git repositories (your code) ---
DEV_ROOT="${HOME}/dev"

# --- Tier 2 : the cloud-backed "vault" — everything durable non-code goes here ---
# Point this at a folder INSIDE a synced cloud drive so it is replicated off-machine.
# Works with anything that presents a local folder:
#   Google Drive : ~/Library/CloudStorage/GoogleDrive-<you>/My Drive/claude   (or a ~/gdrive symlink to it)
#   iCloud Drive : ~/Library/Mobile Documents/com~apple~CloudDocs/claude
#   Dropbox      : ~/Dropbox/claude
#   rclone mount : ~/mnt/gdrive/claude
VAULT_DIR="${HOME}/gdrive/claude"

# --- Optional: extra folders to treat as "must be a git repo" beyond DEV_ROOT (space-separated) ---
EXTRA_DEV_ROOTS=""

# --- Optional: disk survey ------------------------------------------------------------------
# Find durable local files that are NOT in any backed-up zone, so Claude can ask you (at
# session start) how to protect them. Leave SURVEY_ROOTS empty to disable.
# Set to "$HOME" to survey your whole home directory.
SURVEY_ROOTS=""
# Path prefixes ALREADY backed up (excluded from the survey). Add folders your cloud client
# mirrors in place — e.g. if you told Google Drive to back up ~/Downloads and ~/Desktop:
#   BACKED_UP_ZONES="$DEV_ROOT $VAULT_DIR $HOME/Library/CloudStorage $HOME/Downloads $HOME/Desktop"
BACKED_UP_ZONES="$DEV_ROOT $VAULT_DIR $HOME/Library/CloudStorage"
# Directory NAMES to skip entirely (heavy / regenerable / not user data):
SURVEY_IGNORE_NAMES="Library node_modules .git .Trash .cache .npm .cargo .rustup .gradle .venv venv __pycache__ Applications Parallels"

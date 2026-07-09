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

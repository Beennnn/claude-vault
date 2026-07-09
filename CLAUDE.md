# memvault — instructions for Claude

**This repo configures Claude Code itself.** If a user opens you inside this repo and asks to
"set up / install memvault" (or similar), self-configure their machine by following the
steps below. Do it **interactively and carefully** — you are editing their environment.

## What memvault does (say this to the user first)

A 3-tier storage policy with automatic backup:
- **Tier 1** `~/dev/` — code, git repos only (private, pushed).
- **Tier 2** a **cloud vault** — everything durable non-code, replicated off-machine (→ NAS).
- **Tier 3** `~/.claude/` — disposable; memories + `CLAUDE.md` stay local but are mirrored to
  the vault by hooks.
Backups run from **Claude Code hooks** (which inherit Full Disk Access) so they can write the
cloud — a plain `launchd`/`cron` job cannot (macOS TCC). See `docs/architecture.md`.

## Setup steps

1. **Detect the cloud drive.** Look for a synced folder to host the vault, in this order, and
   propose the first that exists (let the user override):
   - Google Drive: `~/Library/CloudStorage/GoogleDrive-*/My Drive` (or a `~/gdrive` symlink)
   - iCloud: `~/Library/Mobile Documents/com~apple~CloudDocs`
   - Dropbox: `~/Dropbox`
   Set `VAULT_DIR="<that>/claude"`.
2. **Confirm `DEV_ROOT`** (default `~/dev`) and that it holds git repos.
3. **Write `config.sh`** from `config.example.sh` with the confirmed paths.
4. **Run `./install.sh`.** It copies the scripts, wires the `Stop` + `SessionStart` +
   `PostToolUse` hooks into `~/.claude/settings.json` (preserving existing hooks), installs the
   launchd watchdog, appends the policy to `~/.claude/CLAUDE.md`, and does a first backup.
5. **Verify:** `settings.json` still valid JSON; the three hooks present; the watchdog loaded
   (`launchctl list | grep memvault`); the vault has `memory/` + `CLAUDE.md`.
6. **Tell the user** to mark `VAULT_DIR` "Available offline" in their cloud client, and — if on
   Google Drive/Synology — that Cloud Sync will replicate it to the NAS.

## Ongoing: the disk survey (if enabled)

If `SURVEY_ROOTS` is set, a `SessionStart` hook runs `bin/survey.sh`, which reports durable
local files sitting **outside every backed-up zone**. When you see its line at session start
(`🔎 memvault survey: N file(s)…`), **read the report** (`~/.claude/memvault-survey.txt`) and
**ask the user how to protect each file/folder**, offering the three strategies from
[`docs/strategies.md`](docs/strategies.md):

- **(a) relocate** it into the vault (for movable files),
- **(b)** have the cloud client **back up its folder in place** (for Downloads/Desktop/Documents),
- **(c) symlink** a fixed-location folder into the vault (for app-constrained paths).

When the user picks (b) for a folder, **add that folder to `BACKED_UP_ZONES`** in their config so
the survey stops flagging it. Never move a user's files without asking. Read
[`docs/lessons.md`](docs/lessons.md) before touching symlinks or verifying a cloud copy.

## Important cautions

- **Never delete** user data. Relocations go to `vault/_relocated/` (quarantine).
- **Do not** grant Full Disk Access to `/bin/bash` — the hook approach exists precisely to
  avoid that. If a backup logs `Operation not permitted`, the fix is to run it from a hook (in
  Claude Code's context), never to widen FDA.
- The scripts are idempotent; re-running `install.sh` is safe.
- After setup, **follow the tier policy yourself**: write code only into git repos under
  `DEV_ROOT`, durable non-code into `VAULT_DIR`, nothing important loose in `~`.

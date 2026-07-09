# Backup strategies for files outside `~/dev` and the vault

When the optional [disk survey](../bin/survey.sh) finds durable local files that aren't in any
backed-up zone, Claude asks you how to protect each one (or each folder). There are three
strategies — pick per case:

## (a) Relocate into the vault
**Move the file into `VAULT_DIR/<group>/`.** Best when the file has no reason to live where it
is — a stray note, an export, a working file. It then rides the vault's cloud→NAS backup and
sits in the mirrored group structure. This is what the `SessionStart` relocator does
automatically for stray files inside `~/dev`.

- ✅ Simplest, fully automatic afterwards.
- ⚠️ Only for files that can *move*.

## (b) Have the cloud client back up the folder **in place**
**Leave the folder where it is; tell your cloud client to mirror it.** Google Drive for Desktop
has *“Folders from your computer”* (Preferences → *My Computer* → *Add folder*); Dropbox has
*Backup*; OneDrive has *Known Folder Move*. Best for folders that are fine where they are and
that you'd rather not move — **`~/Downloads`, `~/Desktop`, `~/Documents`**.

- ✅ Zero disruption; the folder stays put and is backed up continuously.
- ⚠️ One-time GUI step in the cloud client. On Google Drive these land under
  *Computers / <your Mac>* in Drive, not under *My Drive*.
- After enabling it, **add the folder to `BACKED_UP_ZONES`** so the survey stops flagging it.

## (c) Symlink a location-constrained folder into the vault
**When an app *requires* a folder at a fixed path** (a plugin config, a device profile store)
but you want it continuously synced: move the real folder into `VAULT_DIR` and leave a
**symlink** at the original path.

- ✅ The app keeps its fixed path; the data lives in the cloud and syncs to the NAS.
- ⚠️ Caveats we learned the hard way (see [lessons.md](lessons.md)):
  - Editors/tools may **refuse to write through a symlink** — fine for app data, *not* for files
    you edit with Claude's Edit/Write tools (that's why memories stay real+copied, not symlinked).
  - Cloud **online-only eviction**: pin the vault *“Available offline”* so a symlinked folder is
    always materialized (never a dead link when offline).
  - A background job still **cannot write** the cloud folder (macOS TCC) — but reads/writes from
    an app that holds Full Disk Access (Claude Code, the app that owns the folder) work.

## Decision cheatsheet

| The file/folder… | Strategy |
|---|---|
| can move, no fixed home | **(a)** relocate into the vault |
| is fine where it is (Downloads/Desktop/Documents) | **(b)** cloud backs it up in place |
| must stay at a fixed path (app requirement) | **(c)** symlink into the vault |

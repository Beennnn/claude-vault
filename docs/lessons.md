# Lessons learned (the experience behind memvault)

memvault's design is the residue of a long real-world session getting Claude Code work reliably
backed up on macOS. The non-obvious findings, so you don't rediscover them the hard way:

## 1. A background job cannot write to a cloud folder on macOS
macOS **TCC** protects the cloud File Providers (`~/Library/CloudStorage/…`). A `launchd`/`cron`
job starts with **no Full Disk Access** → any write returns `Operation not permitted`. This is
the single fact that shapes everything.

## 2. …but a Claude Code **hook** can
Hooks run *inside* the Claude Code process, which already holds Full Disk Access, so they
**inherit** it and can write the cloud. That's why every backup in memvault is a hook
(`PostToolUse` / `Stop` / `SessionStart`), and the launchd watchdog only *reads* local state and
*flags* — it never touches the cloud.

## 3. FDA is per-executable, and per-process-identity
- Granting Full Disk Access to `/bin/bash` gives it to **every** shell script on the machine —
  broad and dangerous. Don't. Use a hook (or, if you must, a dedicated signed helper app).
- Your **Terminal** having FDA does **not** help a `launchd` job: they are different process
  identities. "My shell can write the Drive" ≠ "my scheduled job can."

## 4. Don't symlink files you edit with Claude's tools
Symlinking memories/`CLAUDE.md` into the cloud looks elegant, but Claude Code's **Edit/Write
tools refuse to write through a symlink** ("Refusing to write through symlink"). It breaks the
editing workflow. So durable, *editable* files stay **real local files** and are **copied** to
the vault. Symlinks are fine for **app data you don't edit** (strategy (c)).

## 5. Cloud "online-only" files break naive verification
Google Drive/iCloud evict unused files to online-only (dataless). Consequences:
- A symlinked file can be unavailable offline → **pin the vault "Available offline."**
- `rsync -an` (even `--size-only`) against a cloud destination reports evicted files as
  **missing/different** — so it **cannot** verify "everything copied." Verify by **file name/path**
  (which is always present) or via the cloud **web UI** (storage/file counts). Don't trust a
  content/size diff of a cloud folder.

## 6. Git vs cloud for backup — use both, for different reasons
- **Git**: automates with **zero permissions** (network push, no FDA) and gives real **version
  history**. But it's not on your NAS without extra steps.
- **Cloud vault**: replicates to your **NAS** for free (Cloud Sync), but a scheduled write needs
  FDA — which the hook approach provides.
For small durable text (memories), the cloud vault (via hooks) + git are complementary;
memvault standardizes on the cloud vault and leaves git for your code.

## 7. Safety rules that prevented real losses
- **Never delete** — relocate to `vault/_relocated/` (quarantine) and notify.
- **Skip files modified in the last 5 minutes** — so a relocation never grabs another running
  session's in-flight work (multiple sessions are safe).
- **Move, verify, then remove** — when copying into a cloud folder, never bare-`mv` into a
  freshly-created cloud subfolder (the write can be lost mid-sync); rsync + check first.

## 8. Structure beats sprawl
Keep `~/dev` **git-only** (every leaf a pushed repo) and make the vault **mirror** its group
hierarchy. Then "where does this file go?" always has one answer, and both trees evolve together.

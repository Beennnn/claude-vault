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

## 9. An additive backup silently accumulates stale copies
`rsync -a` **without `--delete`** only ever *adds*. On a **pure mirror** (like
`vault/projects/<name>/memory/`, which should contain nothing but the source's own `.md`), that
means a memory you **delete or move** survives in the vault **forever** — the backup and the
source drift apart and the "deleted" fact is quietly still there. Fix: `rsync --delete` on pure
mirrors so the vault tracks deletions. Scope it carefully — **never** put `--delete` on an
aggregate dir (`artifacts/`) that legitimately holds vault-only files, or the backup would wipe
them. Rule of thumb: `--delete` is for dirs that are a 1:1 copy of a single source, nothing else.

## 10. Exemptions without coverage = the "falls through the cracks" hole
The relocator keeps `~/dev` git-only by quarantining stray non-git files — **except** a few it
deliberately leaves in place (`DEV_ROOT/CLAUDE.md`, the `DEV_ANCHOR_DIRS` non-code anchors). The
trap: a file that is *exempt from quarantine* is **not** automatically *backed up*. It's durable,
unversioned, and — if nobody copies it — has a **single local copy** that a disk failure erases.
This bit us with `~/dev/CLAUDE.md` and `perso/`+`pro/`'s `README.md`: exempt on one side, uncovered
on the other, invisible in between. The root cause is **two divergent lists** — the relocator's
exemptions and the backup's coverage — maintained independently. The durable fix is an
**invariant**, not a patch: *whatever the relocator leaves in `DEV_ROOT`, the backup must cover.*

## 11. Best-effort backup needs a self-check, or failures are silent
Every `cp`/`rsync` in the backup is `|| true` on purpose: a cloud-folder eviction or a TCC hiccup
must **never** block an assistant response. The price is that a failure is **silent** — you only
find out when you reach for the file and it isn't there. The cure is cheap: after doing the
backup, **re-assert it** — walk the same list of durables and check each one actually landed in
the vault, printing `⚠ UNBACKED <path>` for any miss. Route that output somewhere seen at session
start (here: `memvault.log`, via `relocate.sh`). A backup you don't verify is a hope, not a backup.

## 12. Audit memvault under **bash**, never inline in an interactive **zsh**
The scripts carry `#!/usr/bin/env bash` and rely on **bash word-splitting** — e.g.
`for a in $DEV_ANCHOR_DIRS` iterating over `perso` then `pro`. Replaying such a snippet **inline
in an interactive zsh** (the default macOS shell) gives *different* behavior: zsh does **not**
word-split unquoted variables, so the loop runs **once** with `a="perso pro"` and any derived
regex is wrong. During an audit this produces **false positives** ("these anchor files look
uncovered!") that don't reflect the real runtime. Always exercise memvault logic the way it
actually runs — `bash script.sh`, or `bash -c '…'` — not pasted into your zsh prompt.

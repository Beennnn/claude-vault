# Architecture & design notes

## Why 3 tiers

Every file Claude Code touches falls into exactly one of three categories, and each has a
natural home:

1. **Code** — belongs in version control. Git already gives you history, off-site backup
   (the remote), and diffs. So code lives in `~/dev`, and the rule is simply *every leaf of
   `~/dev` is a git repo* (grouping sub-folders are fine — e.g. `~/dev/ha/deebot-client/` may
   hold several related forks). Backup = `git push`.
2. **Durable non-code** — notes, exports, generated artefacts, working files. Git is the wrong
   tool (binary churn, no diffs). A **cloud drive** is right: it's replicated off-machine and,
   if you run something like Synology Cloud Sync, mirrored to your **NAS** for free. This is
   the **vault** (`VAULT_DIR`).
3. **Disposable** — session transcripts, caches, plugin data. Regenerable; no backup needed.
   This is `~/.claude`.

The awkward case: **memories** (`~/.claude/projects/*/memory/`) and the global **`CLAUDE.md`**
are *durable* but *must physically live in tier 3* because Claude Code reads them from fixed
paths. claude-vault keeps them local (so the editor tools work — see below) and **mirrors**
them into the vault.

## Why not symlink the memories into the vault?

The obvious idea is to `ln -s` the memory dirs into the cloud vault so they "live" there.
Two reasons not to:

1. **Claude Code's Edit/Write tools refuse to write through a symlink** ("Refusing to write
   through symlink") — a safety guard. That breaks the memory-editing workflow.
2. **Online-only eviction.** A cloud file the OS has evicted is unavailable offline; a symlinked
   `CLAUDE.md` could fail to load at session start with no network.

So memories stay **real local files** (tools work, always available) and are **copied** to the
vault. The copy is cheap (`rsync` diffs) and continuous (a hook after every response).

## The TCC / Full Disk Access problem — and the hook solution

macOS **TCC** (Transparency, Consent & Control) protects "sensitive" locations — including the
cloud-storage File Providers (`~/Library/CloudStorage/…`). A process may only write there if it
has **Full Disk Access (FDA)**.

- Your **Terminal** / **Claude Code** typically *have* FDA → interactive writes to the vault work.
- A **`launchd` / `cron`** job starts with **no** FDA → writing the vault returns
  `Operation not permitted`. And FDA is **per-executable**: granting it to `/bin/bash` gives it
  to *every* shell script on the machine (broad, risky).

**claude-vault's resolution:** do the cloud writes from **Claude Code hooks**, which execute
inside the Claude Code process and therefore **inherit its FDA** — no new grant, no risk. The
launchd watchdog stays FDA-less on purpose: it only reads local git state and *flags*; it never
touches the cloud.

| Actor | Has FDA? | Can write the vault? | Role in claude-vault |
|---|---|---|---|
| Claude Code session (hooks) | yes (inherited) | ✅ | backup + relocate |
| launchd watchdog | no | ❌ | flag only |
| Cloud client (Drive/iCloud) | n/a | — | vault → NAS replication |

## Coverage

| Trigger | Script | Guarantees |
|---|---|---|
| `Stop` hook (every response) | `backup-durable.sh` | memories + `CLAUDE.md` mirrored on the fly |
| `SessionStart` hook | `relocate.sh` | catch-up backup; stray non-git moved out of `~/dev`; unpushed repos flagged |
| launchd (3h + login) | `watchdog.sh` | passive alert on unpushed repos / non-git in `~/dev` |

Nothing is ever deleted. Relocations are **quarantined** in `vault/_relocated/<date>/` for you
to triage.

## Portability

The scripts are path-agnostic: everything is driven by `config.sh`
(`CLAUDE_DIR`, `DEV_ROOT`, `VAULT_DIR`). Point `VAULT_DIR` at any synced cloud folder. The
FDA/TCC specifics are macOS-only; on Linux the hooks still work (there is no TCC wall there, so
a plain cron job would work too — but the hook approach is still the cleanest).

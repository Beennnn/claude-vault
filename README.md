<p align="center">
  <img src="docs/banner.svg" alt="memvault" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-hooks-6C5CE7" alt="Claude Code">
  <img src="https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white" alt="macOS">
  <img src="https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white" alt="bash">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT">
</p>

<p align="center"><b>Never lose your Claude Code work — memories, rules, and code, backed up automatically.</b></p>

---

## What problem it solves

Claude Code quietly builds up things you'd hate to lose:

- its **memories** (`~/.claude/projects/*/memory/`) — knowledge it accumulates over months,
- your growing **`CLAUDE.md`** — your rules and hard-won context,
- **files it generates**, and **code** spread across many repos.

**By default none of it is backed up.** One disk failure, one bad edit, or one forgotten
unpushed branch = lost work. **memvault makes that impossible**, without you thinking about it:

- **Code** → stays in **git** (private repos, pushed).
- **Everything else durable** (memories, notes, generated files) → mirrored to your **cloud
  drive**, and on to your **NAS**.
- A quiet **watchdog** warns you the moment code isn't pushed or something lands in the wrong place.

## Where it runs

- **Claude Code**, any project.
- **macOS** (the clever bit below is macOS-specific; it also runs on Linux, even more simply).
- **Any cloud drive** that syncs a local folder — Google Drive, iCloud, Dropbox, or an rclone
  mount. If your cloud mirrors to a **NAS** (e.g. Synology Cloud Sync), your work lands on your
  own hardware too.

## Install

```bash
git clone https://github.com/Beennnn/memvault.git && cd memvault
cp config.example.sh config.sh      # set your cloud folder (VAULT_DIR)
./install.sh                        # idempotent — safe to re-run
```

Or just open Claude Code in the repo and say **“set up memvault for me”** — it reads its own
[`CLAUDE.md`](CLAUDE.md) and installs itself.

---

## How it works (in detail)

Everything you touch is sorted into **3 tiers**, each with one backup path:

<p align="center"><img src="docs/diagram.svg" alt="3-tier architecture" width="90%"></p>

| Tier | What | Where | Backup |
|---|---|---|---|
| **1** | **Code** | `~/dev/` — git repos only, private, pushed | the git remote |
| **2** | **Everything durable non-code** | your **cloud vault** | cloud → NAS |
| **3** | **The rest** (transcripts, cache…) | `~/.claude/` — disposable | none needed |

Memories and `CLAUDE.md` *must* live in tier 3 (Claude reads them there) but are durable — so
they stay local **and** are mirrored to the vault. That mirroring runs from **Claude Code hooks**:

| When | Hook | Does |
|---|---|---|
| The instant a memory is written | `PostToolUse` | mirror it now — a long response never waits |
| After every response | `Stop` | on-the-fly backup |
| At session start | `SessionStart` | catch-up + **mirror your repo hierarchy into the vault** + move any stray non-git into its matching group folder |
| Between sessions | `launchd` watchdog | passively flag unpushed repos / stray files (notification) |

**The vault mirrors your code tree.** memvault keeps the vault's top-level structure in step with
`~/dev` (same groups — `music/`, `work/`, …). A non-git file that drifts into `~/dev/music/` is
moved to `vault/music/`, so your durable files are organized exactly like your repos, and both
sides evolve together. Files loose at the `~/dev` root (no group) go to `vault/_relocated/`.
Nothing is ever deleted.

## The catch — and how memvault beats it

The obvious way to back up to your Drive is a scheduled job (`cron`/`launchd`). **On macOS it
doesn't work:** the privacy system (**TCC**) blocks background jobs from writing to cloud
folders —

```
rsync: … /Google Drive/…: open: Operation not permitted
```

— unless you grant **Full Disk Access** to `/bin/bash`, which hands *every* shell script on your
machine access to all your private data. Bad trade.

**memvault's trick:** do the backup from a **Claude Code hook**. A hook runs *inside* Claude
Code, which already has Full Disk Access — so it can write the vault with **no new permission and
no new risk**. The launchd watchdog stays permission-less on purpose: it only reads local git
state and *flags*; the hooks do the writing.

Full design + the TCC/FDA deep-dive: [`docs/architecture.md`](docs/architecture.md).

## Optional: survey the rest of your disk

Set `SURVEY_ROOTS="$HOME"` and a `SessionStart` hook scans (once/day) for anything **not** backed
up — durable files outside every backed-up zone **and** git repos anywhere that are uncommitted or
unpushed. It only *reports*, grouped by folder; Claude then asks you, per finding, which
[strategy](docs/strategies.md) to use: **(a)** relocate into the vault, **(b)** have your cloud
client back the folder up in place (great for `~/Downloads`, `~/Desktop`, `~/Documents`), or
**(c)** symlink a fixed-location folder into the vault. Add folders your cloud already mirrors to
`BACKED_UP_ZONES` so they stop being flagged.

What the survey treats as "not user data" comes from two community lists —
[`rules/ignore-dirs.txt`](rules/ignore-dirs.txt) and
[`rules/ignore-paths.txt`](rules/ignore-paths.txt) — that anyone can extend by PR.

## Contributing

memvault gets smarter as people feed back the special cases they hit on real machines — usually a
one-line addition to a rules file. See [CONTRIBUTING.md](CONTRIBUTING.md). The golden rule:
**never** add anything that could hide irreplaceable user data, and relocations are
quarantine-only (nothing is ever deleted).

## License

MIT — see [LICENSE](LICENSE).

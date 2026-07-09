# Contributing to memvault

memvault gets smarter as people run it on real machines and feed back the **special cases** they
hit. The most valuable contributions are usually a one-line addition to a rules file.

## Teach the survey a special case (the common PR)

The [disk survey](bin/survey.sh) flags files that aren't backed up. Sometimes it flags something
that is actually fine — an app's cache, a cloud client's own folder, a device backup. When that
happens, add the case to the shared rules so **everyone's** survey stops flagging it:

- A whole **folder that's regenerable / app-managed** (a cache, a build dir, an app bundle) →
  add its **name** to [`rules/ignore-dirs.txt`](rules/ignore-dirs.txt).
- A **location that's already a backup** (a cloud client's local folder, a NAS sync dir, a
  device backup) → add a **path substring** to [`rules/ignore-paths.txt`](rules/ignore-paths.txt).

**How:**
```bash
# 1. fork + branch
git checkout -b rule/ignore-<thing>
# 2. add your line to the right rules file, with a short comment on WHAT it is
echo "SomeAppCache" >> rules/ignore-dirs.txt
# 3. re-run the survey to confirm the noise is gone
bash bin/survey.sh --force && cat "$HOME/.claude/memvault-survey.txt"
# 4. commit + open a PR
```
In the PR, say **which app/tool** produces the folder and **why it's safe to skip** (regenerable?
already synced elsewhere?). That context is what lets a maintainer accept it quickly.

Please **don't** add:
- anything that could contain **irreplaceable user data** (documents, presets you'd hate to lose)
  — those *should* be surfaced so the user can back them up;
- machine-specific absolute paths (use a folder **name** or a portable **substring** instead).

## Other contributions

- **Code / behavior** — bug fixes and features welcome. Keep the scripts POSIX-ish bash, path-
  agnostic (everything via `config.sh`), and idempotent. Run `bash -n` on every script.
- **New cloud provider** — the vault just needs a local synced folder; if a provider needs a
  special path, document it in `config.example.sh`.
- **Docs / lessons** — hit a macOS/TCC/hook gotcha we didn't document? Add it to
  [`docs/lessons.md`](docs/lessons.md).

## Ground rules

- **Never** make a change that could delete user data. Relocations are quarantine-only.
- Test on a real machine before opening a PR; paste the before/after survey output.
- One special case per PR keeps review fast.

Thanks — every accepted rule makes memvault quieter and more trustworthy for the next person.

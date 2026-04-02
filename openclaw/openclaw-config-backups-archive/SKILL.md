---
name: openclaw-config-backups-archive
description: Archive and clean OpenClaw backup config files under ~/.openclaw. Use when the user asks to tidy OpenClaw backup files, normalize openclaw*bak* names into ~/.openclaw/.archived, convert old archived names to the new bak format, or trash archived files older than 30 days.
---

# openclaw-config-backups-archive

Use bundled script `scripts/archive_openclaw_backups.zsh` (Linux + macOS compatible).

## What it does
- Ensure archive directory exists: `~/.openclaw/.archived`.
- Scan both `~/.openclaw` root and `~/.openclaw/.archived` for files that:
  - start with `openclaw`
  - contain `bak`
- Canonical target name in archive: `openclaw.bak.YYYYMMDD-HHMMSS.json`.
- If a file is already in archive and already matches canonical format, skip it.
- Convert archived old-format files without `.bak.` segment:
  - `openclaw.YYYYMMDD-HHMMSS.json` -> `openclaw.bak.YYYYMMDD-HHMMSS.json`
- Timestamp source for canonical names:
  - use `ctime` when readable
  - fallback to `mtime` only if `ctime` cannot be read
- Collision handling for canonical names:
  - increment timestamp by +1 second until no conflict
- Trash policy:
  - files in `~/.openclaw/.archived` with `mtime > 30 days` are sent to Trash via CLI backend (not direct `mv`)
  - backend priority: `trash` -> `gio trash` -> `trash-put`
  - if no backend exists: apply mode fails with an explicit error; dry-run still reports candidates

## Commands
- Dry run:
  - `zsh ./scripts/archive_openclaw_backups.zsh --dry-run` (from this skill directory)
- Apply:
  - `zsh ./scripts/archive_openclaw_backups.zsh --apply` (from this skill directory)

## Notes
- Moving to Trash is non-destructive compared with direct deletion.
- No day parameter is exposed; retention is fixed at 30 days.
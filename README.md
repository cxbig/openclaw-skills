# Skills - Shared Skill Pool

Shared, git-managed skill repository used by multiple agents.

## Directory Layout

- `openclaw/`
  - `openclaw-config-backups-archive/`
    - `SKILL.md`
    - `scripts/archive_openclaw_backups.zsh`
- `obsidian/`
  - `obsidian-reading-ingest/`
- `obsidian-skills/`
- `git/`

## Recent Changes (synced)

- Replaced legacy `config-file-archive.sh/.md` with a structured skill package:
  - `openclaw/openclaw-config-backups-archive`
- Removed old standalone files from `openclaw/` (sent to Trash).
- `archive_openclaw_backups.zsh` now supports both Linux and macOS command differences.
- Trash handling now uses CLI backends (`trash` -> `gio trash` -> `trash-put`) instead of direct file moves to Trash paths.
- Added/kept `obsidian/obsidian-reading-ingest` as the new reading-ingest workflow skill.

## Conventions

- Prefer zsh for shell scripts (`#!/usr/bin/env zsh`).
- Use timestamp format `YYYYMMDD-HHMMSS` for OpenClaw backup archive names.
- Keep skill folders self-contained (`SKILL.md`, optional `scripts/`, `references/`, `assets/`).
- Prefer one canonical skill per function; remove deprecated duplicates after migration.

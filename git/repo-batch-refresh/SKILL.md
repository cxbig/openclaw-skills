---
name: repo-batch-refresh
version: "1.1.0"
description: Batch-refresh a large set of local git repositories under a given root directory. Use when you need to fast-forward update many repos safely (without disrupting the current worktree), with concurrency via --batch and optional --debug output. Repos with a .ignore marker are reported as SKIP.
---

# git-repo-batch-refresh

This skill provides a local Rust-based CLI: `git-repo-batch-refresh`.

Goal: **refresh many local git repositories under a root directory** by updating each repo's default branch reference (best-effort detection via `origin/HEAD`, fallback to `main`).

## Usage

```bash
git-repo-batch-refresh <ROOT_DIR> [--batch 20] [--debug]
```

Examples:

```bash
git-repo-batch-refresh /path/to/repos --batch 20
git-repo-batch-refresh /path/to/repos --debug
```

Flags:

- `<ROOT_DIR>` (positional, required): directory to scan for git repos
- `--batch <N>`: max parallel workers (default: 20)
- `--debug`: print branch details per repo and expand NOK error blocks

## Output

All output lines share a 4-character prefix aligned on the pipe separator (`" | "`).

### OK

```
  OK | <project-id>
```

### NOK

Without `--debug` (single line only):

```
 NOK | <project-id>
```

With `--debug` (error block expanded):

```
 NOK | <project-id>
     | ----------------------------------------
     | <error messages>
     | ----------------------------------------
```

### SKIP

```
SKIP | <project-id>
```

`<project-id>` is derived from `git remote get-url origin` (token-safe parsing). If parsing fails, it falls back to a path relative to `<ROOT_DIR>`.

## Ignore rules

- If a repo root contains `.ignore`: report it as `SKIP` and do not refresh it

## Summary line

```
Processed <total> projects: OK <n>, NOK <n>, SKIP <n>. Total time <duration>.
```

## Build (local)

Run the provided script (user-run only). It builds a release binary and writes it to this skill's `scripts/` directory as an executable (`0755`).

```bash
cd "/path/to/skills/git/repo-batch-refresh"
./scripts/build.zsh

./scripts/git-repo-batch-refresh --help
# Or if you like you can also install to the system local bin folder
sudo install -m 0755 ./scripts/git-repo-batch-refresh /usr/local/bin/
```

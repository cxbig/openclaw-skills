---
name: obsidian-reading-ingest
description: Ingest one URL at a time into Obsidian reading notes with stable verification. Use when the user asks to read/fetch an article URL and write it into `obsidian/reading`. Initialize once per session by loading `obsidian/README.md` and `obsidian/reading/README.md`, then process URLs one by one.
---

# Obsidian Reading Ingest

Process exactly one URL per turn and write to `obsidian/reading` with deterministic checks.

## Global Constraints (must keep)

- When writing into Obsidian Vault, prioritize skills under `~/Workspaces/skills/obsidian-skills/skills/`.
- For article reading/fetching, use Browser tool as the primary path with local headed Chrome and `openclaw` profile.
- Do not use `web_search` / `web_fetch` as the main reading path for this workflow.

## Rule Source Policy

- Keep README files as the single source of truth for Obsidian rules.
- Do not copy full README rules into this skill.
- If any wording in this skill conflicts with README, follow README and report that the skill needs sync.

## Session Initialization (once per session)

On first trigger in a session, read and cache rules from:

1. `obsidian/README.md`
2. `obsidian/reading/README.md`

Then reuse these rules for subsequent URLs in the same session.

## Re-read Triggers (force refresh)

Re-read both README files immediately when any of the following happens:

- User says rules changed / asks to follow latest README
- User asks to refresh rules (command: `refresh-rules` or equivalent)
- Target path leaves `obsidian/reading` subtree
- Execution finds ambiguity or conflict

## Per-URL Workflow

1. Parse URL and optional per-turn override.
2. Ensure current session has initialized rules (or refresh if triggered).
3. Canonicalize URL for storage and dedup (remove tracking/query noise while preserving article identity).
4. Resolve domain-based target folder under `obsidian/reading/` according to README.
5. Check duplicates by canonical URL in existing reading notes for that domain.
   - If duplicate exists: return existing file path and stop (no rewrite).
6. Resolve filename according to README naming rule.
7. Read article with Browser flow.
8. If page is login/paywall blocked or content cannot be reliably extracted, stop and report failure reason (do not fabricate content).
9. Build note structure and frontmatter according to README requirements.
10. Handle images when present: keep only valid resolvable image links; avoid broken placeholders.
11. Validate with DoD checklist.
12. Write file.
13. Return concise completion receipt.

## URL Canonicalization and Dedup Rules

- Remove common tracking parameters (for example: `utm_*`, `ref`, `source`, share/session tokens) unless required for article identity.
- Keep identity-critical path/ids (for example post/article IDs).
- Store canonical URL in note frontmatter.
- Use canonical URL for duplicate detection.

## Content Reliability Rules

- Do not output partial navigation-only captures as article content.
- If extraction quality is low/ambiguous, report uncertainty and stop.
- If blocked by login/subscription/captcha, report blocked status and stop.

## Language and Translation Policy

- Follow `reading/README` for required full-text retention and translation behavior.
- Detect primary language before drafting sections.
- Preserve original section structure during translation when possible.

## DoD Checklist (must report every turn)

- [ ] URL matches input
- [ ] Canonical URL computed and used for dedup
- [ ] Main content is complete (not nav-only partial)
- [ ] Frontmatter satisfies required fields from README
- [ ] Sections satisfy required structure from README
- [ ] Output path is correct under `obsidian/reading/...`
- [ ] Filename satisfies README naming rule

## Completion Receipt Format

Return only:

- `path: <final path>`
- `filename: <final filename>`
- `DoD: ✅/❌ per item`

## Override Rule

Keep defaults and cached rules unless user explicitly overrides for current URL.

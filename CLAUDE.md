# BOOT

> Delete this entire BOOT section once setup is complete. Its presence is the
> signal that this repo hasn't been set up yet — if you're reading this,
> run through the steps below before doing anything else.

1. Determine whether this is a brand-new project or an existing codebase
   adopting this template.
   - New project: ask the user what the project is, what it's for, and what
     stack/tech it will use (if not already decided).
   - Existing codebase: read the code first (package.json, README, folder
     layout, git log) to infer as much as possible. Only ask the user to
     confirm or fill gaps — don't re-ask what's derivable from the repo.
2. Seed the structural files:
   - `Working.md` — add "initial repo setup" as the current in-progress item.
   - `memory/MEMORY.md` plus a first memory file — record the project's
     purpose, stack, and constraints.
   - `decisions/DECISIONS.md` — log "Adopted claude-code-managed-repo-template"
     as the first entry (date, status: accepted, reason).
3. Once the stack is confirmed, suggest a set of stack-appropriate
   permissions to pre-allow in `.claude/settings.json` (e.g. npm/pip/cargo
   commands) and get the user's approval before adding them.
4. Ask whether this repo needs its own `.env` (secrets, SSH keys, API
   tokens, etc.). If yes, create `.env` and `.env.example`, and confirm
   `.env` stays in `.gitignore` (it's there by default — don't remove it).
5. Ask about any repo-specific conventions not already covered (commit
   style, branch strategy, deploy process). Skip anything the user says to
   leave as default.
6. Summarize what was recorded so the user can correct anything inferred
   wrong.
7. Delete this BOOT section from `CLAUDE.md` and note in `Working.md` that
   setup is complete.

---

# [Project Name]

This repo is managed with Claude Code using a structured memory system.
Read this file first in any session.

## Structure

- **`Working.md`** (root, always singular) — what's currently in progress.
  If something is tabled, shelved, or paused, remove it from here rather
  than marking it paused. Purpose: any session — fresh, resumed, or
  accidentally concurrent — can read this file and know the current state
  at a glance.

- **`memory/`** — indexed repo memory: project-specific documentation,
  architecture notes, and context that isn't derivable from the code
  itself. Memory *files* should be split into a section's own `memory/`
  by default whenever that makes sense for the section (monorepo package,
  self-contained subsystem, etc.) — root memory is for whatever is
  cross-cutting or doesn't belong to one section. The *index*,
  `memory/MEMORY.md`, defaults to a single copy at root regardless of how
  memory files are split, and only gets broken into per-section index
  files (each still linked from root) if the root index itself grows too
  long to navigate. Memory files and decisions may cross-reference other
  sections' indexes.

- **`decisions/DECISIONS.md`** — decision register. Every decision worth
  remembering gets an entry: **date**, **status** (proposed / accepted /
  rejected / superseded), **reason**. Same root-vs-section split logic as
  memory applies.

## Rules

- Before proposing or researching an approach, check the decision
  register — don't re-suggest something already tried and rejected
  without saying so. It's fine to resurface a rejected approach if you
  think the prior rejection may have been wrong or there's no viable
  alternative, but say explicitly that it was tried before and why you
  think it's worth revisiting.
- Update `Working.md`, memory, and the decision register as changes
  happen — err toward updating more often rather than batching. Any
  change worth documenting should be documented promptly.
- If you notice a significant discrepancy between the docs and the actual
  repo state, flag it and suggest a memory audit rather than silently
  patching over it or ignoring it.
- Destructive or hard-to-reverse actions still require explicit
  confirmation regardless of what's pre-allowed in `.claude/settings.json`.

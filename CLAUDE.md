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
   commands) and get the user's approval before adding them. Permission
   rules are scoped by *tool name*, not by shell — `Bash(git status *)`
   never matches a call made through the `PowerShell` tool, and vice
   versa. Check which shell tool this session actually uses (`Bash` on
   Mac/Linux, `PowerShell` on Windows unless Git Bash/WSL is in play) and
   add matching entries for that tool. If unsure, add both — a rule for
   a tool that's never invoked is harmless, but a missing one silently
   fails to gate anything, which is worse for the "ask" list than the
   "allow" list.
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
  sections' indexes. Within a section, individual files split by scope,
  not by size — see the memory file scope rule under Rules below.

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
- **Memory file scope rule**: a memory file's job is its one-line
  description in `MEMORY.md`. When new content stops matching that
  description, it belongs elsewhere — split on scope drift, not on line
  count. A large single-topic file is fine; a small multi-topic one
  isn't. Prefer moving drifted content into whichever *existing* file's
  description already covers it before creating a new one. A file passing
  roughly 250 lines is a reasonable prompt to check for drift, not an
  automatic split trigger. Compress resolved session-log narrative ("we
  tried X, it failed with Y, here's why") into a `DECISIONS.md` entry
  once the outcome is settled — memory files should hold what's still
  true/actionable now, plus a pointer to the decision for the "why," not
  a duplicate retelling. After any split, grep the repo for
  `[[wikilinks]]` and prose pointers into the moved content and update
  them — a split that leaves stale cross-references just relocates the
  staleness instead of fixing it.
- Destructive or hard-to-reverse actions still require explicit
  confirmation regardless of what's pre-allowed in `.claude/settings.json`.

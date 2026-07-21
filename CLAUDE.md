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
5. Before the first push, check `git config user.email` (local, falls
   back to global) against the repo's visibility (`gh repo view --json
   visibility`). If it's unset or resolves to an auto-detected address
   (git falls back to `<username>@<hostname>` when no identity is
   configured — a real, non-obvious failure mode, not hypothetical),
   set it explicitly with `git config user.email`: the GitHub noreply
   address (`<id>+<login>@users.noreply.github.com`, from
   `gh api user --jq '{id,login}'`) for **public** repos, since GitHub
   rejects pushes exposing an unverified/non-public real email (GH007);
   a real address is fine for **private** repos. Setting the config only
   affects *future* commits — if commits already exist with the wrong
   email, they need reapplying (cherry-pick each onto a reset branch
   tip, not interactive rebase) before they'll push.
6. Ask about any repo-specific conventions not already covered (commit
   style, branch strategy, deploy process). Skip anything the user says to
   leave as default.
7. Summarize what was recorded so the user can correct anything inferred
   wrong.
8. Delete this BOOT section from `CLAUDE.md` and note in `Working.md` that
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
  at a glance. When handing off mid-investigation (model switch, low
  context, end of session), record what's already been **ruled out** and
  the single **next concrete step** — not just the goal — so the next
  session continues the diagnosis instead of restarting it.

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
- Treat `git push` and any deploy as outward-facing actions needing
  explicit go-ahead **each time** — in repos wired to auto-deploy, a push
  *is* a deploy. Committing locally is fine; publishing is the gated step.
  When the user says to hold off pushing/deploying, that hold stands for
  the **rest of the session**, not just the one commit it was said about.

### If this project has a UI / front-end

- Verify visual changes against **actual rendered pixels** — screenshot
  the result, ideally at the viewport (and in the browser) the user
  actually uses, not just headless defaults or `getComputedStyle`
  numbers. A layout can measure as correct and still render wrong.
- If the user reports a visual problem that your measurements say is
  fine, **believe them** — you're measuring the wrong element or the
  wrong environment. Get an annotated screenshot or reproduce what they
  see; measure the exact thing they point at. Don't re-assert the numbers.
- **Set up a design-token layer early** as the single source of truth
  for styling — colours, type scale, spacing scale, radii, z-index, and
  key layout constants — using the stack's idiomatic mechanism (CSS
  custom properties, a theme object, Tailwind config, etc.). Name tokens
  **semantically by role** (e.g. `ink` / `paper` / `accent`, not raw
  hexes), so theming and dark mode re-point tokens in one place instead
  of touching every component. Components reference tokens, never magic
  numbers; genuine one-offs (a lone banner height, a hairline border)
  stay inline rather than pretending to be scale steps. A refactor that
  only tokenizes existing values should be **zero behaviour change** —
  preserve every computed value, and verify that (tests/snapshots green,
  rendered output identical).

### If this project has tests

- Keep both unit tests (logic) and integration/e2e tests (rendering +
  behaviour) **green before calling a change done** — run the suite,
  don't assume. Add or update tests alongside the change that needs them.
- For visual-regression baselines, only regenerate them **after
  confirming the new render is actually correct**. Never blind-update
  snapshots to turn red green — that silently blesses regressions.
- Encode design/behaviour invariants ("fits without scrolling", "no
  overflow", "stays centred") as guardrail tests where you can, so they
  fail loudly instead of being caught by eye later.

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

- **`Working.md`** (root) — what's currently in progress. If something is
  tabled, shelved, or paused, remove it from here rather than marking it
  paused. Purpose: any session — fresh, resumed, or accidentally
  concurrent — can read this file and know the current state at a glance.
  When handing off mid-investigation (model switch, low context, end of
  session), record what's already been **ruled out** and the single
  **next concrete step** — not just the goal — so the next session
  continues the diagnosis instead of restarting it.
  **Archive-cadence rule:** don't wait for a fixed weekly clock. Archive a
  `##` section into a new `Working_archive-<week-start-date>.md` (reuse
  the current week's archive file if one already exists, otherwise start a
  new one) as soon as **either** (a) that section's own text reports
  itself finished — done/merged/deployed/verified, nothing gated on a
  human or another stream (small deferred fast-follow items don't count;
  carry those forward as a short bullet instead) — or (b) the file exceeds
  roughly 400 lines of currently-in-progress material, whichever comes
  first. Move whole sections wholesale, never summarize or delete; leave a
  one-line pointer in `Working.md`. These archives double as a project
  roadmap/history, so preserve full detail, don't compress it.

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
  memory applies. **Entry-length rule:** a `Decision`/`Reason` cell running
  past roughly 300 words combined gets trimmed at write time to a summary
  + a pointer into the relevant `memory/*.md` file, rather than left as
  one giant paragraph.

- **`handoffs/`** (optional, opt-in) — independent-execution dispatch
  system for repos with parallelizable, independent work streams. Not
  part of default setup; adopt it when a project outgrows single-threaded
  work (multiple independent streams that could run concurrently without
  colliding). See `handoffs/TEMPLATE.md` and `.claude/agents/executor.md`
  for the mechanics: an orchestrator session writes a self-contained
  handoff doc per stream, `handoffs/INDEX.md` tracks dispatch status/deps/
  touched-surface conflicts, and `executor` subagents (worktree-isolated
  for parallel work) run each stream independently and report back in a
  structured shape. Delete `handoffs/` entirely if a project never needs
  it — its presence isn't a signal the repo requires it. Pairs with the
  `## Parallel work` section below once a project has genuinely
  concurrent streams, not just sequential handoffs.

- **`integrations/`** (optional, opt-in) — self-contained add-on modules a
  project can adopt piecemeal. Each lives in its own subdirectory with its
  own `README.md` covering what it does, how to wire it in, and how to
  remove it cleanly — not part of default BOOT setup. A project that
  doesn't need a given integration just deletes its subdirectory; nothing
  else references it. See `integrations/telegram-relay/README.md` for the
  one shipped with this template (Telegram notifications + remote
  permission-approval for Claude Code sessions).

## Secrets

Two different problems, two different mechanisms — don't reach for one
where the other actually fits:

- **A secret only this machine/session needs, never committed**: a
  gitignored `.env` (see BOOT step 4). Simple, no extra tooling, fine for
  the common case.
- **A secret that needs to be shared across machines, needs to survive a
  single machine's loss, or is worth committing for audit/history** (a
  credential a *remote* environment also needs, anything you'd otherwise
  be copy-pasting into a password manager and a local `.env` in parallel):
  encrypt it at rest and commit the encrypted file rather than keeping it
  local-only. [SOPS](https://github.com/getsops/sops) plus an age key is a
  concrete, low-ceremony mechanism for this: `*.enc.yaml` files are safe
  to commit, one `.sops.yaml` declares what gets encrypted — prefer
  encrypt-by-default (an `unencrypted_regex` allow-list of what stays
  plain) over the inverse, since an allow-list-of-what-to-encrypt silently
  misses a new field the day someone forgets to add it — and the actual
  age private key lives *outside* the repo entirely (password manager,
  one machine's local keyring), never committed itself.
- **Pair either mechanism with a registry, not just the raw files.** One
  file recording *names, owners, rotation dates* — never values — so a
  session (or a human) can read what credentials exist and when they last
  rotated without ever touching a value. A credential's registry row
  should say plainly where its real value lives (which `.enc.yaml`, which
  password-manager entry) rather than duplicating it.
- **A write-capable credential's "a human must be present" requirement
  doesn't always need its own storage/passphrase ceremony.** If every
  mutating command in the session already needs interactive approval
  before it runs, that approval step *is* the gate — pair it with a
  standing rule to always state plainly what a mutation will do before
  running it, rather than building mint-per-task or passphrase-vault
  machinery on top of a gate that already exists. Reach for real
  credential separation only when the interactive-approval assumption
  itself doesn't hold (a fully autonomous/unattended run, a credential
  several people share).
- **Treat any accidental exposure as a real compromise, not a near-miss.**
  A secret printed to a transcript, logged, or echoed in a command's own
  argv is exposed the moment it's visible, whether or not anyone actually
  reads it back. Rotate the credential immediately — don't just
  re-encrypt or hide the same value — and clean up whatever local
  artifacts hold the plaintext. **A command's own arguments are not a
  safe place to narrate from if a secret is among them**: printing "here's
  the exact command about to run" for transparency is good practice right
  up until that command's argv contains a credential. An encoding
  (base64, JSON, a rendered template) is not encryption and does not make
  this safe — it's trivially reversible by anyone who reads it. Narrate
  *intent* instead ("about to join this host to the network using a fresh
  key"), never the literal invocation, whenever a secret could be sitting
  in it.

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
- **When an instruction is ambiguous partway through a long, multi-thread
  session, survey the full set of currently open items before asking a
  clarifying question** — not just whatever was most recently discussed.
  Recency bias makes the last topic feel like "the" open item and crowds
  out others that are equally live; a clarifying question built around
  only the most recent thread can miss the actual referent entirely,
  costing a wasted round-trip. Likewise, when stating a fact about
  something that exists at multiple layers (a host and its guests, a
  service and its dependency), name the layer explicitly on first
  mention — an unqualified claim about one layer reads as ignorance of
  the other, even when it's narrowly correct.
- **A file's own top-of-file status banner is the highest-visibility claim
  in it — keep it in sync with reality as work lands**, don't let it go
  stale while a detailed table or checklist further down the same file
  stays accurately maintained. A reader (human or a future session) skims
  the banner first and often only the banner; a banner claiming "nothing
  built yet" beside a body that's mostly done is actively misleading,
  worse than no banner at all.
- **Verify the verification.** Before reporting an all-clear ("tests pass",
  "the fix works", "nothing's broken"), confirm the check you ran could
  actually have detected the problem in question — a green result from a
  check that never exercised the failing path is not evidence of anything.
  This has bitten real projects: a "confirmed healthy" health check that
  read the wrong signal, a passing test suite that never touched the
  changed code path. State what was actually verified and how, not just
  the outcome.

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

## Parallel work (worktrees + stream registry) — optional, pairs with `handoffs/`

Only relevant once a project has genuinely parallel, independent work
streams — multiple orchestrator sessions, or an orchestrator plus
subagents, touching the repo at once. A single-threaded project doesn't
need this; `handoffs/` alone covers sequential dispatch. Folded into this
template from a downstream project's real scaling pain — a real incident
where an unscoped `git add -A` in the shared checkout swept another
session's in-progress work into an unrelated commit — the rules below
exist specifically to stop that class of collision, not as speculative
process:

- **One worktree per stream — created by hand by the orchestrator, never
  via the Agent tool's own `isolation` param.** The primary checkout (on
  the default branch) is the **integration tree**; it only reviews and
  merges. Every parallel stream works in its **own** worktree on its own
  branch, created by the orchestrator BEFORE dispatch:
  `git worktree add ../<repo>-<stream> -b stream/<name>`, then the
  executor's dispatch prompt states that absolute sibling path as where to
  work. A stream commits only to its own branch; the integrator merges it
  to the default branch, so that branch moves through one reviewed door.
  Never `git add -A` in the primary tree without checking whose changes
  are actually staged.
  **Do not pass `isolation: "worktree"` to the Agent tool without first
  confirming it actually works in your environment** — confirmed to fail
  100% of the time on at least one real Windows setup this rule was
  written against. Use the sibling-worktree convention above unless you've
  specifically verified the harness's own isolation works for you, and
  record whichever way it goes (with the exact error text, if it fails) in
  an `environment-truths.md`-style memory file so it isn't re-discovered
  the expensive way twice.
  **Commit before you dispatch.** A worktree branches from a *commit*, not
  the orchestrator's working tree — a freshly written, uncommitted handoff
  (or any doc it depends on) is invisible to the executor meant to run it.
  This is structural, not bad luck: it recurs every time it's skipped.
  Commit to the default branch first, *then* `git worktree add`. If a
  stream's worktree already existed and the default branch has moved on,
  rebase it before resuming.
  **Cleanup gotcha (seen on Windows):** once a stream's branch is merged,
  removing its worktree can fail with a permission error even though the
  worktree is otherwise done — a lingering handle from a just-finished
  subagent process, or antivirus scanning the directory right after its
  last write, can hold a lock for a few seconds. It's transient: retry
  once, or fall back to a plain directory removal (the directory is
  already empty of tracked content at that point, distinct from a
  recursive force-delete of something still in use). Then prune the
  worktree from git's own registry.
- **The orchestrator owns the live stream registry outright — executors
  never touch it, even to "claim" or "release" their own row.** Call it
  `ACTIVE.md` in the primary worktree, and **gitignore it** — it's
  machine-local coordination state, not project history. Only the
  orchestrator reads and writes it: add/update a stream's row (stream ·
  worktree/branch · owner+date · touched surfaces · status) **before**
  dispatching, and update/release it once the executor reports back.
  Executors report status in their structured report only — a
  worktree-isolated executor reaching *outside its own worktree* to
  hand-edit a file that only exists in the primary tree defeats the
  isolation the worktree exists to provide. This is what enforces a
  serialized-chokepoint rule (name any shared, hard-to-merge surface
  explicitly — "at most one active stream on this surface at a time")
  *across* independent sessions, not just within one. If a surface you
  need is already claimed, coordinate rather than double-touch it.
  **Keep it small** — give it the same archive-cadence discipline as
  `Working.md`; an always-injected coordination file that grows unbounded
  is one of the more expensive doc-bloat mistakes a project's own tooling
  can make.
- **Executors do not reliably commit incrementally, and instructing them
  does not fix it on its own.** Even with the commit-discipline rule in
  `.claude/agents/executor.md`, real streams have lost hundreds of lines of
  work because an executor was terminated mid-run — an API error, a
  session limit, a timeout — before it got around to committing. What
  actually closed the gap was not another instruction but a `Monitor` loop
  armed at dispatch time that commits anything uncommitted on a short
  interval (a few minutes): it no-ops when the agent behaves, and caps
  worst-case loss at that interval regardless. Consider arming one at
  every worktree dispatch rather than relying on the agent remembering to
  commit — the rule already existing in `executor.md` and still not being
  followed consistently is itself the evidence that a second, independent
  safety net earns its keep here.

See `.claude/agents/executor.md` for the executor contract these rules
assume, and `.claude/agents/researcher.md` for the read-only counterpart
used for investigation that feeds a decision or a handoff rather than
building one.

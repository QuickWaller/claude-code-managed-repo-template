# Working

What's currently in progress. Remove an item once it's done, tabled, or
shelved — don't mark it paused, just take it out. The point of this file
is that any session (fresh, resumed, or accidentally concurrent) can read
it and know what's actually going on right now.

## 2026-08-18 — process learnings ported forward + telegram-relay module added

Two batches of work, both done directly in this repo (not a new BOOT run —
this repo stays a generic template; a real, optional module was added to
it, and the template's own core conventions were brought forward):

1. **Folded a second round of real-world process learnings back into
   `CLAUDE.md`** from a downstream project's continued development, on top
   of the first port from 2026-07-30: a `## Parallel work (worktrees +
   stream registry)` section (opt-in, pairs with `handoffs/`), a sharpened
   dual-condition `Working.md` archive-cadence rule, a decisions
   entry-length trim rule, a `verify-the-verification` Rules bullet, a new
   `.claude/agents/researcher.md` (paired with the existing `executor.md`),
   and commit-discipline / no-background-wait rules added to `executor.md`.
   All identifying specifics (project name, business/tenant details, real
   incident IDs) were deliberately generalized out before writing — see
   `decisions/DECISIONS.md`'s 2026-08-18 rows.
2. **Added `integrations/telegram-relay/`** — an opt-in module (Telegram
   notifications, an inbound instruction channel, dual-channel local-popup/
   Telegram permission approval), ported and generalized from the same
   downstream project, with a `README.md` crediting three existing public
   projects compared during design (`RichardAtCT/claude-code-telegram`,
   `JessyTsui/Claude-Code-Remote`, `kcisoul/remotecode`). Set the whole
   repo's license to MIT (root `LICENSE`) as part of this — this is a
   generic, shareable template; the downstream project this content
   originated from stays under its own, different license/visibility.
   A real, named gap this module doesn't yet close — injecting a fresh
   instruction into an idle session, which the compared projects solve via
   tmux (Linux/Mac) or AppleScript (Mac), neither available natively on
   Windows — is scoped as `handoffs/windows-command-injection.md`, not
   dispatched.

**Verification status**: `integrations/telegram-relay/tests/remote-approval.tests.ps1`
ported with only cosmetic path/text changes to the header and one test
payload's fake `cwd` value — functions are byte-identical to the version
that was passing ~70 assertions in its origin repo. Re-run it here before
relying on it (not yet re-run in this location as of this entry).

**Known pre-existing issue, flagged not fixed**: this repo's git history
(from the 2026-07-30 port, predating this session) already contains one
literal mention of the downstream project's name in a commit message and
in `decisions/DECISIONS.md`'s prior text (now generalized in the current
file content). Removing it from history would need a force-push rewrite —
not done without explicit confirmation, since this repo is public.

**Not yet done**: `git commit` + `git push` for this session's changes —
holding per this repo's own CLAUDE.md rule ("treat push as outward-facing,
needs explicit go-ahead each time").

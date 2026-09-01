# Working

What's currently in progress. Remove an item once it's done, tabled, or
shelved — don't mark it paused, just take it out. The point of this file
is that any session (fresh, resumed, or accidentally concurrent) can read
it and know what's actually going on right now.

## 2026-09-01 — third round of process learnings ported forward

Same pattern as the 2026-07-30 and 2026-08-18 ports (see
`decisions/DECISIONS.md`), from the same downstream project's continued
development:

1. **New `## Secrets` section in `CLAUDE.md`** — when a gitignored `.env`
   is enough vs. when to encrypt-and-commit instead (SOPS + age key
   named as the concrete mechanism), pairing either with a
   names/owners/rotation-dates-only registry, a note that a write-capable
   credential's "human must be present" requirement can be satisfied by
   an already-interactive approval flow rather than needing its own
   ceremony, and a rule that any accidental exposure — including a secret
   printed via a command's own echoed arguments, encoded or not — is a
   real compromise requiring rotation, not just a close call.
2. **Two new `## Rules` bullets** — survey the full set of currently open
   items before asking a clarifying question in a long multi-thread
   session, rather than anchoring on whichever thread was most recently
   discussed; keep a file's own top-of-file status banner in sync with
   reality as work lands, since it's the highest-visibility claim in the
   file and a reader often trusts it without reading further.

All identifying specifics (project domain, real infrastructure names, the
specific incident's exact commands) deliberately generalized out before
writing — see `decisions/DECISIONS.md`'s 2026-09-01 row.

**Not yet done**: `git commit` + `git push` for this session's changes —
holding per this repo's own `CLAUDE.md` rule ("treat push as
outward-facing, needs explicit go-ahead each time").

# Handoff dispatch index

Single source of truth for independent-execution streams. An orchestrator
session writes handoffs (`handoffs/<slug>.md` from `TEMPLATE.md`) and keeps
this table current; `executor` subagents (or interactive sessions for gated
work) run them. See `.claude/agents/executor.md` for the rules every
executor follows.

## How dispatch works
- **Automated (parallel):** orchestrator calls
  `Agent(subagent_type="executor", model="sonnet", isolation="worktree",
  prompt="Execute handoffs/<slug>.md")`. Worktree isolation keeps parallel
  streams from colliding on files. Executor reports back; orchestrator
  integrates + reviews.
- **Interactive (gated work):** the user opens a session and says "execute
  handoffs/<slug>.md" — required whenever the handoff's core is a gated op
  (destructive infra change, DB wipe, live prod mutation), since subagents
  can't prompt mid-run.

## Sizing & token economy (important) — a crossover, not "always warm"
There are TWO opposing costs; size streams to sit between them:
- **Lower bound — don't cold-spawn per micro-task.** A cold start re-pays the
  doc-load. Batch small related steps into ONE stream so a single executor
  does them all before reporting.
- **Upper bound — don't operate bloated.** A warm agent re-processes its whole
  context every turn; once it's ~30%+ full, that recurring per-turn cost
  exceeds a fresh start's one-time load (and quality degrades / compaction
  looms). A stream *ends* — the executor reports and **terminates**; the next
  unrelated stream starts fresh. Split any stream too big for a lean window
  into **sequential handoffs**, not one long warm agent.
- **Sweet spot: warm WITHIN a coherent stream, fresh BETWEEN streams.** Resume
  (`SendMessage`) only for a tightly-coupled, *soon* follow-up; otherwise let
  the executor die and cold-start the next.
- **Handoffs front-load facts** so even a cold start reads the handoff (small),
  not the full memory/decisions corpus. Keep "Current state & IDs" distilled
  to the stream.

## Rules that govern the table
- **Chokepoints:** if two streams touch the same shared, hard-to-merge
  surface (a single service's core module, a shared migration, a live
  resource only one process should mutate at a time), at most ONE such
  stream may be `running` at a time — name the chokepoint explicitly in
  both streams' rows. Everything else can run in parallel.
- **Deps:** a stream may start only when every `Depends on` is `done`.
- **Every completed stream** flips its own row here + updates `Working.md`/
  `decisions/DECISIONS.md`.

## Streams
| Stream (handoff) | Status | Mode | Touches | Depends on | Notes |
|---|---|---|---|---|---|
| _example — delete once real streams exist_ | ⬜ blocked | subagent | — | — | — |

<!-- Add new streams as rows; copy TEMPLATE.md for the handoff doc. -->

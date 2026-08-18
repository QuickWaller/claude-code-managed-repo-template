# Handoff: <one-line goal>

<!--
Copy this file to handoffs/<short-slug>.md, fill every section, then add a row
to handoffs/INDEX.md. A cold executor must be able to run this with NO other
context. Restate load-bearing rules HERE — don't just link them (rules near
the top get followed; rules buried in a linked doc get skipped).
Size to ~one warm session of related work (batch small steps into the stream),
and keep "Current state & IDs" distilled to what THIS stream needs — the
executor reads this, not the full memory/decisions corpus.
Dispatch (orchestrator): Agent(subagent_type="executor", model="sonnet",
isolation="worktree" for parallel/code work, prompt="Execute handoffs/<slug>.md").
-->

## Goal & done-when
- **Goal:** <what "finished" looks like in one sentence.>
- **Acceptance criteria:** <bullet the concrete, checkable outcomes.>

## Autonomy boundary  ← read first
- **Autonomous:** <what the executor may just do.>
- **STOP-and-hand-back:** <the gated ops it must NOT run itself — anything
  destructive, hard to reverse, or affecting shared/live/production state.
  Say exactly where to stop.>
- **Mode:** subagent (worktree) | interactive session (required if this
  handoff's core IS a gated op).

## Touched surfaces & dependencies
- **Touches:** <files/systems this stream will change. Used to decide what
  can run in parallel.>
- **Depends on:** <handoff slugs that must be `done` first, or "none".>
- **Conflicts with:** <handoffs that must not run concurrently — name any
  shared chokepoint surface explicitly.>

## Current state & IDs (re-derivable — the whole point)
- <IDs, hostnames, credential locations, live resource IDs the executor
  needs. Point to the relevant `memory/*.md` file for the durable set;
  restate the few this task actually uses.>

## Gotchas
- <the traps a cold session would hit — non-obvious constraints, known
  flaky steps, permission gates that will block mid-run.>

## Steps
1. <ordered, each with its own check.>

## On completion (mandatory)
- Update `Working.md`, add a `decisions/DECISIONS.md` row if a decision was
  made, correct any stale doc you relied on, flip this row in `INDEX.md`, and
  report in the executor's structured shape.

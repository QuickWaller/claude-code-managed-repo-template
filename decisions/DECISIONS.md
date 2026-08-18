# Decision Register

Log every decision worth remembering here: **date**, **status**, **reason**.

Before proposing or researching an approach, check this register first —
don't re-suggest something already tried and rejected without saying so.
It's fine to resurface a rejected approach if the prior rejection may have
been wrong or there's no viable alternative, but say explicitly that it
was tried before and why it's worth revisiting.

| Date | Decision | Status | Reason |
|------|----------|--------|--------|
| 2026-07-30 | Ported 3 conventions from a downstream consumer of this template: `Working.md` weekly-archive splitting, a generic destructive-command `ask` list in `.claude/settings.json`, and an opt-in `handoffs/` orchestrator/executor dispatch system | accepted | The downstream project hit real scaling pain this template didn't yet handle (a 1400+-line `Working.md`, no permission-level guard on destructive git commands, no pattern for parallelizable independent work streams); generalized the fixes back into the template so future projects start with them. `handoffs/` is opt-in scaffolding, not part of default BOOT setup. |

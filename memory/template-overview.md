---
name: template-overview
description: What this repo's structure is, why it exists, and where it came from
metadata:
  type: overview
---

This repo follows the structure defined in
`QuickWaller/claude-code-managed-repo-template`: a root `CLAUDE.md` (with a
one-time BOOT section that deletes itself once setup is done), a single
root `Working.md` for in-progress state, an indexed `memory/` directory for
project documentation, and a `decisions/DECISIONS.md` decision register
with date/status/reason metadata on every entry.

**Why it exists:** re-explaining the same repo conventions — what goes
where, when to update docs, how to avoid re-litigating rejected
approaches — to fresh or resumed Claude Code sessions was getting
repetitive across projects. This template centralizes those conventions
once so every project built with Claude Code starts from the same
baseline instead of reinventing it each time.

**Where it came from:** designed collaboratively with Claude Code and
first applied to `recipe-website-v2` as the initial test case.

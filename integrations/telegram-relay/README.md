<!-- markdownlint-disable MD041 -->
# telegram-relay

An opt-in module: Telegram notifications, an inbound instruction channel,
and dual-channel (local popup + Telegram) permission approval for Claude
Code sessions. Built for, and proven live in, a real production project;
generalized into this template.

Delete this whole directory if you don't want it — nothing outside
`integrations/telegram-relay/` depends on it.

## What's in here

| File | What it does |
|---|---|
| `notify-telegram.ps1` | Pings you on Telegram when a session needs attention (a permission prompt, an idle wait) or when Claude explicitly announces it's done/blocked/progressing. Notify-only — cannot answer anything. |
| `remote-approval.ps1` | Answers a `PermissionRequest` hook from either a local WinForms popup on the machine or Telegram, whichever you answer first. Fails closed on every error path. |
| `telegram-inbound-poll.ps1` | One poll of the bot's inbox; prints new messages from you to stdout so a monitor loop can surface them to the model as input to consider. |
| `lib/notify-common.ps1` | Shared truncation + credential-read helpers, dot-sourced by the two scripts above. |
| `tests/remote-approval.tests.ps1` | ~70 assertions: pure-function unit tests, a real subprocess harness against an isolated fake home directory, and one real (clearly-labelled) live Telegram round-trip. |

## Why this exists (the honest version)

Claude Code sessions run unattended for long stretches — dispatched
background work, permission prompts that can sit for minutes, idle waits
that only resolve when a human comes back. Without a channel out, all of
that is invisible until you happen to check the terminal. This module is
the fix: a Telegram bot as a second surface for "something needs you" and,
optionally, a way to answer from your phone instead of waiting until you're
back at the keyboard.

Three mechanical designs for "when is a session actually finished, not just
between turns" were tried and two were rejected before the current one —
see `notify-telegram.ps1`'s own header for the full "why finished is not a
hook" account. The short version: no hook-visible signal reliably
distinguishes "waiting on you" from "waiting on a background subagent" —
that's a judgement about the state of the work, and only the model holds
it. So `-Announce` is a deliberate act, not an inference, with the
mechanical `Notification` hooks as a partial backstop for the cases a hook
*can* see (an actual blocking prompt).

## Setup

1. Get a Telegram bot token from [@BotFather](https://t.me/BotFather) and
   your own numeric chat id (message the bot once, then read
   `https://api.telegram.org/bot<token>/getUpdates`).
2. Create `~/.claude/notify.env` (NOT this repo's `.env` — this is
   cross-project, user-level, and deliberately outside any repo):
   ```
   DEV_RELAY_BOT_TOKEN=<your bot token>
   DEV_RELAY_CHAT_ID=<your chat id>
   ```
3. Wire `notify-telegram.ps1` into `~/.claude/settings.json`'s `Notification`
   hook (matcher `permission_prompt|idle_prompt|agent_needs_input`), pointed
   at this file's absolute path. If you want cross-project reach, this is a
   user-level hook, not a repo-level one — see the tradeoff this implies in
   the script's own header (moving/renaming this repo breaks the hardcoded
   path in every project until fixed).
4. Optionally wire `remote-approval.ps1` into the `PermissionRequest` hook
   the same way, and toggle it on/off with:
   ```
   powershell -File notify-telegram.ps1 -Afk on
   powershell -File notify-telegram.ps1 -Afk off
   ```
5. Have Claude call `notify-telegram.ps1 -Announce -Message "..." -Mode Done|Progress|Blocked`
   when it genuinely wants you back — this is the deliberate-act backstop
   described above, not automatic.
6. For the inbound channel, run `telegram-inbound-poll.ps1` on a loop (e.g.
   a ~30s interval via whatever your harness's own background/monitor
   mechanism is) and treat its stdout lines as input the model should
   consider, never as auto-executed instructions.

Run `tests/remote-approval.tests.ps1` after any change — section 3 sends
one real, clearly-labelled Telegram message if real credentials are
present; it's harmless but expected.

## Design note: presence-gated vs. dual-race approval

`remote-approval.ps1` supports two shapes, and it's worth picking
deliberately rather than defaulting:

- **Presence-gated** (`Invoke-RemoteApproval`): AFK off → the plain native
  prompt, zero Telegram contact, zero behavior change. AFK on → Telegram
  only. One channel at a time, chosen by a toggle you have to remember to
  flip.
- **Dual-race** (`Invoke-DualApproval`, the current entry point): AFK on →
  a local popup AND Telegram poll concurrently, whichever answers first
  wins. Never need to remember whether you're "away" — but it costs you
  the terminal's own diff/output view on **every** prompt while the toggle
  is on, not just while you're actually away, since the decision is made
  from a plain-text summary (tool name + truncated raw args) rather than
  the real rendered diff.

Neither is more "correct" — it's a real tradeoff between convenience and
context-at-decision-time. Pick based on how often you're actually deciding
away from the keyboard versus how much you rely on seeing the real diff.

## Credits

This module's design was sharpened by comparing three existing public
projects that solve an adjacent problem — remote/Telegram control of
Claude Code — before building further on the design already in progress
here:

- **[RichardAtCT/claude-code-telegram](https://github.com/RichardAtCT/claude-code-telegram)**
  (MIT) — a Telegram bot that drives Claude Code as a service via its SDK
  (agentic + classic modes, webhooks, cron, SQLite session persistence).
  Architecturally different from this module (it *owns* sessions rather
  than riding along with one you're already running interactively), but
  useful as a reference for what a fuller hosted-bot architecture looks
  like.
- **[JessyTsui/Claude-Code-Remote](https://github.com/JessyTsui/Claude-Code-Remote)**
  (MIT) — multi-channel (email/Telegram/LINE/desktop) remote control that
  hooks into a real interactive session and injects replies back in via
  **tmux `send-keys` or macOS AppleScript keystroke automation**, including
  screen-scraping the terminal to auto-answer confirmation dialogs. This is
  the piece this module doesn't yet have: injecting a *fresh* instruction
  into an *idle* session, not just answering a pending prompt. Its
  mechanism doesn't port directly to Windows (no tmux, no AppleScript) —
  see `../../handoffs/windows-command-injection.md` for that gap scoped as
  its own follow-up, crediting the approach here.
- **[kcisoul/remotecode](https://github.com/kcisoul/remotecode)** (site
  states MIT) — closest in spirit to this module: "Session Takeover" (open
  Telegram, see what a stuck session needs, keep it going) and a
  "Cross-Session Scanner" (get notified across multiple sessions, not just
  the one you're looking at) name almost exactly what `remote-approval.ps1`
  and `notify-telegram.ps1` already do here, arrived at independently.

None of this module's code is copied from those projects — the approaches
differ (this module answers a live hook's structured `PermissionRequest`
directly rather than screen-scraping a terminal), but the comparison
directly shaped the design and is credited here rather than left
unacknowledged.

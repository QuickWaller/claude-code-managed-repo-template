# Handoff: Windows-native command injection into an idle Claude Code session

<!--
Copy this file's shape from TEMPLATE.md if reused elsewhere. This one is
pre-written as a scoping document, not yet dispatched — see "Status" below.
-->

## Status: NOT DISPATCHED — scoping only

Written to capture a real, named gap rather than let it evaporate. No code
exists yet. Pick this up as its own stream when the underlying need
(genuinely starting/steering a session from a phone, not just answering a
pending permission prompt) becomes real enough to justify the build.

## Goal & done-when
- **Goal:** from Telegram (or another remote channel), send a brand-new
  instruction that actually reaches a Claude Code session waiting idle at
  its prompt — not just a reply to something already pending — on a native
  Windows desktop, without tmux or WSL's general Linux userland (neither is
  reliably available; `integrations/telegram-relay/README.md`'s Credits
  section explains why the existing prior art doesn't port directly).
- **Acceptance criteria:**
  1. A message sent to the relay bot while no permission prompt is pending
     is typed into a real, currently-idle Claude Code terminal/window and
     submitted, without the operator touching the keyboard.
  2. Fails safely if no idle session can be found or the target window
     can't be identified — never types into the wrong window.
  3. Live-verified by actually watching it happen on a real desktop, not
     reasoned about from code alone (this class of bug — "looks correct,
     silently isn't" — has bitten adjacent WinForms/UI code in this
     template's own history; see `.claude/agents/executor.md`'s commit-
     discipline note for the general pattern of real streams losing work
     to unverified assumptions).

## Prior art (credited, not ported)
- `JessyTsui/Claude-Code-Remote`'s `tmux-injector.js`: `tmux send-keys` to
  type into a captured pane, plus `tmux capture-pane` + string-matching on
  the CLI's own TUI output (`"Do you want to proceed?"`, `(y/n)`, etc.) to
  auto-answer confirmation dialogs it can't otherwise see.
- The same project's `smart-injector.js`: macOS-only, `osascript`/
  `System Events` keystroke injection plus clipboard-paste fallbacks.
- `kcisoul/remotecode`'s "Session Takeover" feature does this on whatever
  its own (unread, at scoping time) internals are — worth reading before
  starting this stream, since it may already have solved the Windows case.

Neither of JessyTsui's two mechanisms is Windows-portable as-is: no tmux by
default, and AppleScript is macOS-only. A Windows-native build means
simulating keystrokes into the real terminal window via Win32 SendInput or
UI Automation — a genuinely different implementation, not a port.

## Autonomy boundary
- **STOP-and-hand-back for ALL live verification.** Injecting synthetic
  keystrokes into a real, currently-in-use desktop session is not something
  to test unattended — a bug here means keystrokes land in the wrong
  window, on the wrong session, possibly mid-conversation. Build and
  reason about the mechanism autonomously; every live test needs a human
  physically watching the screen.
- **Mode:** interactive session with the user present once implementation
  starts. Not a worktree executor task for the live-verification steps.

## Touched surfaces & dependencies
- **Touches:** a new script in `integrations/telegram-relay/` (e.g.
  `windows-inject.ps1`), `telegram-inbound-poll.ps1`'s consumer loop (to
  wire the new instruction path in), this module's `README.md`.
- **Depends on:** none — `integrations/telegram-relay/` as it stands today
  works fully without this.
- **Conflicts with:** none currently.

## Gotchas
- **Which window is "the idle session"?** Multiple Claude Code
  windows/terminals can be open at once. A real design needs a way to
  identify the intended target unambiguously (window title convention,
  a marker file per session, focus-tracking) before typing into anything —
  guessing wrong is the failure mode acceptance criterion 2 exists to catch.
- **Keystroke injection can race real human typing.** If the operator is
  mid-sentence in a *different* window when an injected message fires, the
  result is corrupted input in whatever has focus. The mechanism needs to
  either force focus deliberately and visibly (so a human sees it happen)
  or refuse to inject if it can't be sure nothing else has focus.
- **This is a genuinely different trust boundary from the existing
  approval/notify scripts** — those only ever answer yes/no to something
  Claude itself already proposed. This types arbitrary text as a fresh
  instruction. Revisit `telegram-inbound-poll.ps1`'s existing "surfaced as
  input to consider, never auto-executed" boundary explicitly before
  building this — it may need to stay that way even after this ships (i.e.,
  the injected text still goes through the model's own judgement rather
  than being blindly submitted), or the decision to change that needs to
  be made deliberately, not by default.

## Steps
1. Read `kcisoul/remotecode`'s actual source for its "Session Takeover"
   mechanism — it may already have solved the Windows case; don't rebuild
   blind if so.
2. Design the window-identification scheme (see Gotchas) and get it
   reviewed before writing injection code.
3. Prototype Win32 SendInput or UI Automation keystroke injection against a
   throwaway test window first — prove the mechanism works before pointing
   it at a real Claude Code session.
4. Wire into `telegram-inbound-poll.ps1`'s consumer loop, gated behind an
   explicit opt-in toggle (mirroring `afk.state`'s pattern) — default OFF.
5. Live-verify with the user present (see Autonomy boundary).
6. Update this module's `README.md`, add a `decisions/DECISIONS.md` row,
   flip this handoff's status.

## On completion (mandatory)
- Update `Working.md`, add a `decisions/DECISIONS.md` row, correct any
  stale fact relied on here, and update `integrations/telegram-relay/README.md`.

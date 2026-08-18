<#
  notify-telegram.ps1 — pings the operator on Telegram when Claude Code needs
  attention, and when a session has genuinely gone idle.

  Origin: built after a production incident ran for roughly 30 minutes with
  zero notification to anyone, which made the general point that "something
  needs a human" had no channel at all — not for the live system, and not
  for Claude Code itself. See ../README.md for the full backstory and credits.

  This is the NOTIFY-ONLY layer. It deliberately cannot answer anything.
  Remote approval (answering a permission prompt from Telegram) is
  remote-approval.ps1, a separate script in this same module.

  SCOPE: if wired via the USER-level ~/.claude/settings.json (see
  ../README.md), this fires in EVERY project on the machine, not just one.
  The script deliberately lives in a version-controlled repo rather than in
  a loose ~/.claude/hooks/ directory so it stays tracked, diffable, and
  backed up. The cost of that choice: ~/.claude/settings.json then hardcodes
  this repo's absolute path, so moving or renaming the repo breaks the hook
  in every project until the path is fixed.

  Credentials live in ~/.claude/notify.env (NOT this repo's .env) because the
  bot is cross-project.

  ACTUAL live wiring is whatever your own ~/.claude/settings.json says —
  read that, don't trust a comment here, if you need to re-verify what's
  actually hooked up. As shipped, this script expects:
    Notification -> the event this is designed around, matcher
                    "permission_prompt|idle_prompt|agent_needs_input"
    Stop / UserPromptSubmit -> handled below (counter bump only, sends
                    nothing) but NOT necessarily wired to this script in
                    your settings.json — wire them only if you want that
                    behavior. The switch cases are harmless no-ops if left
                    unwired, and are kept as the seed of a future
                    subagent-aware debounce (see "Why finished is not a
                    hook" below) if your harness exposes
                    SubagentStart/SubagentStop/TeammateIdle-style events.

  ## Why "finished" is NOT a hook — two rejected designs, and the reason

  The operator wants one thing from this: *when is it worth coming back?*
  Two mechanical attempts at that were built and both were wrong.

  **v1 — Stop, if the turn ran over 2 minutes.** Fired on EVERY long turn
  whether or not anyone had walked away. Once background subagent streams
  made multi-minute turns routine, it was mostly noise.

  **v2 — Stop, debounced by a fixed window of total session silence.**
  Rejected before shipping: silence is not completion. A dispatched
  background stream can run for half an hour while the session sits
  perfectly quiet, so the debounce would confidently say "come back" in the
  middle of the work. Same false signal, better disguise.

  **The actual reason both failed:** Stop means "this turn's output ended",
  which is not remotely the same as "the work is done". With background
  agents, Claude yields the turn constantly and is re-invoked as each stream
  reports. No mechanical signal available to a hook distinguishes "waiting
  on you" from "waiting on a subagent" — that is a judgement about the state
  of the work, and only the model holds it.

  **v3 (this): make it explicit.** Claude calls this script itself, in
  `-Announce` mode, when it has genuinely finished and is waiting on a
  human. A deliberate act, not an inference. It can be forgotten — a real
  weakness, and the honest trade for never crying wolf. The Notification
  hooks below still cover the mechanical "a prompt is blocking" cases
  automatically, so a forgotten announce costs a convenience, never a
  blocked session (assuming your harness's Notification hooks are actually
  wired — verify this for your own setup rather than assuming it).

  Design rules this follows:
    - NEVER block or fail the session. Every failure path exits 0 silently.
      A notifier that can break your session is worse than no notifier.
    - Don't spam. Idle is debounced; a session that is still moving is silent.
    - No secrets in this file or in settings.json — the token is read at run
      time from ~/.claude/notify.env.
#>

param(
    # Explicit "I am done" mode. NOT a hook path — Claude calls this itself
    # when it has actually finished and is waiting on the operator. See the
    # "Why finished is not a hook" section above.
    [switch]$Announce,

    # Which title -Announce sends under. Defaults to 'Done' so every existing
    # call site that doesn't pass -Mode behaves exactly as before.
    [ValidateSet('Done','Progress','Blocked')]
    [string]$Mode = 'Done',

    [string]$Message = '',
    [string]$Project = 'claude',

    # AFK toggle for remote-approval.ps1. NOT a hook path — invoked manually
    # (or from a shortcut) as:
    #   notify-telegram.ps1 -Afk on
    #   notify-telegram.ps1 -Afk off
    # Writes a plain state file that remote-approval.ps1 reads before every
    # PermissionRequest decision. Lives on this script rather than a second
    # one so there is a single, memorable toggle command. The state file
    # itself is intentionally dumb (one word, no timestamps, no owner) —
    # remote-approval.ps1 treats "absent or anything other than the literal
    # word 'on'" as off, which is the safe default before anyone ever touches
    # this switch.
    [ValidateSet('on','off')]
    [string]$Afk = ''
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# Shared with remote-approval.ps1: word-boundary truncation and the
# relay-bot credential read live in one place, lib/notify-common.ps1. A
# missing lib file must not break this notifier (design rule: never block or
# fail the session) — fall back to inline copies if dot-sourcing fails.
$commonLib = Join-Path $PSScriptRoot 'lib\notify-common.ps1'
$haveCommonLib = $false
try {
    if (Test-Path $commonLib) {
        . $commonLib
        $haveCommonLib = $true
    }
} catch { $haveCommonLib = $false }

# How long the session must stay completely quiet before "come back" is true.
# Declared but not read anywhere below by default — kept as documentation of
# the intended threshold for whoever wires a real debounce using it (see
# "Why finished is not a hook" above), not removed as unused-code cleanup,
# since the value itself would need re-deriving otherwise.
$IdleSeconds = 75

$stateDir = Join-Path $env:TEMP 'claude-notify'
if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}

# Appends one line to $stateDir\notify.log, capped so it can never grow
# without bound. Best-effort: logging must never be why a hook fails.
function Write-NotifyLog {
    param([string]$Dir, [string]$Line)
    try {
        $logFile = Join-Path $Dir 'notify.log'
        $stamp   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Add-Content -Path $logFile -Value "$stamp $Line" -Encoding utf8
        $existing = @(Get-Content -Path $logFile)
        if ($existing.Count -gt 400) {
            $existing[-200..-1] | Set-Content -Path $logFile -Encoding utf8
        }
    } catch { }
}

# Sends one Telegram message. Returns nothing; never throws.
function Send-Notify {
    param([string]$Dir, [string]$Title, [string]$Detail, [string]$ProjectName, [string]$Tag)
    try {
        if ($haveCommonLib) {
            $creds = Get-DevRelayCredentials
            if (-not $creds) { return }
            $token = $creds.Token; $chatId = $creds.ChatId
        } else {
            # Fallback inline copy — only reached if lib/notify-common.ps1 is
            # missing or fails to load. Kept so this notifier's own design
            # rule ("never block or fail the session") doesn't gain a new
            # dependency it can't survive without.
            $envFile = Join-Path $env:USERPROFILE '.claude\notify.env'
            if (-not (Test-Path $envFile)) { return }
            $token = $null; $chatId = $null
            foreach ($line in (Get-Content -Path $envFile)) {
                if ($line -match '^\s*DEV_RELAY_BOT_TOKEN\s*=\s*(.+?)\s*$') { $token  = $Matches[1] }
                if ($line -match '^\s*DEV_RELAY_CHAT_ID\s*=\s*(.+?)\s*$')   { $chatId = $Matches[1] }
            }
            if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($chatId)) { return }
        }

        $text = "[$ProjectName] $Title"
        if (-not [string]::IsNullOrWhiteSpace($Detail)) {
            # Cut on a word boundary, and make the cut visible. History: an
            # earlier version of this script used a hard character-count
            # Substring with no boundary awareness, which produced mid-word
            # stubs reading as if the sentence had finished. Later raised
            # further still, because a self-imposed cap well under Telegram's
            # actual 4096-character API limit was discarding real information
            # (a genuine status update got cut mid-sentence, losing the half
            # that explained a decision made on the operator's behalf) for no
            # reason outside this script. 3900 leaves headroom for the
            # "[project] Title\n" prefix beneath the real ceiling.
            #
            # NOTE: this deliberately passes MaxLength explicitly rather than
            # changing ConvertTo-TruncatedText's own 900 default, which
            # remote-approval.ps1 also uses — a permission prompt SHOULD stay
            # short. Only the announce path wants the long form.
            if ($haveCommonLib) {
                $Detail = ConvertTo-TruncatedText -Text $Detail -MaxLength 3900
            } elseif ($Detail.Length -gt 3900) {
                $cut = $Detail.Substring(0, 3900)
                $lastSpace = $cut.LastIndexOf(' ')
                if ($lastSpace -gt 3000) { $cut = $cut.Substring(0, $lastSpace) }
                $Detail = $cut + ' [...]'
            }
            $text += "`n$Detail"
        }

        $body  = @{ chat_id = $chatId; text = $text; disable_notification = $false } |
                 ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $resp = Invoke-RestMethod -Method Post `
            -Uri "https://api.telegram.org/bot$token/sendMessage" `
            -ContentType 'application/json; charset=utf-8' `
            -Body $bytes -TimeoutSec 10
        Write-NotifyLog $Dir "SENT $Tag ok=$($resp.ok)"
    }
    catch {
        # Never let a notifier break the session. But DO leave a trace: this
        # notifier exits 0 on every failure path, so a broken one is otherwise
        # indistinguishable from a quiet one. That is not hypothetical — hook
        # paths in a settings.json have been silently corrupted before (stray
        # control characters inside the JSON string), pointing hooks at
        # nonexistent executables with nothing firing and nothing saying so.
        try { Write-NotifyLog $Dir "FAIL $Tag $($_.Exception.Message)" } catch { }
    }
}

# ---- explicit announce mode (no stdin; must run before any read) -----------
# Invoked as: powershell -File <this> -Announce -Message "..." -Project "..."
if ($Announce) {
    if ([string]::IsNullOrWhiteSpace($Message)) { exit 0 }
    # Title comes from -Mode, not a hardcoded string — a single hardcoded
    # title for every announce call means progress updates and genuine
    # blocking states become indistinguishable, which corrodes trust in the
    # channel faster than a missed ping does. A closed ValidateSet rather
    # than one switch per mode, so a typo (-Mode Donee) throws before any
    # network call instead of silently falling through to the default.
    $titles = @{
        Done     = 'Done - your move'
        Progress = 'Progress update'
        Blocked  = 'Blocked - need input'
    }
    Send-Notify $stateDir $titles[$Mode] $Message $Project "announce-$($Mode.ToLower())"
    exit 0
}

# ---- AFK toggle (no stdin; must run before any read) ------------------------
# Invoked as: powershell -File <this> -Afk on   /   -Afk off
if ($Afk) {
    $afkFile = Join-Path $stateDir 'afk.state'
    try {
        if ($Afk -eq 'on') {
            Set-Content -Path $afkFile -Value 'on' -Encoding ascii -NoNewline
        } else {
            # 'off' removes the file rather than writing 'off', so the safe
            # default (absent = off) and the explicit-off state can never
            # drift apart into two representations of the same thing.
            if (Test-Path $afkFile) { Remove-Item -Path $afkFile -Force }
        }
        Write-NotifyLog $stateDir "AFK set to $Afk"
    } catch {
        try { Write-NotifyLog $stateDir "FAIL afk-toggle $($_.Exception.Message)" } catch { }
    }
    exit 0
}

try {
    # ---- read the hook payload from stdin -------------------------------
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $payload = $raw | ConvertFrom-Json

    $event     = [string]$payload.hook_event_name
    $sessionId = [string]$payload.session_id
    if ([string]::IsNullOrWhiteSpace($sessionId)) { $sessionId = 'nosession' }
    $safeId      = ($sessionId -replace '[^A-Za-z0-9_-]', '_')
    $counterFile = Join-Path $stateDir "$safeId.count"

    # Derived from the PAYLOAD's cwd, not from $PSScriptRoot: this script is
    # invoked from every project if wired at the user level, so its own
    # location says nothing about which project is actually asking for you.
    $projectName = 'claude'
    if (-not [string]::IsNullOrWhiteSpace([string]$payload.cwd)) {
        $projectName = Split-Path -Leaf ([string]$payload.cwd)
    }

    # Bumps the session's activity counter and returns the new value. Any bump
    # invalidates a pending idle check.
    function Step-Counter {
        $n = 0
        if (Test-Path $counterFile) {
            [int]::TryParse((Get-Content -Path $counterFile -Raw).Trim(), [ref]$n) | Out-Null
        }
        $n = $n + 1
        [string]$n | Set-Content -Path $counterFile -Encoding ascii
        return $n
    }

    switch ($event) {
        'UserPromptSubmit' {
            # The operator is here. Cancel any pending idle ping, say nothing.
            Step-Counter | Out-Null
            exit 0
        }

        'Stop' {
            # Deliberately silent. The turn's output ending is NOT "finished" —
            # see the header. Left wired-capable but sends nothing.
            Step-Counter | Out-Null
            exit 0
        }

        'Notification' {
            $msg     = [string]$payload.message
            $matcher = [string]$payload.notification_type
            if ([string]::IsNullOrWhiteSpace($msg)) { $msg = $matcher }

            # The three "a human is required" shapes.
            #
            # The three-way split below is deliberate. Falling through to
            # "Needs attention" for ANY type leaked an auth-success
            # notification during testing once. But a strict allowlist is the
            # WORSE failure if this payload field is ever named something
            # other than notification_type: every event would be suppressed
            # and the notifier would be silently dead, which looks identical
            # to "nothing needed you".
            #
            # So: recognised-and-wanted -> send; recognised-but-unwanted ->
            # drop; can't tell (field absent/empty) -> send, because your
            # settings.json matcher has already filtered at that point and a
            # spurious ping is far cheaper than silence.
            $title = $null
            if ($matcher -match 'permission') {
                $title = 'Needs your approval'
            } elseif ($matcher -match 'idle') {
                $title = 'Waiting on you'
            } elseif ($matcher -match 'agent_needs_input') {
                $title = 'Agent needs input'
            } elseif (-not [string]::IsNullOrWhiteSpace($matcher)) {
                exit 0   # a type we know about and deliberately don't want
            } else {
                $title = 'Needs attention'
            }

            # A prompt is itself activity, and it already pings — don't let a
            # pending idle check fire a second message on top of it.
            Step-Counter | Out-Null
            Send-Notify $stateDir $title $msg $projectName "Notification/$title"
            exit 0
        }

        default { exit 0 }
    }
}
catch {
    # Never let a notifier break the session.
}
exit 0

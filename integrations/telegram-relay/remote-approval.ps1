<#
  remote-approval.ps1 — answers a Claude Code PermissionRequest from either a
  local popup on this machine OR Telegram, whichever the operator answers
  first, so a permission prompt never just sits blocked on one single
  channel.

  Started as a presence-gated, Telegram-only design (AFK off -> native
  prompt, AFK on -> Telegram only), then rebuilt into a genuine dual-race.
  See ../README.md for the full design rationale, including why
  presence-gated was the first choice and what the dual-race trades away
  (the terminal's real diff view, on EVERY prompt, not just while away) in
  exchange for never needing to remember an AFK toggle.

  ## What the dual-race actually does
  The `afk.state` toggle (`notify-telegram.ps1 -Afk on|off`) gates whether
  remote-approval runs AT ALL — it no longer picks ONE channel.
    off -> exit fast, zero popup, zero Telegram, native prompt exactly as
           the plain, unmodified Claude Code experience.
    on  -> `Invoke-DualApproval`: a local WinForms popup (Allow/Deny
           buttons) AND a Telegram poll run concurrently on ONE STA thread
           (a `System.Windows.Forms.Timer` drives the Telegram poll so it
           never blocks the popup's own message loop — no second thread, no
           cross-thread state). Whichever answers first closes the popup and
           returns that decision; the loser is simply never consulted again.
           Fail-closed-by-construction throughout: any failure (WinForms
           unavailable, e.g. no interactive desktop — SSH/headless — network
           down, malformed reply) still ends in an explicit deny, never
           silent fallthrough to allow.
  The original Telegram-only decision loop (`Invoke-RemoteApproval`,
  `Wait-ForTelegramReply`) is KEPT, not deleted — it's what the automated
  test suite exercises directly, and `Invoke-DualApproval` falls back to it
  (same nonce, same already-sent Telegram message, no double-send) if the
  popup itself fails to construct, so a headless box degrades to the old
  Telegram-only behavior instead of hanging or crashing.

  ============================================================================
  THE ONE RULE THAT MATTERS: FAIL CLOSED, BY CONSTRUCTION, NEVER BY TIMEOUT.
  ============================================================================
  Per Claude Code's own hooks documentation (verify against your current
  docs, not this comment, before relying on it): "A timed-out command,
  http, or mcp_tool hook doesn't block the tool call. The call continues
  through the normal permission flow." A hook that times out is NOT a deny —
  it is silence, and silence here can resolve to the tool call proceeding.
  So this script self-deadlines well inside the harness's own default hook
  timeout, and EVERY path — network failure, malformed payload, missing
  credentials, unparseable reply, unexpected exception — must end in an
  explicit printed `deny`, never in falling through to "no output". The one
  and only legitimate "no output" exit is the AFK-off fast path, checked
  first, before anything else runs.

  ## PermissionRequest payload/output shape
  The distinct `PermissionRequest` event (which is what this script wants —
  it fires only when a decision is actually needed, unlike `PreToolUse`
  which fires on every tool call regardless) uses this shape:

    { "hookSpecificOutput": { "hookEventName": "PermissionRequest",
        "decision": "allow" | "deny" | "escalate",
        "decisionReason": "..." } }

  This script emits that shape. `escalate` (ask the user) exists but is
  unused here — this design's "ask the user" IS the AFK-off fast path
  (return nothing, let the native prompt render), not escalate. Verify this
  shape against your own harness's current hooks documentation before
  relying on it — hook payload/output shapes are exactly the kind of thing
  that changes between versions without much fanfare.

  ## Design: presence-gated, not dual-race, is the OTHER valid shape
  If you'd rather not pay the "costs the terminal's diff view on every
  prompt" cost, a simpler presence-gated design (AFK off -> exit 0 entirely,
  AFK on -> Telegram-only, no popup) is what `Invoke-RemoteApproval` below
  still implements on its own — you could wire the entry point to call that
  directly instead of `Invoke-DualApproval` and drop the popup code.

  ## Bot separation (security constraint, not preference)
  Uses ONLY a single relay bot via Get-DevRelayCredentials
  (lib/notify-common.ps1 -> ~/.claude/notify.env). If you run any other bot
  for other purposes (status pages, ops alerts, anything deployed
  elsewhere), never let it share a token with this one — a bot whose token
  lives on any other host must never gain a reply path into your permission
  decisions.

  ## Matching a reply to a request
  Each request gets a short nonce (derived from tool_use_id, already unique
  per call). A reply is accepted three ways, in order of how likely an
  operator is to actually type it:
    1. A bare "allow"/"deny" (also yes/no/y/n/ok) as a brand-new message,
       when this is PROVABLY the only pending request — see "Pending-request
       markers" below. This is the common case: an operator on a phone
       typing a plain message, no swipe-to-reply gesture required.
    2. A genuine Telegram reply-to the request message — then a bare
       yes/no/allow/deny is unambiguous regardless of how many requests are
       pending, because Telegram itself says which message it answers.
    3. A fresh message of the form "allow <nonce>" / "deny <nonce>" — the
       fallback when more than one request is genuinely in flight and a
       bare reply would be ambiguous.
  A reply that arrives after this request's own deadline denial is simply
  never seen: the process has already exited by then. A stale reply from
  BEFORE this request was sent is rejected by the date >= request-start-time
  check in Test-ReplyMatch.

  ## Pending-request markers
  A bare "allow" typed as a brand-new message only works when it's
  unambiguous which request it answers, so each running instance drops an
  empty file `pending-<nonce>.marker` in the state dir right after its
  Telegram send succeeds, and removes it on every exit path via try/finally
  (Invoke-RemoteApproval). Test-SolePendingRequest lists marker files newer
  than (DeadlineSeconds + 30s) — anything older is provably from a dead
  process, since the deadline is the hard backstop no live instance can
  outlive — and returns true only when EXACTLY ONE live marker exists and it
  is this instance's own. That boolean is recomputed once per poll iteration
  (so a bare reply becomes acceptable mid-wait the moment a sibling request
  resolves) and passed into the still-pure Test-ReplyMatch as -SolePending;
  the function itself does no I/O. Deliberately conservative: any ambiguity,
  any I/O error reading the state dir, any inability to confirm "exactly one
  and it's mine" resolves to false, which only ever narrows acceptance back
  to the reply-to/nonce forms — it can never manufacture a match that wasn't
  there. Two instances starting within the same instant both see each
  other's marker (or neither does, in which case count != 1 for both) —
  either way, no window exists where both independently conclude "just me".

  ## Known limitation: concurrent pending requests
  Telegram's getUpdates is a single-consumer polling contract per bot token;
  two PermissionRequest hooks polling at once (e.g. two Claude Code sessions
  in two worktrees, both AFK-on, both blocked) can occasionally 409 each
  other. This script treats getUpdates failures (network or 409) as
  transient and keeps retrying until its own deadline rather than denying
  immediately on the first one — the deadline remains the real backstop.
  Each poller only ever reads (never advances a shared offset), so pollers
  don't suppress updates from each other; worst case is wasted round-trips,
  not a missed reply. The pending-marker mechanism above is orthogonal to
  this: it decides whether a BARE reply is ambiguous across requests, not
  whether the getUpdates poll itself can 409-collide.

  ## Never modifies ~/.claude/settings.json
  This script only ever reports its own decision on stdout. Wiring it into
  your settings.json (which hook event, which matcher) is a manual step —
  see ../README.md.

  Design rules carried over from notify-telegram.ps1 where they still apply:
    - No secrets in this file. Credentials come from ~/.claude/notify.env via
      the shared lib, at run time only.
    - Every logged line is passed through Protect-LogText, which redacts
      anything matching a Telegram bot-token shape — HTTP exceptions from
      Invoke-RestMethod can otherwise leak the token into the log via the
      request URI, which embeds it (https://api.telegram.org/bot<token>/...).
#>

param()

# Fail-closed requires exceptions to actually surface so the top-level
# try/catch can turn them into an explicit deny — the opposite of
# notify-telegram.ps1's SilentlyContinue, which is correct THERE because
# silence is safe for a pure notifier and dangerous HERE.
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'lib\notify-common.ps1')

$stateDir = Join-Path $env:TEMP 'claude-notify'
if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}

# ---- logging (own log file; never lets a bot token through) ---------------
function Protect-LogText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    # Telegram bot tokens have the shape <digits>:<35 base64url-ish chars> and
    # only ever appear in this script inside a /bot<token>/ URL path, so this
    # is deliberately broad rather than trying to match the exact token
    # length precisely.
    return ($Text -replace '(?i)bot\d+:[A-Za-z0-9_\-]+', 'bot<REDACTED>')
}

function Write-ApprovalLog {
    param([string]$Dir, [string]$Line)
    try {
        $logFile = Join-Path $Dir 'remote-approval.log'
        $stamp   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Add-Content -Path $logFile -Value "$stamp $(Protect-LogText $Line)" -Encoding utf8
        $existing = @(Get-Content -Path $logFile)
        if ($existing.Count -gt 400) {
            $existing[-200..-1] | Set-Content -Path $logFile -Encoding utf8
        }
    } catch { }
}

# ---- AFK gate ---------------------------------------------------------------
# Toggled via: notify-telegram.ps1 -Afk on|off (shared state dir/file).
# Absent, unreadable, or anything other than the literal word 'on' => off.
# That "can't tell -> off" default is the conservative one: it reproduces
# the plain native-prompt behaviour rather than guessing AFK.
function Get-AfkState {
    param([string]$StateDir)
    try {
        $afkFile = Join-Path $StateDir 'afk.state'
        if (-not (Test-Path $afkFile)) { return $false }
        $content = (Get-Content -Path $afkFile -Raw -ErrorAction Stop).Trim()
        return ($content -eq 'on')
    } catch {
        return $false
    }
}

# ---- nonce --------------------------------------------------------------
# tool_use_id is already unique per tool call, so deriving from it (rather
# than minting a fresh random id and having to persist it somewhere to
# survive process exit) means the nonce is naturally stable and needs no
# state file of its own.
function Get-RequestNonce {
    param([string]$ToolUseId)
    $clean = [string]$ToolUseId -replace '[^A-Za-z0-9]', ''
    if ($clean.Length -ge 6) {
        return $clean.Substring($clean.Length - 6).ToUpper()
    }
    return ([guid]::NewGuid().ToString('N').Substring(0, 6)).ToUpper()
}

# ---- message formatting --------------------------------------------------
function Get-ToolTargetSummary {
    param([string]$ToolName, $ToolInput)
    switch ($ToolName) {
        'Bash' {
            $cmd  = [string]$ToolInput.command
            $desc = [string]$ToolInput.description
            $line = "Bash: $cmd"
            if (-not [string]::IsNullOrWhiteSpace($desc)) { $line += "  ($desc)" }
            return $line
        }
        'Edit'      { return "Edit: $([string]$ToolInput.file_path)" }
        'Write'     { return "Write: $([string]$ToolInput.file_path)" }
        'Read'      { return "Read: $([string]$ToolInput.file_path)" }
        'WebFetch'  { return "WebFetch: $([string]$ToolInput.url)" }
        'WebSearch' { return "WebSearch: $([string]$ToolInput.query)" }
        default     { return "$ToolName" }
    }
}

# Shared by both channels: the tool-target summary + truncated raw args,
# with neither channel's own reply instructions baked in (each of
# Format-ApprovalMessage/Format-PopupBody below appends its own, since a
# Telegram reply needs text instructions and the popup needs none — it has
# buttons). Extracted so the two channels' bodies can never drift out of
# describing the SAME request differently.
function Get-ApprovalBody {
    param($Payload, [string]$Nonce)

    $toolName  = [string]$Payload.tool_name
    $toolInput = $Payload.tool_input

    $target = ConvertTo-TruncatedText -Text (Get-ToolTargetSummary -ToolName $toolName -ToolInput $toolInput) -MaxLength 500

    $rawJson = '(no args)'
    if ($null -ne $toolInput) {
        try { $rawJson = ($toolInput | ConvertTo-Json -Compress -Depth 6) } catch { $rawJson = '(could not render args)' }
    }
    $rawJson = ConvertTo-TruncatedText -Text $rawJson -MaxLength 500

    $cwd     = [string]$Payload.cwd
    $project = 'claude'
    if (-not [string]::IsNullOrWhiteSpace($cwd)) { $project = Split-Path -Leaf $cwd }

    return [pscustomobject]@{
        Project = $project
        Target  = $target
        RawJson = $rawJson
    }
}

# The operator is being asked to decide without seeing the actual diff/output
# — the message says so explicitly rather than implying full context.
function Format-ApprovalMessage {
    param($Payload, [string]$Nonce)

    $body = Get-ApprovalBody -Payload $Payload -Nonce $Nonce
    $lines = @(
        "[$($body.Project)] Approval needed - id $Nonce",
        $body.Target,
        "Raw args: $($body.RawJson)",
        "",
        "You cannot see the diff or output for this - decide from the summary above only.",
        "Also showing as a popup on the machine - whichever answers first wins.",
        "Reply allow or deny.",
        "(If more than one request is pending, send: allow $Nonce  /  deny $Nonce instead)",
        "Auto-denies if unanswered."
    )
    return ($lines -join "`n")
}

# Same underlying request, worded for the popup: no reply-text instructions
# (it has Allow/Deny buttons instead), same "no diff/output" honesty note.
function Format-PopupBody {
    param($Payload, [string]$Nonce)

    $body = Get-ApprovalBody -Payload $Payload -Nonce $Nonce
    $lines = @(
        "Tool: $($body.Target)",
        "",
        "Raw args:",
        $body.RawJson,
        "",
        "You cannot see the diff or output for this - decide from the summary above only.",
        "Also live on Telegram right now (id $Nonce) - whichever answers first wins."
    )
    return ($lines -join "`n")
}

# ---- Telegram API (thin; every call bounded, every failure throws) --------
function Send-TelegramApiMessage {
    param([string]$Token, [string]$ChatId, [string]$Text)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $body  = @{ chat_id = $ChatId; text = $Text; disable_notification = $false } | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $resp  = Invoke-RestMethod -Method Post `
        -Uri "https://api.telegram.org/bot$Token/sendMessage" `
        -ContentType 'application/json; charset=utf-8' `
        -Body $bytes -TimeoutSec 10
    if (-not $resp.ok) { throw "sendMessage: ok=false" }
    return [Int64]$resp.result.message_id
}

# Deliberately never passes an `offset` — that would permanently mark
# updates as consumed for every other poller of this same bot token, and two
# hook instances could legitimately be polling at once (see header). Instead
# always fetches the recent backlog and relies on Test-ReplyMatch's
# chat/date/nonce/reply-to filtering to find the relevant reply, which is
# idempotent against re-seeing the same update on the next iteration.
function Get-TelegramApiUpdates {
    param([string]$Token)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $resp = Invoke-RestMethod -Method Get `
        -Uri "https://api.telegram.org/bot$Token/getUpdates?timeout=0" -TimeoutSec 10
    if (-not $resp.ok) { throw "getUpdates: ok=false" }
    return @($resp.result)
}

# ---- pending-request markers (own-instance-presence tracking) -------------
# See the header's "Pending-request markers" section for the design and the
# safety argument. All three functions are deliberately silent on I/O
# failure (try/catch swallow) — a marker-file problem must only ever narrow
# what Test-SolePendingRequest reports (toward "not sole"), never crash the
# hook or block the reply-to/nonce paths that don't depend on markers at all.

function Get-PendingMarkerPath {
    param([string]$StateDir, [string]$Nonce)
    return (Join-Path $StateDir "pending-$Nonce.marker")
}

function New-PendingMarker {
    param([string]$StateDir, [string]$Nonce)
    try {
        # Content is unused - existence + the filesystem's own mtime are all
        # Test-SolePendingRequest needs. Empty file, deliberately.
        Set-Content -Path (Get-PendingMarkerPath -StateDir $StateDir -Nonce $Nonce) -Value '' -NoNewline -Encoding ascii -Force
    } catch { }
}

function Remove-PendingMarker {
    param([string]$StateDir, [string]$Nonce)
    try {
        Remove-Item -Path (Get-PendingMarkerPath -StateDir $StateDir -Nonce $Nonce) -Force -ErrorAction SilentlyContinue
    } catch { }
}

# Returns $true ONLY when exactly one live (non-stale) pending marker exists
# in $StateDir and it is THIS request's own ($Nonce). Any ambiguity (0 or 2+
# live markers), any I/O failure, any inability to confirm ownership resolves
# to $false — mirroring Test-ReplyMatch's own "can't tell -> don't guess"
# rule. $MaxAgeSeconds ages out markers a killed/crashed instance never
# cleaned up: a live instance cannot still be polling past its own deadline,
# so anything older than deadline+margin is provably dead and ignored.
function Test-SolePendingRequest {
    param([string]$StateDir, [string]$Nonce, [int]$MaxAgeSeconds = 570)
    try {
        $cutoffUtc = (Get-Date).ToUniversalTime().AddSeconds(-$MaxAgeSeconds)
        $liveMarkers = @(Get-ChildItem -Path $StateDir -Filter 'pending-*.marker' -File -ErrorAction Stop |
            Where-Object { $_.LastWriteTimeUtc -ge $cutoffUtc })
        if ($liveMarkers.Count -ne 1) { return $false }
        return ($liveMarkers[0].Name -eq "pending-$Nonce.marker")
    } catch {
        return $false
    }
}

# ---- reply matching (pure function; this is the unit-tested core) ---------
# Returns 'allow' | 'deny' | $null (no match / keep waiting). Never throws —
# any unexpected shape is treated as "no match", never as a decision.
# -SolePending is a plain bool computed by the caller (via
# Test-SolePendingRequest) so this function stays pure/no-I/O and stays
# trivially unit-testable without touching the filesystem.
function Test-ReplyMatch {
    param(
        $Update,
        [string]$ChatId,
        [Int64]$SentMessageId,
        [string]$Nonce,
        [Int64]$RequestStartUnix,
        [bool]$SolePending = $false
    )
    try {
        if (-not $Update.message) { return $null }
        $msg = $Update.message
        if (-not $msg.chat) { return $null }
        if ([string]$msg.chat.id -ne [string]$ChatId) { return $null }   # not our operator - ignore silently
        if ($msg.date -and ([Int64]$msg.date -lt $RequestStartUnix)) { return $null }  # stale, predates this request

        $text = [string]$msg.text
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        $trimmed = $text.Trim()

        $isReplyToUs = $false
        if ($msg.reply_to_message -and $SentMessageId -and $msg.reply_to_message.message_id) {
            if ([Int64]$msg.reply_to_message.message_id -eq [Int64]$SentMessageId) { $isReplyToUs = $true }
        }

        if ($isReplyToUs) {
            if ($trimmed -match '(?i)^(deny|no|n)\b')  { return 'deny' }
            if ($trimmed -match '(?i)^(allow|yes|y|ok)\b') { return 'allow' }
            return $null   # ambiguous reply-to - keep waiting rather than guess
        }

        if (-not [string]::IsNullOrWhiteSpace($Nonce)) {
            $escaped = [regex]::Escape($Nonce)
            if ($trimmed -match "(?i)^deny\s+$escaped\s*$")  { return 'deny' }
            if ($trimmed -match "(?i)^allow\s+$escaped\s*$") { return 'allow' }
        }

        # Bare "allow"/"deny" as a brand-new message (no reply-to, no nonce)
        # is accepted ONLY when the caller has confirmed this is the sole
        # live pending request — see Test-SolePendingRequest. Anchored to the
        # whole message (optional trailing punctuation/whitespace only) so
        # this stays tighter than the reply-to case's prefix match: a
        # sentence merely starting with "allow" is not accepted here, since
        # unlike a reply-to, a fresh message carries no structural proof it
        # was meant as an answer at all.
        if ($SolePending) {
            if ($trimmed -match '(?i)^(deny|no|n)\s*[.!]?$')      { return 'deny' }
            if ($trimmed -match '(?i)^(allow|yes|y|ok)\s*[.!]?$') { return 'allow' }
        }

        return $null   # doesn't reference this request - never matched to the wrong one
    } catch {
        return $null
    }
}

# ---- shared decision-loop primitives ---------------------------------------
# Both channels (the old Telegram-only loop and the new popup's Timer) drive
# THE SAME matching logic through these two functions — extracted so "does a
# reply count" is never written twice. Invoke-ApprovalPollTick is one
# iteration's worth of work (one getUpdates call + match check); callers
# decide how to drive it (a blocking while+Start-Sleep loop here, a
# non-blocking WinForms Timer.Tick in Show-ApprovalPopup below).

# One poll iteration. Returns @{ decision; reason } on a match, $null on "no
# match yet, keep waiting". Never throws — a failed getUpdates call is logged
# and treated as "no match this tick", not an error the caller must handle.
# $ConsecutiveFailures is a [ref] so the caller's own counter (used only for
# log context — the deadline is what actually bounds a failure run, not this)
# persists across ticks.
function Invoke-ApprovalPollTick {
    param(
        [string]$Token,
        [string]$ChatId,
        [Int64]$SentMessageId,
        [string]$Nonce,
        [Int64]$RequestStartUnix,
        [string]$StateDir,
        [int]$MarkerMaxAge,
        [ref]$ConsecutiveFailures
    )
    $updates = @()
    try {
        $updates = Get-TelegramApiUpdates -Token $Token
        $ConsecutiveFailures.Value = 0
    } catch {
        $ConsecutiveFailures.Value++
        Write-ApprovalLog $StateDir "FAIL poll id=$Nonce attempt=$($ConsecutiveFailures.Value) $($_.Exception.Message)"
        # Transient (network blip, or a 409 from a concurrent poller — see
        # header) — the caller's own deadline is what bounds an unbroken
        # failure run, not this function; a failed tick is just "no match".
    }

    # Recomputed every tick (cheap: one directory listing) so a sibling
    # request resolving mid-wait immediately makes bare replies acceptable
    # for this one too, without waiting for a new request to trigger it.
    $solePending = Test-SolePendingRequest -StateDir $StateDir -Nonce $Nonce -MaxAgeSeconds $MarkerMaxAge

    foreach ($u in $updates) {
        $m = Test-ReplyMatch -Update $u -ChatId $ChatId -SentMessageId $SentMessageId -Nonce $Nonce -RequestStartUnix $RequestStartUnix -SolePending $solePending
        if ($m) {
            Write-ApprovalLog $StateDir "MATCHED id=$Nonce decision=$m solePending=$solePending"
            return @{ decision = $m; reason = "remote-approval: operator replied $m via Telegram" }
        }
    }
    return $null
}

# Blocking poll loop against an ALREADY-SENT Telegram request — ticks via
# Invoke-ApprovalPollTick until either a reply matches or the deadline
# passes. Used by both Invoke-RemoteApproval (the original Telegram-only
# path, still what the automated tests exercise directly) and
# Invoke-DualApproval's popup-construction-failed fallback (same nonce, same
# already-sent message — no double-send). $StartTime is a parameter (not
# `Get-Date` computed here) so a caller falling back mid-request keeps the
# ORIGINAL deadline rather than getting a fresh one.
function Wait-ForTelegramReply {
    param(
        [string]$Token,
        [string]$ChatId,
        [Int64]$SentMessageId,
        [string]$Nonce,
        [Int64]$RequestStartUnix,
        [string]$StateDir,
        [int]$DeadlineSeconds,
        [double]$PollIntervalSeconds,
        [datetime]$StartTime
    )
    # Buffer reserved at the end of the budget for the courtesy timeout notice
    # (best-effort Telegram send). Capped at 15s, but never more than a third
    # of the whole deadline — a flat 15s buffer would silently swallow ALL
    # polling time for any DeadlineSeconds <= 15, which is harmless at a
    # typical production default but is a real landmine for any smaller value
    # (found by this script's own test suite using short test deadlines).
    $buffer = [Math]::Min(15, [Math]::Floor($DeadlineSeconds / 3))
    $pollDeadline = $StartTime.AddSeconds([Math]::Max(0, $DeadlineSeconds - $buffer))
    $markerMaxAge = $DeadlineSeconds + 30
    $consecutiveFailures = 0

    while ((Get-Date) -lt $pollDeadline) {
        $failRef = [ref]$consecutiveFailures
        $tick = Invoke-ApprovalPollTick -Token $Token -ChatId $ChatId -SentMessageId $SentMessageId `
            -Nonce $Nonce -RequestStartUnix $RequestStartUnix -StateDir $StateDir -MarkerMaxAge $markerMaxAge `
            -ConsecutiveFailures $failRef
        $consecutiveFailures = $failRef.Value
        if ($tick) { return $tick }

        $remaining = ($pollDeadline - (Get-Date)).TotalSeconds
        if ($remaining -le 0) { break }
        Start-Sleep -Milliseconds ([int]([Math]::Min($PollIntervalSeconds, [Math]::Max(0.2, $remaining)) * 1000))
    }

    Write-ApprovalLog $StateDir "TIMEOUT id=$Nonce - denying, no valid reply before deadline"
    try {
        Send-TelegramApiMessage -Token $Token -ChatId $ChatId `
            -Text "[$Nonce] Timed out waiting for a reply - denied automatically." | Out-Null
    } catch {
        Write-ApprovalLog $StateDir "FAIL timeout-notice id=$Nonce $($_.Exception.Message)"
    }
    return @{ decision = 'deny'; reason = 'remote-approval: no reply before deadline' }
}

# ---- local popup ------------------------------------------------------------
# WinForms modal on the SAME thread that polls Telegram — a
# System.Windows.Forms.Timer drives Invoke-ApprovalPollTick on each tick
# inside the form's own message loop (ShowDialog pumps it), so no second
# thread and no cross-thread state is ever needed: button clicks and timer
# ticks are just two different events on one message queue, and whichever
# fires first (and sets $result.decision) wins — the loser's own next tick
# (if the timer) or click (if the buttons, now disposed) simply never
# happens because the form is already closed.
#
# Requires an interactive desktop session. Throws if WinForms itself can't
# initialize (no desktop — SSH/headless) — deliberately NOT caught in here;
# Invoke-DualApproval catches it and falls back to Wait-ForTelegramReply.
function Show-ApprovalPopup {
    param(
        $Payload,
        [string]$Nonce,
        [string]$Token,
        [string]$ChatId,
        [Int64]$SentMessageId,
        [Int64]$RequestStartUnix,
        [string]$StateDir,
        [int]$DeadlineSeconds,
        [double]$PollIntervalSeconds,
        [datetime]$StartTime
    )
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $body = Get-ApprovalBody -Payload $Payload -Nonce $Nonce
    $popupText = Format-PopupBody -Payload $Payload -Nonce $Nonce

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "[$($body.Project)] Approval needed - $Nonce"
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.Width = 560
    $form.Height = 420
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Multiline = $true
    $textBox.ReadOnly = $true
    $textBox.ScrollBars = 'Vertical'
    $textBox.Font = New-Object System.Drawing.Font('Consolas', 9)
    $textBox.Text = $popupText
    $textBox.Location = New-Object System.Drawing.Point(10, 10)
    $textBox.Size = New-Object System.Drawing.Size(524, 280)
    $form.Controls.Add($textBox)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(10, 298)
    $statusLabel.Size = New-Object System.Drawing.Size(524, 20)
    $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    $statusLabel.Text = 'Also live on Telegram - whichever answers first wins.'
    $form.Controls.Add($statusLabel)

    $denyButton = New-Object System.Windows.Forms.Button
    $denyButton.Text = 'Deny'
    $denyButton.Location = New-Object System.Drawing.Point(410, 335)
    $denyButton.Size = New-Object System.Drawing.Size(120, 35)
    $denyButton.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
    $denyButton.ForeColor = [System.Drawing.Color]::White
    $denyButton.FlatStyle = 'Flat'
    $form.Controls.Add($denyButton)

    $allowButton = New-Object System.Windows.Forms.Button
    $allowButton.Text = 'Allow'
    $allowButton.Location = New-Object System.Drawing.Point(280, 335)
    $allowButton.Size = New-Object System.Drawing.Size(120, 35)
    $allowButton.BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
    $allowButton.ForeColor = [System.Drawing.Color]::White
    $allowButton.FlatStyle = 'Flat'
    $form.Controls.Add($allowButton)

    $form.AcceptButton = $allowButton
    $form.CancelButton = $denyButton

    $result = @{ decision = $null; reason = $null }

    $allowButton.Add_Click({
        $result.decision = 'allow'
        $result.reason = 'remote-approval: operator clicked Allow in the local popup'
        $form.Close()
    })
    $denyButton.Add_Click({
        $result.decision = 'deny'
        $result.reason = 'remote-approval: operator clicked Deny in the local popup'
        $form.Close()
    })

    $buffer = [Math]::Min(15, [Math]::Floor($DeadlineSeconds / 3))
    $pollDeadline = $StartTime.AddSeconds([Math]::Max(0, $DeadlineSeconds - $buffer))
    $markerMaxAge = $DeadlineSeconds + 30
    $consecutiveFailures = 0

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [Math]::Max(500, [int]($PollIntervalSeconds * 1000))
    $timer.Add_Tick({
        $remaining = [Math]::Max(0, [int](($pollDeadline - (Get-Date)).TotalSeconds))
        $statusLabel.Text = "Also live on Telegram - whichever answers first wins. (~${remaining}s left)"
        if ((Get-Date) -ge $pollDeadline) {
            $timer.Stop()
            $result.decision = 'deny'
            $result.reason = 'remote-approval: no reply before deadline'
            $form.Close()
            return
        }
        $failRef = [ref]$consecutiveFailures
        $tick = Invoke-ApprovalPollTick -Token $Token -ChatId $ChatId -SentMessageId $SentMessageId `
            -Nonce $Nonce -RequestStartUnix $RequestStartUnix -StateDir $StateDir -MarkerMaxAge $markerMaxAge `
            -ConsecutiveFailures $failRef
        $consecutiveFailures = $failRef.Value
        if ($tick) {
            $timer.Stop()
            $result.decision = $tick.decision
            $result.reason = $tick.reason
            $form.Close()
        }
    })

    # Fail-closed even if the window is dismissed some OTHER way (Alt+F4, the
    # native X button) — FormClosing fires on every close path, and a
    # decision that's still $null at that point means neither a button nor
    # the timer ever set one.
    $form.Add_FormClosing({
        $timer.Stop()
        if (-not $result.decision) {
            $result.decision = 'deny'
            $result.reason = 'remote-approval: popup closed without a decision'
        }
    })

    try { [System.Media.SystemSounds]::Exclamation.Play() } catch { }
    $form.Add_Shown({ $form.Activate() | Out-Null })
    $timer.Start()
    [void]$form.ShowDialog()
    $timer.Dispose()
    $form.Dispose()

    Write-ApprovalLog $StateDir "DECIDED id=$Nonce decision=$($result.decision) via=popup-or-telegram-race"
    return @{ decision = $result.decision; reason = $result.reason }
}

# ---- orchestration ---------------------------------------------------------
# Returns $null for "no decision" (toggle off), or @{ decision; reason }.
# $null is ONLY returned from the toggle-off check. Every other exit from
# this function is an explicit decision hashtable - including every catch.
function Invoke-RemoteApproval {
    param(
        $Payload,
        [string]$StateDir,
        [int]$DeadlineSeconds = 540,
        [double]$PollIntervalSeconds = 3
    )
    $startTime = Get-Date

    if (-not (Get-AfkState -StateDir $StateDir)) {
        return $null
    }

    $creds = Get-DevRelayCredentials
    if (-not $creds) {
        return @{ decision = 'deny'; reason = 'remote-approval: relay credentials unavailable' }
    }

    $toolUseId = [string]$Payload.tool_use_id
    $nonce = Get-RequestNonce -ToolUseId $toolUseId
    $messageText = Format-ApprovalMessage -Payload $Payload -Nonce $nonce
    $requestStartUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $sentMessageId = $null
    try {
        $sentMessageId = Send-TelegramApiMessage -Token $creds.Token -ChatId $creds.ChatId -Text $messageText
        Write-ApprovalLog $StateDir "SENT request id=$nonce tool_use_id=$toolUseId msg_id=$sentMessageId"
    } catch {
        Write-ApprovalLog $StateDir "FAIL send id=$nonce $($_.Exception.Message)"
        return @{ decision = 'deny'; reason = 'remote-approval: failed to send Telegram request' }
    }

    # Marker written only after the send above succeeded (a request that
    # never reached Telegram has no business making itself "the sole pending
    # request" for anyone). Removed on every exit from here down — match,
    # timeout, or any unexpected exception — via finally, so a killed process
    # is the only way a marker outlives its request (see header).
    New-PendingMarker -StateDir $StateDir -Nonce $nonce
    try {
        return Wait-ForTelegramReply -Token $creds.Token -ChatId $creds.ChatId -SentMessageId $sentMessageId `
            -Nonce $nonce -RequestStartUnix $requestStartUnix -StateDir $StateDir `
            -DeadlineSeconds $DeadlineSeconds -PollIntervalSeconds $PollIntervalSeconds -StartTime $startTime
    } finally {
        Remove-PendingMarker -StateDir $StateDir -Nonce $nonce
    }
}

# The production entry point (see header). Same toggle/creds/send/marker
# shape as Invoke-RemoteApproval above — the only difference is what happens
# AFTER the send: this races a local popup against the same Telegram poll
# instead of polling alone, falling back to the plain poll (Wait-ForTelegramReply,
# same nonce/message, no re-send) if the popup can't even construct (no
# desktop session).
function Invoke-DualApproval {
    param(
        $Payload,
        [string]$StateDir,
        [int]$DeadlineSeconds = 540,
        [double]$PollIntervalSeconds = 3
    )
    $startTime = Get-Date

    if (-not (Get-AfkState -StateDir $StateDir)) {
        return $null
    }

    $creds = Get-DevRelayCredentials
    if (-not $creds) {
        return @{ decision = 'deny'; reason = 'remote-approval: relay credentials unavailable' }
    }

    $toolUseId = [string]$Payload.tool_use_id
    $nonce = Get-RequestNonce -ToolUseId $toolUseId
    $messageText = Format-ApprovalMessage -Payload $Payload -Nonce $nonce
    $requestStartUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $sentMessageId = $null
    try {
        $sentMessageId = Send-TelegramApiMessage -Token $creds.Token -ChatId $creds.ChatId -Text $messageText
        Write-ApprovalLog $StateDir "SENT request id=$nonce tool_use_id=$toolUseId msg_id=$sentMessageId"
    } catch {
        Write-ApprovalLog $StateDir "FAIL send id=$nonce $($_.Exception.Message)"
        return @{ decision = 'deny'; reason = 'remote-approval: failed to send Telegram request' }
    }

    New-PendingMarker -StateDir $StateDir -Nonce $nonce
    try {
        try {
            return Show-ApprovalPopup -Payload $Payload -Nonce $nonce -Token $creds.Token -ChatId $creds.ChatId `
                -SentMessageId $sentMessageId -RequestStartUnix $requestStartUnix -StateDir $StateDir `
                -DeadlineSeconds $DeadlineSeconds -PollIntervalSeconds $PollIntervalSeconds -StartTime $startTime
        } catch {
            Write-ApprovalLog $StateDir "FAIL popup id=$nonce $($_.Exception.Message) - falling back to Telegram-only"
            return Wait-ForTelegramReply -Token $creds.Token -ChatId $creds.ChatId -SentMessageId $sentMessageId `
                -Nonce $nonce -RequestStartUnix $requestStartUnix -StateDir $StateDir `
                -DeadlineSeconds $DeadlineSeconds -PollIntervalSeconds $PollIntervalSeconds -StartTime $startTime
        }
    } finally {
        Remove-PendingMarker -StateDir $StateDir -Nonce $nonce
    }
}

# ---- entry point ------------------------------------------------------------
# Guarded so tests can dot-source this file (setting REMOTE_APPROVAL_TEST_MODE=1
# first) to get every function above loaded for direct, mock-free unit
# testing, without triggering a real stdin read / real network activity.
if ($env:REMOTE_APPROVAL_TEST_MODE -ne '1') {
    $decision = $null
    try {
        # AFK check FIRST, before touching stdin further than draining it —
        # this is the "zero behaviour change, no Telegram message" fast path
        # the presence-gate design requires.
        if (-not (Get-AfkState -StateDir $stateDir)) {
            [Console]::In.ReadToEnd() | Out-Null
            exit 0
        }

        $raw = [Console]::In.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $decision = @{ decision = 'deny'; reason = 'remote-approval: empty hook input while AFK' }
        } else {
            $payload = $raw | ConvertFrom-Json
            $decision = Invoke-DualApproval -Payload $payload -StateDir $stateDir
        }
    } catch {
        try { Write-ApprovalLog $stateDir "FAIL entrypoint $($_.Exception.Message)" } catch { }
        $decision = @{ decision = 'deny'; reason = 'remote-approval: unexpected error, failing closed' }
    }

    if ($null -eq $decision) {
        exit 0
    }

    $out = @{
        hookSpecificOutput = @{
            hookEventName  = 'PermissionRequest'
            decision       = $decision.decision
            decisionReason = $decision.reason
        }
    } | ConvertTo-Json -Compress -Depth 6
    Write-Output $out
    exit 0
}

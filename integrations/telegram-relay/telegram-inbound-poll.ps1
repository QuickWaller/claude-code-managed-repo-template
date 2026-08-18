<#
  telegram-inbound-poll.ps1 - ONE poll of the relay bot's inbox. Prints any
  new operator messages to stdout, one per line, then exits.

  ASCII ONLY, deliberately. An earlier version of this file used em-dashes
  and was written UTF-8 without a BOM; Windows PowerShell 5.1 reads a
  BOM-less .ps1 as ANSI, turned them into mojibake, and the parser failed
  with a cascade of errors that pointed at innocent lines. Keep every
  character in this file 7-bit ASCII, or add a BOM.

  Built at the operator's explicit request ("set an inbound loop for me"),
  after a live demonstration of the gap: the operator sent a message from
  their phone, it was never seen, and it only surfaced because someone
  happened to poll by hand later. See ../README.md for the design notes and
  the blockers this had to solve.

  ## Why a single-shot script and not a daemon

  The caller supplies the loop (e.g. a `while true; do ...; sleep 30; done`
  from whatever your harness's own background/monitor mechanism is), so each
  poll is an independent process. A crash, a hung TLS handshake or a
  malformed response costs one tick, not the channel. It also means the
  whole thing stops when the session stops - no orphaned poller left running
  against the operator's bot after the session exits.

  ## The offset contract - the load-bearing constraint

  Telegram's getUpdates is a SINGLE-CONSUMER contract per bot token, and
  remote-approval.ps1 already depends on that: it deliberately never passes
  an "offset" (see its own comment) so concurrent hook instances cannot
  consume each other's view of the backlog. This script MUST NOT break that.

  So it never passes "offset" either. It tracks its own high-water update_id
  in a local mark file and filters client-side. Consequence, accepted
  knowingly: Telegram keeps returning the same backlog (its own ~24h/100-
  update retention is what eventually clears it), and this script re-filters
  it every tick. That is a few KB per poll in exchange for not interfering
  with approvals.

  ## Why the first run is deliberately silent about history

  A poller that started from zero on a bot with an existing backlog would
  replay old messages (including old approval replies) into a live session
  as if the operator had just sent them. That is a real hazard, not a
  cosmetic one, so a first run with no mark file SEEDS to the current
  maximum update_id and reports only how many it skipped.

  ## Trust boundary - read this before widening anything

  Messages are filtered to the operator's own DEV_RELAY_CHAT_ID. Anyone
  holding the bot token can still send into that chat, so this is a
  convenience filter, not authentication. Output is surfaced to the model as
  INPUT TO CONSIDER, never auto-executed: it still applies its own judgement,
  and anything gated (destructive or hard-to-reverse) still needs real
  confirmation. Do not "improve" this into an auto-execute channel without
  an explicit, recorded decision.

  Exit code is always 0. A notifier that can break the session is worse than
  no notifier - the same rule notify-telegram.ps1 follows.
#>

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

$stateDir = Join-Path $env:TEMP 'claude-notify'
if (-not (Test-Path $stateDir)) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
}
$markFile = Join-Path $stateDir 'inbound.mark'
$failFile = Join-Path $stateDir 'inbound.failing'

# Credentials: same source as notify-telegram.ps1 and remote-approval.ps1.
$token  = $null
$chatId = $null
try {
    $envFile = Join-Path $env:USERPROFILE '.claude\notify.env'
    foreach ($line in (Get-Content -Path $envFile -ErrorAction Stop)) {
        if ($line -match '^\s*DEV_RELAY_BOT_TOKEN\s*=\s*(.+?)\s*$') { $token  = $Matches[1] }
        if ($line -match '^\s*DEV_RELAY_CHAT_ID\s*=\s*(.+?)\s*$')   { $chatId = $Matches[1] }
    }
} catch { }

if (-not $token -or -not $chatId) {
    # One line, then stay quiet - the loop would otherwise repeat this forever.
    if (-not (Test-Path $failFile)) {
        Set-Content -Path $failFile -Value 'no-creds' -Encoding utf8
        Write-Output 'telegram-inbound: no credentials in ~/.claude/notify.env, poller is inert'
    }
    exit 0
}

try {
    $uri  = "https://api.telegram.org/bot" + $token + "/getUpdates?timeout=0"
    $resp = Invoke-RestMethod -Uri $uri -TimeoutSec 20 -ErrorAction Stop
    if (-not $resp.ok) { throw 'getUpdates returned ok=false' }
} catch {
    # Report only once a streak reaches $reportAt CONSECUTIVE failures, then
    # stay quiet until it recovers.
    #
    # Reporting the first failure of any streak is too eager in practice: a
    # single tick's TLS timeout can happen while the channel is in fact
    # working fine on either side of it. A blip that self-heals on the next
    # tick 30s later is not news; a channel that is actually down is.
    # Telegram 409s from remote-approval.ps1 polling concurrently are
    # expected under the shared-token/no-offset design and land in the same
    # category.
    #
    # Still fail-visible, deliberately: this is NOT a return to swallowing
    # errors. A genuinely broken poller crosses the threshold within ~90s and
    # says so. Silence must never be the way breakage presents itself - a
    # broken interpreter path piped to a null redirect, with the loop failing
    # every tick and emitting absolutely nothing, is exactly the failure mode
    # this design is written against.
    $reportAt = 3
    $streak = 0
    if (Test-Path $failFile) {
        try { $streak = [int](Get-Content -Path $failFile -Raw).Trim() } catch { $streak = 0 }
    }
    $streak = $streak + 1
    Set-Content -Path $failFile -Value $streak -Encoding utf8
    if ($streak -eq $reportAt) {
        $msg = $_.Exception.Message
        Write-Output ('telegram-inbound: poll failing ' + $streak + 'x consecutively (' + $msg + '), staying quiet until it recovers')
    }
    exit 0
}
# Any success clears the streak, so the next report needs a fresh $reportAt in a row.
Remove-Item -Path $failFile -Force -ErrorAction SilentlyContinue

$updates = @($resp.result)
if ($updates.Count -eq 0) { exit 0 }

$maxId = ($updates | ForEach-Object { [int64]$_.update_id } | Measure-Object -Maximum).Maximum

# First run: seed to the current high-water mark, do not replay history.
if (-not (Test-Path $markFile)) {
    Set-Content -Path $markFile -Value $maxId -Encoding utf8
    $n = $updates.Count
    Write-Output ('telegram-inbound: armed, skipped ' + $n + ' pre-existing update/s, watching for new messages only')
    exit 0
}

$mark = 0
try { $mark = [int64](Get-Content -Path $markFile -Raw).Trim() } catch { $mark = 0 }

foreach ($u in ($updates | Sort-Object { [int64]$_.update_id })) {
    $uid = [int64]$u.update_id
    if ($uid -le $mark) { continue }

    $m = $u.message
    if (-not $m) { continue }

    # Operator's own chat only. See the trust-boundary note in the header.
    $from = [string]$m.chat.id
    if ($from -ne [string]$chatId) { continue }

    $text = [string]$m.text
    if ([string]::IsNullOrWhiteSpace($text)) { $text = '(non-text message)' }
    # One line per message - a typical monitor loop turns each stdout line
    # into one event.
    $text = ($text -replace '\r?\n', ' / ')
    Write-Output ('TELEGRAM FROM OPERATOR: ' + $text)
}

if ($maxId -gt $mark) { Set-Content -Path $markFile -Value $maxId -Encoding utf8 }
exit 0

<#
  remote-approval.tests.ps1 — proves remote-approval.ps1 fails closed on
  every error/timeout path, and behaves correctly on the happy paths.

  Run: powershell -NoProfile -ExecutionPolicy Bypass -File remote-approval.tests.ps1

  No test framework dependency — plain assert-and-count, deliberately, to
  avoid drift risk against whatever Pester version happens to be installed.

  Three test styles:
    1. In-process (dot-sourced, REMOTE_APPROVAL_TEST_MODE=1): unit tests
       against the real Test-ReplyMatch / Get-RequestNonce / Get-AfkState
       functions, plus Invoke-RemoteApproval with the real Telegram-calling
       functions SHADOWED by fakes (no network) — proves the decision logic
       and the self-deadline timing without needing a live human reply.
    2. Subprocess (real `powershell -File remote-approval.ps1 < payload`):
       exercises the true entry point exactly as a harness will invoke it,
       with $env:USERPROFILE/$env:TEMP pointed at an isolated fake home so
       nothing here ever touches the real ~/.claude/notify.env or the real
       afk.state.
    3. One real live network round-trip against the REAL relay bot
       (credentials from the real ~/.claude/notify.env) with a short
       self-deadline override, proving send + poll + timeout-deny works for
       real, not just against fakes. Sends exactly one Telegram message,
       clearly labelled as a test.
#>

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$hooksDir  = Split-Path -Parent $scriptDir
$targetScript = Join-Path $hooksDir 'remote-approval.ps1'
$ps = "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

$script:pass = 0
$script:fail = 0

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { $script:pass++; Write-Output "PASS: $Name" }
    else            { $script:fail++; Write-Output "FAIL: $Name" }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    if ($Expected -eq $Actual) { $script:pass++; Write-Output "PASS: $Name" }
    else { $script:fail++; Write-Output "FAIL: $Name (expected '$Expected', got '$Actual')" }
}

Write-Output "=== 1. In-process unit tests (dot-sourced, no network) ==="
$env:REMOTE_APPROVAL_TEST_MODE = '1'
. $targetScript

# --- Test-ReplyMatch matrix ---------------------------------------------
$chatId = '8729820393'
$sentId = [Int64]555
$nonce  = 'AB12CD'
$startUnix = [Int64]1000000

function New-Update {
    param($ChatId = $chatId, $Text = 'allow', $Date = ($startUnix + 10), $ReplyToId = $null, $MsgId = 999)
    $msg = [pscustomobject]@{
        message_id = $MsgId
        chat       = [pscustomobject]@{ id = $ChatId }
        date       = $Date
        text       = $Text
    }
    if ($ReplyToId) {
        $msg | Add-Member -NotePropertyName reply_to_message -NotePropertyValue ([pscustomobject]@{ message_id = $ReplyToId })
    }
    return [pscustomobject]@{ update_id = 1; message = $msg }
}

Assert-Equal 'allow' (Test-ReplyMatch -Update (New-Update -Text 'allow' -ReplyToId $sentId) -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'reply-to + "allow" -> allow'
Assert-Equal 'allow' (Test-ReplyMatch -Update (New-Update -Text 'Yes' -ReplyToId $sentId) -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'reply-to + "Yes" -> allow'
Assert-Equal 'deny'  (Test-ReplyMatch -Update (New-Update -Text 'deny' -ReplyToId $sentId) -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'reply-to + "deny" -> deny'
Assert-Equal 'deny'  (Test-ReplyMatch -Update (New-Update -Text 'no thanks' -ReplyToId $sentId) -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'reply-to + "no thanks" -> deny'
Assert-Equal $null   (Test-ReplyMatch -Update (New-Update -Text 'maybe??' -ReplyToId $sentId) -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'reply-to + ambiguous text -> no match (keep waiting, not a guess)'
Assert-Equal $null   (Test-ReplyMatch -Update (New-Update -Text 'yes' -ReplyToId 12345) -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'reply-to a DIFFERENT message -> no match'
Assert-Equal $null   (Test-ReplyMatch -Update (New-Update -ChatId '999999999' -Text 'allow' -ReplyToId $sentId) -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'wrong chat id, even with correct reply-to+text -> ignored'
Assert-Equal 'allow' (Test-ReplyMatch -Update (New-Update -Text "allow $nonce") -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'fresh msg "allow <nonce>" (no reply-to) -> allow'
Assert-Equal 'deny'  (Test-ReplyMatch -Update (New-Update -Text "deny $nonce") -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'fresh msg "deny <nonce>" (no reply-to) -> deny'
Assert-Equal $null   (Test-ReplyMatch -Update (New-Update -Text 'allow') -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'bare "allow", no reply-to, no nonce, SolePending default(false) -> NOT accepted (would be ambiguous across queued requests)'
Assert-Equal $null   (Test-ReplyMatch -Update (New-Update -Text "allow ZZ9999") -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'nonce for a DIFFERENT pending request -> ignored, not matched to this one'
Assert-Equal $null   (Test-ReplyMatch -Update (New-Update -Text 'allow' -Date ($startUnix - 500)) -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'stale message predating this request -> ignored'
Assert-Equal $null   (Test-ReplyMatch -Update ([pscustomobject]@{ update_id = 1 }) -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix) 'update with no .message field (e.g. edited_message) -> no match, no throw'

# --- Test-ReplyMatch: bare allow/deny gated on -SolePending ---
Assert-Equal 'allow' (Test-ReplyMatch -Update (New-Update -Text 'allow') -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix -SolePending $true) 'bare "allow", no reply-to, no nonce, SolePending=true -> allow'
Assert-Equal 'allow' (Test-ReplyMatch -Update (New-Update -Text 'Allow') -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix -SolePending $true) 'bare "Allow" (mixed case), SolePending=true -> allow'
Assert-Equal 'allow' (Test-ReplyMatch -Update (New-Update -Text 'yes') -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix -SolePending $true) 'bare "yes", SolePending=true -> allow'
Assert-Equal 'deny'  (Test-ReplyMatch -Update (New-Update -Text 'deny') -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix -SolePending $true) 'bare "deny", SolePending=true -> deny'
Assert-Equal 'deny'  (Test-ReplyMatch -Update (New-Update -Text 'no') -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix -SolePending $true) 'bare "no", SolePending=true -> deny'
Assert-Equal $null   (Test-ReplyMatch -Update (New-Update -Text 'allow me to explain') -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix -SolePending $true) 'sentence merely starting with "allow" (not a reply-to) -> NOT accepted even when sole-pending (whole-message anchor, no structural proof it was meant as an answer)'
Assert-Equal $null   (Test-ReplyMatch -Update (New-Update -Text 'I am not sure') -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix -SolePending $true) 'unrelated bare text, SolePending=true -> still no match (not allow/deny wording)'
Assert-Equal $null   (Test-ReplyMatch -Update (New-Update -Text 'allow' -Date ($startUnix - 500)) -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix -SolePending $true) 'bare "allow" predating this request, SolePending=true -> still rejected as stale'
Assert-Equal $null   (Test-ReplyMatch -Update (New-Update -ChatId '999999999' -Text 'allow') -ChatId $chatId -SentMessageId $sentId -Nonce $nonce -RequestStartUnix $startUnix -SolePending $true) 'bare "allow" from wrong chat id, SolePending=true -> still ignored'

# --- Test-SolePendingRequest (marker files) ---
$markerDir = Join-Path $env:TEMP "rat-markers-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $markerDir -Force | Out-Null

Assert-Equal $false (Test-SolePendingRequest -StateDir $markerDir -Nonce $nonce) 'no marker files at all -> not sole (0 != 1)'

New-PendingMarker -StateDir $markerDir -Nonce $nonce
Assert-Equal $true  (Test-SolePendingRequest -StateDir $markerDir -Nonce $nonce) 'exactly one live marker, and it is mine -> sole'
Assert-Equal $false (Test-SolePendingRequest -StateDir $markerDir -Nonce 'OTHERNC') 'exactly one live marker, but a DIFFERENT nonce asks -> not sole for them'

New-PendingMarker -StateDir $markerDir -Nonce 'SECOND1'
Assert-Equal $false (Test-SolePendingRequest -StateDir $markerDir -Nonce $nonce) 'two live markers -> ambiguous, not sole for either'
Assert-Equal $false (Test-SolePendingRequest -StateDir $markerDir -Nonce 'SECOND1') 'two live markers -> ambiguous, not sole for either (other direction)'

Remove-PendingMarker -StateDir $markerDir -Nonce 'SECOND1'
Assert-Equal $true  (Test-SolePendingRequest -StateDir $markerDir -Nonce $nonce) 'after the second marker is removed, back to sole for the remaining one'

Remove-PendingMarker -StateDir $markerDir -Nonce $nonce
Assert-Equal $false (Test-SolePendingRequest -StateDir $markerDir -Nonce $nonce) 'after its own marker is removed too -> not sole (0 markers)'

# Stale marker (simulates a killed/crashed instance that never reached its
# own finally-block cleanup): backdate the file's LastWriteTime well past a
# short MaxAgeSeconds and confirm it is ignored, not treated as live.
New-PendingMarker -StateDir $markerDir -Nonce 'STALE01'
$staleFile = Get-PendingMarkerPath -StateDir $markerDir -Nonce 'STALE01'
(Get-Item $staleFile).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddSeconds(-9999)
New-PendingMarker -StateDir $markerDir -Nonce $nonce   # one fresh marker alongside the stale one
Assert-Equal $true  (Test-SolePendingRequest -StateDir $markerDir -Nonce $nonce -MaxAgeSeconds 60) 'a stale marker (backdated far past MaxAgeSeconds) does not count -> fresh one is still sole'
Assert-Equal $false (Test-SolePendingRequest -StateDir $markerDir -Nonce $nonce -MaxAgeSeconds 99999) 'the SAME stale marker, with a MaxAgeSeconds wide enough to include it, correctly makes it ambiguous again -> proves the aging logic is really age-based, not identity-based'
Remove-Item -Recurse -Force $markerDir

# --- Get-RequestNonce ---
$n1 = Get-RequestNonce -ToolUseId 'toolu_01ABCDEFGHIJKLMNOP'
Assert-True ($n1.Length -eq 6) 'nonce derived from tool_use_id is 6 chars'
$n2 = Get-RequestNonce -ToolUseId ''
Assert-True ($n2.Length -eq 6) 'nonce for empty/missing tool_use_id still produces 6 chars (guid fallback)'

# --- ConvertTo-TruncatedText reused correctly (shared lib) ---
$long = ('word ' * 300).Trim()
$short = ConvertTo-TruncatedText -Text $long -MaxLength 50
Assert-True ($short.Length -le 60) 'ConvertTo-TruncatedText actually shortens long text'
Assert-True ($short.Contains('[...]')) 'truncation marker present'
Assert-Equal 'short text' (ConvertTo-TruncatedText -Text 'short text' -MaxLength 900) 'text under budget is returned unchanged'

# --- Get-AfkState ---
$isoState = Join-Path $env:TEMP "rat-afkstate-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $isoState -Force | Out-Null
Assert-Equal $false (Get-AfkState -StateDir $isoState) 'no afk.state file -> off (safe default)'
Set-Content -Path (Join-Path $isoState 'afk.state') -Value 'on' -NoNewline -Encoding ascii
Assert-Equal $true (Get-AfkState -StateDir $isoState) 'afk.state = on -> on'
Set-Content -Path (Join-Path $isoState 'afk.state') -Value 'garbage' -NoNewline -Encoding ascii
Assert-Equal $false (Get-AfkState -StateDir $isoState) 'afk.state = unexpected content -> off (fail conservative, not on)'
Remove-Item -Recurse -Force $isoState

# --- Invoke-RemoteApproval with SHADOWED (faked) Telegram functions -------
# Redefining these after dot-sourcing shadows the real ones for every call
# made from here on in THIS process — no network, fully deterministic.
$isoState2 = Join-Path $env:TEMP "rat-invoke-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $isoState2 -Force | Out-Null
Set-Content -Path (Join-Path $isoState2 'afk.state') -Value 'on' -NoNewline -Encoding ascii

$fakePayload = [pscustomobject]@{
    tool_name    = 'Bash'
    tool_input   = [pscustomobject]@{ command = 'echo hi'; description = 'test' }
    tool_use_id  = 'toolu_TESTTESTTEST'
    cwd          = 'C:\fake\project'
}

# Case: credentials missing.
function Get-DevRelayCredentials { return $null }
$r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 5
Assert-Equal 'deny' $r.decision 'missing credentials -> deny'
Assert-True ($r.reason -match 'credentials') 'missing-credentials reason mentions credentials'

# Restore fake-but-present credentials for the rest of the shadowed tests.
function Get-DevRelayCredentials { return @{ Token = 'FAKE:NOTREAL'; ChatId = $chatId } }

# Case: send itself fails.
function Send-TelegramApiMessage { param($Token,$ChatId,$Text) throw 'simulated send failure' }
$r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 5
Assert-Equal 'deny' $r.decision 'sendMessage throwing -> deny'

# Case: send succeeds, nobody ever replies -> must deny via self-deadline,
# and must actually have WAITED roughly the deadline (proves it isn't a
# no-op return, i.e. proves the self-deadline mechanism itself runs).
function Send-TelegramApiMessage { param($Token,$ChatId,$Text) return [Int64]777 }
function Get-TelegramApiUpdates { param($Token) return @() }
# DeadlineSeconds=5 -> buffer=floor(5/3)=1 -> poll window=4s (see the
# matching comment in remote-approval.ps1's Invoke-RemoteApproval).
$swStart = Get-Date
$r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 5 -PollIntervalSeconds 1
$elapsed = ((Get-Date) - $swStart).TotalSeconds
Assert-Equal 'deny' $r.decision 'no reply ever -> deny (fail-closed-on-timeout, THE critical property)'
Assert-True ($r.reason -match 'deadline') 'timeout-deny reason says so'
Assert-True ($elapsed -ge 3) "self-deadline actually elapsed real time before denying (elapsed=$([math]::Round($elapsed,1))s, expected ~4s poll window)"
Assert-True ($elapsed -lt 10) "self-deadline did not hang far past its own budget (elapsed=$([math]::Round($elapsed,1))s)"

# Case: wrong chat id in every incoming update -> never matches, still denies via timeout.
function Get-TelegramApiUpdates {
    param($Token)
    return @([pscustomobject]@{ update_id = 1; message = [pscustomobject]@{ message_id = 1; chat = [pscustomobject]@{ id = '111111111' }; date = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); text = 'allow' } })
}
$r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 4 -PollIntervalSeconds 1
Assert-Equal 'deny' $r.decision 'replies from a non-operator chat id are ignored -> still denies at deadline'

# Case: a valid matching reply arrives -> allow.
function Get-TelegramApiUpdates {
    param($Token)
    return @([pscustomobject]@{ update_id = 1; message = [pscustomobject]@{ message_id = 1; chat = [pscustomobject]@{ id = $chatId }; date = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); text = 'allow'; reply_to_message = [pscustomobject]@{ message_id = 777 } } })
}
$r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 10 -PollIntervalSeconds 1
Assert-Equal 'allow' $r.decision 'a genuine matching reply -> allow, returns promptly (not waiting for deadline)'

# Case: a valid matching deny reply arrives -> deny.
function Get-TelegramApiUpdates {
    param($Token)
    return @([pscustomobject]@{ update_id = 1; message = [pscustomobject]@{ message_id = 1; chat = [pscustomobject]@{ id = $chatId }; date = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); text = 'deny'; reply_to_message = [pscustomobject]@{ message_id = 777 } } })
}
$r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 10 -PollIntervalSeconds 1
Assert-Equal 'deny' $r.decision 'a genuine matching deny reply -> deny'

# Case: bare "allow" (no reply-to, no nonce) is accepted end-to-end when it is
# genuinely the ONLY pending request — this is the sole-pending bare-reply
# fix under real end-to-end exercise, not just the pure-function test above.
# isoState2 has no leftover marker files at this point (every prior case
# above cleaned up its own via Invoke-RemoteApproval's finally block), so
# this instance's own marker is the only one that will exist while it polls.
$testNonce = Get-RequestNonce -ToolUseId $fakePayload.tool_use_id
function Get-TelegramApiUpdates {
    param($Token)
    return @([pscustomobject]@{ update_id = 1; message = [pscustomobject]@{ message_id = 1; chat = [pscustomobject]@{ id = $chatId }; date = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); text = 'allow' } })
}
$r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 10 -PollIntervalSeconds 1
Assert-Equal 'allow' $r.decision 'sole-pending bare "allow", no reply-to, no nonce, genuinely sole pending -> allow'
Assert-Equal $false (Test-Path (Get-PendingMarkerPath -StateDir $isoState2 -Nonce $testNonce)) 'marker cleaned up after a matched reply (finally ran)'

# Case: a SECOND pending request's marker is sitting in the same state dir
# (simulating another AFK-on hook instance genuinely mid-poll right now) ->
# the same bare "allow" must NOT be accepted; only the nonce form still
# works. This is the safety half of the fix: widen only when provably safe.
New-PendingMarker -StateDir $isoState2 -Nonce 'OTHRPND'
try {
    function Get-TelegramApiUpdates {
        param($Token)
        return @([pscustomobject]@{ update_id = 1; message = [pscustomobject]@{ message_id = 1; chat = [pscustomobject]@{ id = $chatId }; date = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); text = 'allow' } })
    }
    $r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 4 -PollIntervalSeconds 1
    Assert-Equal 'deny' $r.decision 'two pending markers present: bare "allow" NOT accepted -> denies via timeout, not a false allow'
    Assert-True ($r.reason -match 'deadline') 'two-pending timeout-deny reason says so (proves it fell through to the deadline, not a silent match)'

    function Get-TelegramApiUpdates {
        param($Token)
        return @([pscustomobject]@{ update_id = 1; message = [pscustomobject]@{ message_id = 1; chat = [pscustomobject]@{ id = $chatId }; date = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); text = "allow $testNonce" } })
    }
    $r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 10 -PollIntervalSeconds 1
    Assert-Equal 'allow' $r.decision 'two pending markers present: the nonce form ("allow <nonce>") still works, unaffected by the ambiguity'
} finally {
    Remove-PendingMarker -StateDir $isoState2 -Nonce 'OTHRPND'
}

# Case: a killed instance's marker (backdated far past its own deadline+30s)
# does not permanently wedge bare replies for a fresh request that comes
# after it — proves stale markers age out rather than accumulating forever.
New-PendingMarker -StateDir $isoState2 -Nonce 'DEADONE'
(Get-Item (Get-PendingMarkerPath -StateDir $isoState2 -Nonce 'DEADONE')).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddSeconds(-9999)
try {
    function Get-TelegramApiUpdates {
        param($Token)
        return @([pscustomobject]@{ update_id = 1; message = [pscustomobject]@{ message_id = 1; chat = [pscustomobject]@{ id = $chatId }; date = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); text = 'allow' } })
    }
    $r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 10 -PollIntervalSeconds 1
    Assert-Equal 'allow' $r.decision 'a stale/abandoned marker from a killed instance does not wedge bare-reply matching for a fresh request'
} finally {
    Remove-PendingMarker -StateDir $isoState2 -Nonce 'DEADONE'
}

# Case: send fails -> no marker is ever created for a request that never
# reached Telegram (a failed send has no business claiming "sole pending").
function Send-TelegramApiMessage { param($Token,$ChatId,$Text) throw 'simulated send failure' }
$r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 5
Assert-Equal 'deny' $r.decision 'send failure still denies (sanity re-check after marker changes)'
Assert-Equal $false (Test-Path (Get-PendingMarkerPath -StateDir $isoState2 -Nonce $testNonce)) 'no marker left behind when the send itself failed'
function Send-TelegramApiMessage { param($Token,$ChatId,$Text) return [Int64]777 }

# Case: AFK off -> no decision at all (Invoke-RemoteApproval called directly).
Set-Content -Path (Join-Path $isoState2 'afk.state') -Value 'off' -NoNewline -Encoding ascii
function Get-TelegramApiUpdates { param($Token) throw 'must never be called when AFK is off' }
function Send-TelegramApiMessage { param($Token,$ChatId,$Text) throw 'must never be called when AFK is off' }
$r = Invoke-RemoteApproval -Payload $fakePayload -StateDir $isoState2 -DeadlineSeconds 5
Assert-Equal $null $r 'AFK off -> $null (no decision), and Telegram functions never invoked'

Remove-Item -Recurse -Force $isoState2
Remove-Item Env:\REMOTE_APPROVAL_TEST_MODE

Write-Output ""
Write-Output "=== 2. Subprocess tests (real entry point, isolated fake $env:USERPROFILE/$env:TEMP) ==="

$testHome = Join-Path $env:TEMP "rat-subproc-home-$([guid]::NewGuid().ToString('N'))"
$testTemp = Join-Path $env:TEMP "rat-subproc-temp-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path (Join-Path $testHome '.claude') -Force | Out-Null
New-Item -ItemType Directory -Path $testTemp -Force | Out-Null
# Clearly-fake credentials — never the real ones, never printed.
@"
DEV_RELAY_BOT_TOKEN=000000000:FAKE-TEST-TOKEN-NOT-REAL-DO-NOT-USE
DEV_RELAY_CHAT_ID=111222333
"@ | Set-Content -Path (Join-Path $testHome '.claude\notify.env') -Encoding ascii

$origUserProfile = $env:USERPROFILE
$origTemp = $env:TEMP
$env:USERPROFILE = $testHome
$env:TEMP = $testTemp

function Invoke-HookSubprocess {
    param([string]$Stdin)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ps
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$targetScript`""
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.EnvironmentVariables['USERPROFILE'] = $testHome
    $psi.EnvironmentVariables['TEMP'] = $testTemp
    $psi.EnvironmentVariables['TMP'] = $testTemp
    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($Stdin) { $proc.StandardInput.Write($Stdin) }
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit(30000) | Out-Null
    return [pscustomobject]@{ Stdout = $stdout; Stderr = $stderr; ExitCode = $proc.ExitCode }
}

# --- AFK off: real subprocess, real (fake-but-present) creds, must be a total no-op ---
if (Test-Path (Join-Path $testTemp 'claude-notify\afk.state')) { Remove-Item -Force (Join-Path $testTemp 'claude-notify\afk.state') }
$payloadJson = (@{ hook_event_name = 'PermissionRequest'; tool_name = 'Bash'; tool_input = @{ command = 'echo hi' }; tool_use_id = 'toolu_ABCDEF123456'; cwd = 'C:\proj'; session_id = 'sess1' } | ConvertTo-Json -Compress)
$res = Invoke-HookSubprocess -Stdin $payloadJson
Assert-Equal 0 $res.ExitCode 'AFK-off subprocess: exit code 0'
Assert-Equal '' ($res.Stdout.Trim()) 'AFK-off subprocess: empty stdout (no decision printed -> native prompt renders unchanged)'
$logPath = Join-Path $testTemp 'claude-notify\remote-approval.log'
Assert-Equal $false (Test-Path $logPath) 'AFK-off subprocess: no remote-approval.log created at all -> proves no Telegram attempt was made'

# --- AFK on + malformed JSON stdin -> deny ---
New-Item -ItemType Directory -Path (Join-Path $testTemp 'claude-notify') -Force | Out-Null
Set-Content -Path (Join-Path $testTemp 'claude-notify\afk.state') -Value 'on' -NoNewline -Encoding ascii
$res = Invoke-HookSubprocess -Stdin 'this is not { valid json'
Assert-Equal 0 $res.ExitCode 'malformed-stdin subprocess: exit code 0 (never a nonzero crash)'
Assert-True ($res.Stdout -match '"decision"\s*:\s*"deny"') 'malformed-stdin subprocess: stdout is an explicit deny'
Assert-True ($res.Stdout -match '"hookEventName"\s*:\s*"PermissionRequest"') 'malformed-stdin subprocess: correct hookEventName in output'

# --- AFK on + empty stdin -> deny ---
$res = Invoke-HookSubprocess -Stdin ''
Assert-True ($res.Stdout -match '"decision"\s*:\s*"deny"') 'empty-stdin subprocess (AFK on): explicit deny'

# --- AFK on + real payload, but bad token -> real network call, real failure -> deny ---
# (Fake token IS syntactically token-shaped so this hits the real Telegram API
# and gets a real error response — proves the HTTP-failure path for real,
# without touching real credentials.)
$res = Invoke-HookSubprocess -Stdin $payloadJson
Assert-True ($res.Stdout -match '"decision"\s*:\s*"deny"') 'AFK on + invalid token subprocess: real network call fails closed -> deny'
Assert-True ($res.Stdout -notmatch 'FAKE-TEST-TOKEN') 'AFK on + invalid token subprocess: token value never echoed into output'

$env:USERPROFILE = $origUserProfile
$env:TEMP = $origTemp
Remove-Item -Recurse -Force $testHome
Remove-Item -Recurse -Force $testTemp

Write-Output ""
Write-Output "=== 3. Real live network round-trip (real relay bot, short deadline) ==="
Write-Output "Sends ONE real Telegram message labelled as a test; proves send+poll+timeout-deny for real."
Write-Output "Requires a real ~/.claude/notify.env with DEV_RELAY_BOT_TOKEN/DEV_RELAY_CHAT_ID to do anything."
$env:REMOTE_APPROVAL_TEST_MODE = '1'
# Re-dot-source so the REAL Send-TelegramApiMessage/Get-TelegramApiUpdates
# (not the fakes shadowed in section 1) are what's called below.
. $targetScript
$realStateDir = Join-Path $env:TEMP 'claude-notify'
$prevAfk = $null
if (Test-Path (Join-Path $realStateDir 'afk.state')) { $prevAfk = Get-Content (Join-Path $realStateDir 'afk.state') -Raw }
Set-Content -Path (Join-Path $realStateDir 'afk.state') -Value 'on' -NoNewline -Encoding ascii

$livePayload = [pscustomobject]@{
    tool_name   = 'Bash'
    tool_input  = [pscustomobject]@{ command = 'echo remote-approval-live-test'; description = 'automated fail-closed proof, no action needed' }
    tool_use_id = 'toolu_LIVETEST999999'
    cwd         = 'C:\projects\example-app'
}
$liveStart = Get-Date
$liveResult = Invoke-RemoteApproval -Payload $livePayload -StateDir $realStateDir -DeadlineSeconds 25 -PollIntervalSeconds 3
$liveElapsed = ((Get-Date) - $liveStart).TotalSeconds

if ($prevAfk) { Set-Content -Path (Join-Path $realStateDir 'afk.state') -Value $prevAfk -NoNewline -Encoding ascii }
else { Remove-Item -Force (Join-Path $realStateDir 'afk.state') -ErrorAction SilentlyContinue }

Assert-True ($liveResult -ne $null) 'live test: got a real decision object back (not a crash/null)'
Assert-True (@('allow','deny') -contains $liveResult.decision) 'live test: decision is allow or deny'
if ($liveResult.decision -eq 'deny' -and $liveResult.reason -match 'deadline') {
    # DeadlineSeconds=25 -> buffer=floor(25/3)=8 -> poll window=17s.
    Assert-True ($liveElapsed -ge 14) "live test: nobody replied, so it genuinely waited out the self-deadline before denying (elapsed=$([math]::Round($liveElapsed,1))s, expected ~17s poll window)"
    Write-Output "  (no live reply arrived within the window - this is the expected/normal outcome for an unattended run and IS the fail-closed proof)"
} else {
    Write-Output "  (a real reply was matched during the test window: decision=$($liveResult.decision) elapsed=$([math]::Round($liveElapsed,1))s)"
}

Remove-Item Env:\REMOTE_APPROVAL_TEST_MODE

Write-Output ""
Write-Output "=== SUMMARY: $script:pass passed, $script:fail failed ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }

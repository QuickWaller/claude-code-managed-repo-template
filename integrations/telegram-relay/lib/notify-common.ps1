<#
  notify-common.ps1 — small shared helpers used by BOTH notify-telegram.ps1
  and remote-approval.ps1. Dot-sourced by both, never run directly.

  Extracted so the word-boundary truncation and the relay-bot credential read
  exist in exactly one place instead of two drifting copies.

  Deliberately does NOT touch ~/.claude/settings.json in any way — this file
  only exists in this module and is loaded via dot-sourcing a path relative
  to $PSScriptRoot. See ../README.md for how to wire the module in.
#>

# Cuts $Text to at most $MaxLength characters, snapping back to the last
# space so the cut never lands mid-word, and appends a visible ' [...]'
# marker (space-prefixed so it can never fuse onto a partial word). Returns
# $Text unchanged if it's already within budget.
#
# The 78% floor: if the last space is too far back, a mid-word hard cut is a
# smaller readability loss than throwing away a huge chunk of the message,
# so the hard cut is kept in that case.
function ConvertTo-TruncatedText {
    param(
        [string]$Text,
        [int]$MaxLength = 900
    )
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    if ($Text.Length -le $MaxLength) { return $Text }

    $cut = $Text.Substring(0, $MaxLength)
    $lastSpace = $cut.LastIndexOf(' ')
    $floor = [int]($MaxLength * 0.78)
    if ($lastSpace -gt $floor) { $cut = $cut.Substring(0, $lastSpace) }
    return $cut + ' [...]'
}

# Reads the relay bot's token/chat id from ~/.claude/notify.env.
# Returns $null if the file is missing or either value is blank/absent —
# callers must treat $null as "credentials unavailable" and act accordingly
# (notify-telegram.ps1 stays silent; remote-approval.ps1 must fail closed).
# Never writes the values anywhere; never throws.
function Get-DevRelayCredentials {
    try {
        $envFile = Join-Path $env:USERPROFILE '.claude\notify.env'
        if (-not (Test-Path $envFile)) { return $null }

        $token = $null; $chatId = $null
        foreach ($line in (Get-Content -Path $envFile)) {
            if ($line -match '^\s*DEV_RELAY_BOT_TOKEN\s*=\s*(.+?)\s*$') { $token  = $Matches[1] }
            if ($line -match '^\s*DEV_RELAY_CHAT_ID\s*=\s*(.+?)\s*$')   { $chatId = $Matches[1] }
        }
        if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($chatId)) { return $null }
        return @{ Token = $token; ChatId = $chatId }
    } catch {
        return $null
    }
}

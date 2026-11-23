# Teams call detection, one check per fixture row (test/teams-call.json). Plain asserts, one PASS or FAIL line per check. A child of
# test\run.ps1 (its FAIL lines count there). Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\teams-call.ps1
#
# The contract checked (the builder meets it): Test-TeamsCall $mic $wins -Agenda <agenda> -Now <clock>, in tray.ps1.
#   $mic: Get-MicUsage's reading, $null when the mic store cannot be read. $wins: Get-TeamsWindows' reading.
#   $Agenda: agenda.json's parsed text, the value Get-TodayAgenda takes; $null when there is no agenda file.
#   $Now: the clock. Every row is read against the same time, never the real one.
#   A Teams app holding the mic is a call whatever the agenda says.
#   A mic store that cannot be read: a Teams meeting window is a call only while the agenda shows an event now with its teams
#   flag set and showAs not free. With no agenda ($null) the window is a call, as it always was.
# A row with no agenda key has agenda $null.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
. (Join-Path $root 'tray.ps1') -Lib
$now = [datetime]'2026-11-20 10:00:00'
$cases = @(ConvertFrom-Json (Get-Content -Raw (Join-Path $PSScriptRoot 'teams-call.json')) | % { $_ })
Check 'tray: Teams call detection reads every fixture row (scope)' ($cases.Count -eq 25) "rows: $($cases.Count)"
# Get-TodayAgenda drops an event that does not parse, so a row whose events are dropped would pass for the wrong reason.
$unparsed = @($cases | ? { $_.agenda } | ? { @((Get-TodayAgenda $_.agenda $now)).Count -ne @($_.agenda.events).Count } | % { $_.case })
Check 'tray: every agenda row reads all its events (scope)' ($unparsed.Count -eq 0) ($unparsed -join '; ')
foreach ($c in $cases) {
  $got = [bool](Test-TeamsCall $c.mic $c.wins -Agenda $c.agenda -Now $now)
  Check "tray: call detection: $($c.case)" ($got -eq [bool]$c.call) "call: $got, expected $([bool]$c.call)"
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All teams-call checks passed.'; exit 0 }

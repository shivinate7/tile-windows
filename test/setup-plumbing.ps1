# Monitor setups (decision monitor-setups): the tray's display key. Plain asserts, one FAIL line per failing check. Its own file, run in a
# child powershell by test\run.ps1 (its FAIL lines count there). Touches no real profile: the run folder holds the profile.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\setup-plumbing.ps1
#
# The contract checked (the builder meets it):
#   Tray: the display key is the setup key, the sorted monitor ids joined by Get-TileSetupKey (config.ps1). A monitor set that is only
#   rearranged is the same setup, so it fires no display trigger (decision monitor-setups, item 4, coordinator default 2026-11-17 09:50
#   CST; that item departs from tray.ps1 Get-MonitorKey). Step-Tray counts the monitors in a key by its ids, not by a ';' split.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
# One case. An error inside it is one FAIL line, and the run goes on.
function Case([string]$name, [scriptblock]$body) { try { & $body } catch { $script:fail++; "FAIL  $name  threw: $($_.Exception.Message)" } }

# Run folder (test-temp-standard), as run-undo.ps1 keeps it: <TEMP>\tile-windows-test-runs\<pid>-<UUID>, removed at the end.
# The sweep of old run folders is stack-lock.ps1's.
$runRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
New-Item -ItemType Directory -Force $runRoot | Out-Null
$runDir = Join-Path $runRoot ("$PID-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory $runDir | Out-Null

# Strip what the code under test reads from the caller, and point the profile into the run folder.
$saved = @{ USERPROFILE = $env:USERPROFILE; APPDATA = $env:APPDATA; TILE_HOME = $env:TILE_HOME; TILE_SCREENS_FILE = $env:TILE_SCREENS_FILE }
$prof = Join-Path $runDir 'profile'; New-Item -ItemType Directory -Force (Join-Path $prof 'AppData\Roaming') | Out-Null
$env:USERPROFILE = $prof; $env:APPDATA = Join-Path $prof 'AppData\Roaming'; $env:TILE_HOME = $null; $env:TILE_SCREENS_FILE = $null

try {
  Add-Type -AssemblyName System.Drawing   # Rectangle for the monitor bounds; run.ps1 loads it earlier, a child does not
  . (Join-Path $root 'tray.ps1') -Lib   # Get-MonitorKey, Step-Tray, New-TrayState, and config.ps1 (Get-TileSetupKey)

  # A tray scene set: one scene per monitor count, each made for that count (the display trigger picks by count).
  $trayCfg = ConvertFrom-Json '{"scenes":[{"id":"one","name":"One","trigger":{"type":"display"},"auto":{"monitors":true},"screens":1},{"id":"two","name":"Two","trigger":{"type":"display"},"auto":{"monitors":true},"screens":2},{"id":"three","name":"Three","trigger":{"type":"display"},"auto":{"monitors":true},"screens":3}]}'
  $d = [datetime]'2026-10-20 10:00'   # a fixed time: the display trigger does not read the clock
  function Ids($x) { (@($x) | % { $_.id }) -join ',' }
  # The setup key of some monitor ids, through the product's own key function.
  function Key-Of([string[]]$ids) { Get-TileSetupKey @($ids | % { [pscustomobject]@{ id = $_ } }) }
  # A monitor as the tray's Get-MonitorKey reads it (DeviceName, Bounds) and as the setup key reads it (id).
  function New-TestScreen([string]$dev, [string]$id, [int]$x, [int]$y, [int]$w, [int]$h) {
    [pscustomobject]@{ DeviceName = $dev; Bounds = [Drawing.Rectangle]::new($x, $y, $w, $h); id = $id }
  }
  # The applied ids of one tick that follows a seeding tick with key $a (the first key only seeds, so it applies nothing).
  function Step-Pair([string]$a, [string]$b) { $ts = New-TrayState; $null = Step-Tray $ts $d $trayCfg $a $null ''; Ids (Step-Tray $ts $d $trayCfg $b $null '') }

  $k1 = Key-Of 'AUO1'; $k2 = Key-Of 'AUO1', 'DEL2'; $k3 = Key-Of 'AUO1', 'DEL2', 'LEN3'

  # Rearranged (decision item 4): the same three monitors in other places. The key the tray takes must not move with the bounds.
  $arrA = @((New-TestScreen 'DISPLAY1' 'LEN3' 0 1000 1536 960), (New-TestScreen 'DISPLAY2' 'AUO1' 1536 0 4096 1728), (New-TestScreen 'DISPLAY3' 'DEL2' 5632 0 1200 1920))
  $arrB = @((New-TestScreen 'DISPLAY1' 'LEN3' 0 1000 1536 960), (New-TestScreen 'DISPLAY2' 'AUO1' -4096 0 4096 1728), (New-TestScreen 'DISPLAY3' 'DEL2' -5296 0 1200 1920))
  Case 'tray: the rearranged set has the same monitor ids (scope)' {
    $idsA = (@($arrA.id) | Sort-Object) -join ','; $idsB = (@($arrB.id) | Sort-Object) -join ','
    Check 'tray: the rearranged set has the same monitor ids (scope)' ($idsA -ceq $idsB) "A: $idsA B: $idsB"
  }
  Case 'tray: the same monitors rearranged fire no display trigger' {
    $ts = New-TrayState; $null = Step-Tray $ts $d $trayCfg (Get-MonitorKey $arrA) $null ''
    $rr = Ids (Step-Tray $ts $d $trayCfg (Get-MonitorKey $arrB) $null '')
    Check 'tray: the same monitors rearranged fire no display trigger' ($rr -eq '') "applied: '$rr'"
  }

  # Added: the trigger fires (control), and the scene picked is the one made for the new count.
  Case 'tray: adding a monitor, 1 to 2, fires the display trigger (control)' {
    $up2 = Step-Pair $k1 $k2
    Check 'tray: adding a monitor, 1 to 2, fires the display trigger (control)' ($up2 -ne '') "applied: '$up2'"
    Check 'tray: a display key of two monitors applies the scene made for two' ($up2 -eq 'two') "applied: '$up2'"
  }
  Case 'tray: adding a monitor, 2 to 3, fires the display trigger (control)' {
    $up3 = Step-Pair $k2 $k3
    Check 'tray: adding a monitor, 2 to 3, fires the display trigger (control)' ($up3 -ne '') "applied: '$up3'"
    Check 'tray: a display key of three monitors applies the scene made for three' ($up3 -eq 'three') "applied: '$up3'"
  }
  # Removed: the trigger fires (control), and the scene picked is the one made for the smaller count.
  Case 'tray: removing a monitor, 3 to 2, fires the display trigger (control)' {
    $down2 = Step-Pair $k3 $k2
    Check 'tray: removing a monitor, 3 to 2, fires the display trigger (control)' ($down2 -ne '') "applied: '$down2'"
    Check 'tray: after a removal, a display key of two monitors applies the scene made for two' ($down2 -eq 'two') "applied: '$down2'"
  }
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All setup-plumbing checks passed.'; exit 0 }

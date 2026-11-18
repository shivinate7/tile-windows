# Monitor setups (decision monitor-setups): the tray's display key. Plain asserts, one FAIL line per failing check. Its own file, run in a
# child powershell by test\run.ps1 (its FAIL lines count there). Touches no real profile: the run folder holds the profile.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\setup-plumbing.ps1
#
# The contract checked (the builder meets it):
#   Tray: the display key is the setup key, the sorted monitor ids joined by Get-TileSetupKey (config.ps1). A monitor set that is only
#   rearranged is the same setup, so it fires no display trigger (decision monitor-setups, item 4, coordinator default 2026-11-17 09:50
#   CST; that item departs from tray.ps1 Get-MonitorKey). Step-Tray counts the monitors in a key by its ids, not by a ';' split.
#   Tray, a failed read: Read-Monitors (tray.ps1) on a failed tile.ps1 -Monitors returns no monitors or the last good set, never throws, and
#   never the Windows screen list (no ids, so its key differs). The tick passes Get-MonitorKey of it to Step-Tray: a failed read fires
#   no display trigger, and neither does the good read after it, for the same monitors.
#   Server (serve.ps1, -From snapshot, config in a case's own TILE_HOME):
#     GET  /snapshot  {monitors, windows, setup: {key, name, follows}}; the plugged-in setup is registered in config (first setup: Desk).
#     GET  /config    the config; GET /layouts: {<scene id>: Resolve-TileLayout's layout of that scene for the plugged-in setup}.
#     POST /layout    body {scene, key, layout}: 200 and stored when key is plugged in; 409 and no change when not.
#     POST /config    a whole config. The server keeps its monitors, setups and its layouts for every key, plugged in or not, whatever
#                     the body carries: POST /config writes no layout. Layouts are written only by POST /layout (409 for a key not plugged in).
#   A route the server lacks answers 404. On 31ea7c1 the /layout and /layouts cases are red for that reason: the route is not built.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tile = Join-Path $root 'tile.ps1'; $serve = Join-Path $root 'serve.ps1'
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
$servers = @()   # every server this file starts; the finally block stops what is still running

try {
  Add-Type -AssemblyName System.Drawing   # Rectangle for the monitor bounds; run.ps1 loads it earlier, a child does not
  . (Join-Path $root 'tray.ps1') -Lib   # Get-MonitorKey, Step-Tray, New-TrayState, and config.ps1 (Get-TileSetupKey)

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
  # A tray scene set: one scene per setup, each made on that setup (Use This Scene on This Setup, owner ruling Q4 A, 2026-11-17 09:47 CST).
  $trayCfg = ConvertFrom-Json ('{"scenes":[{"id":"one","name":"One","trigger":{"type":"display"},"auto":{"setup":true},"setupKey":"' + $k1 + '"},{"id":"two","name":"Two","trigger":{"type":"display"},"auto":{"setup":true},"setupKey":"' + $k2 + '"},{"id":"three","name":"Three","trigger":{"type":"display"},"auto":{"setup":true},"setupKey":"' + $k3 + '"}]}')

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

  # ---- Server: the setup on /snapshot, /layouts, /layout and POST /config ----
  # The plugged-in monitors, in the fixture's order (the fixture has no ids): DISPLAY1 laptop, DISPLAY2 wide, DISPLAY3 tall.
  $plugged = @(
    [pscustomobject]@{ id = 'LEN3'; name = 'Laptop'; builtin = $true; bw = 1536; bh = 960 },
    [pscustomobject]@{ id = 'AUO1'; name = 'Ultrawide'; builtin = $false; bw = 4096; bh = 1728 },
    [pscustomobject]@{ id = 'DEL2'; name = 'Portrait'; builtin = $false; bw = 1200; bh = 1920 })
  $snapObj = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixture.json'), $utf8))
  for ($i = 0; $i -lt $plugged.Count; $i++) {
    $snapObj.monitors[$i] | Add-Member -Force -NotePropertyName id -NotePropertyValue $plugged[$i].id
    $snapObj.monitors[$i] | Add-Member -Force -NotePropertyName builtin -NotePropertyValue $plugged[$i].builtin
  }
  $snapFile = Join-Path $runDir 'snap-ids.json'
  [IO.File]::WriteAllText($snapFile, (ConvertTo-Json -Depth 8 -Compress $snapObj), $utf8)

  # Helpers for the server cases. Every reply is a value (status and text), so a missing route is a FAIL line, not a throw.
  function Start-Child([string]$tileHome, [string]$argLine, [hashtable]$extra = @{}) {
    $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass $argLine"
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['USERPROFILE'] = $prof; $psi.EnvironmentVariables['APPDATA'] = Join-Path $prof 'AppData\Roaming'
    $psi.EnvironmentVariables['TILE_HOME'] = $tileHome; $psi.EnvironmentVariables['TILE_SCREENS_FILE'] = ''
    foreach ($k in $extra.Keys) { $psi.EnvironmentVariables[$k] = $extra[$k] }
    [Diagnostics.Process]::Start($psi)
  }
  # One child run to its end: its exit code and its stdout, without the WARNING lines the product writes to stderr.
  function Run-Child([string]$argLine, [hashtable]$extra = @{}) {
    $p = Start-Child '' $argLine $extra
    $out = $p.StandardOutput.ReadToEnd(); [void]$p.StandardError.ReadToEnd(); $p.WaitForExit()
    [pscustomobject]@{ code = $p.ExitCode; text = (@($out -split "`r?`n" | ? { $_ -notmatch '^WARNING:' }) -join "`n") }
  }
  # A dry-run server on the snapshot file, its config in $tileHome. Returns its process and tokened URL (its first line).
  function Start-Server([string]$tileHome, [string]$snapPath) {
    $p = Start-Child $tileHome "-File `"$serve`" -NoBrowser -From `"$snapPath`""
    $script:servers += $p
    [pscustomobject]@{ proc = $p; url = $p.StandardOutput.ReadLine() }
  }
  function Stop-Server($s) {
    if ($s.proc.HasExited) { return }
    try { [void](Invoke-WebRequest -UseBasicParsing "$($s.url)quit" -Method Post -Body 'quit') } catch {}
    if (-not $s.proc.WaitForExit(5000)) { $s.proc.Kill() }
  }
  function Get-Reply([string]$url) {
    try { $r = Invoke-WebRequest -UseBasicParsing $url; [pscustomobject]@{ code = [int]$r.StatusCode; text = [string]$r.Content } }
    catch { [pscustomobject]@{ code = [int]$_.Exception.Response.StatusCode; text = '' } }
  }
  function Send-Post([string]$url, [string]$body) {
    try { $r = Invoke-WebRequest -UseBasicParsing $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ($utf8.GetBytes($body)); [pscustomobject]@{ code = [int]$r.StatusCode; text = [string]$r.Content } }
    catch { [pscustomobject]@{ code = [int]$_.Exception.Response.StatusCode; text = '' } }
  }
  # Canonical JSON (keys sorted, arrays in order), as setup-config.ps1 has it: a value compares the same whatever order its file wrote.
  function Canon($o) {
    if ($null -eq $o) { return 'null' }
    if ($o -is [System.Management.Automation.PSCustomObject]) {
      $pairs = @($o.PSObject.Properties | Sort-Object Name | ForEach-Object { (ConvertTo-Json -Compress -InputObject $_.Name) + ':' + (Canon $_.Value) })
      return '{' + ($pairs -join ',') + '}'
    }
    if ($o -is [Array]) { $items = @($o); return '[' + ((@($items | ForEach-Object { Canon $_ })) -join ',') + ']' }
    return (ConvertTo-Json -Compress -InputObject $o)
  }
  # The config as a comparable value: the times a read moves (lastSeen, lastUsed) are left out.
  function Config-Shape([string]$text) {
    $c = ConvertFrom-Json $text
    if ($c.monitors) { foreach ($m in @($c.monitors.PSObject.Properties)) { [void]$m.Value.PSObject.Properties.Remove('lastSeen') } }
    if ($c.setups) { foreach ($s in @($c.setups.PSObject.Properties)) { [void]$s.Value.PSObject.Properties.Remove('lastUsed') } }
    Canon $c
  }
  function Keys-Of($o) { if ($null -eq $o) { '' } else { (@($o.PSObject.Properties.Name) | Sort-Object) -join ',' } }
  function Sorted([object[]]$ids) { (@($ids | ForEach-Object { [string]$_ }) | Sort-Object) -join ',' }

  $keyDesk = Key-Of 'AUO1', 'DEL2', 'LEN3'     # the plugged-in setup
  $keyOffice = Key-Of 'AUO1', 'DEL2'           # a setup the config knows, not plugged in
  $officeLayout = '{"grids":{"AUO1":{"c":2,"r":1}},"pins":[],"zones":[],"fill":{"mon":null,"held":[]},"bay":{}}'
  $layoutBody = '{"grids":{"AUO1":{"c":3,"r":1}},"pins":[],"zones":[],"fill":{"mon":null,"held":[]},"bay":{}}'
  $layoutEarlier = '{"grids":{"AUO1":{"c":1,"r":1}},"pins":[],"zones":[],"fill":{"mon":null,"held":[]},"bay":{}}'   # a Desk layout the server replaces

  # The config a case starts from: the starters (version 4), the plugged-in monitors with their Desk setup, an Office setup (not
  # plugged in), and an Office layout on the focus scene. $deskLayout, when given, is the plugged-in setup's layout on that scene too.
  # Written into $tileHome before its server starts. Returns the object it wrote.
  function Write-SeedConfig([string]$tileHome, [string]$deskLayout = '') {
    New-Item -ItemType Directory -Force $tileHome | Out-Null
    $c = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $root 'scenes.json'), $utf8))
    $c.monitors = [pscustomobject]@{}
    foreach ($m in $plugged) { $c.monitors | Add-Member -NotePropertyName $m.id -NotePropertyValue ([pscustomobject]@{ name = $m.name; builtin = $m.builtin; lastSeen = '2026-11-09T09:00:00'; bw = $m.bw; bh = $m.bh }) }
    $c.setups = [pscustomobject]@{}
    $c.setups | Add-Member -NotePropertyName $keyDesk -NotePropertyValue ([pscustomobject]@{ name = 'Desk'; ids = @($plugged.id | Sort-Object); lastUsed = '2026-11-09T09:00:00' })
    $c.setups | Add-Member -NotePropertyName $keyOffice -NotePropertyValue ([pscustomobject]@{ name = 'Office'; ids = @('AUO1', 'DEL2'); lastUsed = '2026-11-08T09:00:00' })
    $focus = @($c.scenes | ? { $_.id -eq 'focus' })[0]
    $focus | Add-Member -Force -NotePropertyName layouts -NotePropertyValue ([pscustomobject]@{})
    $focus.layouts | Add-Member -NotePropertyName $keyOffice -NotePropertyValue (ConvertFrom-Json $officeLayout)
    if ($deskLayout) { $focus.layouts | Add-Member -NotePropertyName $keyDesk -NotePropertyValue (ConvertFrom-Json $deskLayout) }
    [IO.File]::WriteAllText((Join-Path $tileHome 'config.json'), (ConvertTo-Json -Depth 20 -Compress $c), $utf8)
    $c
  }

  # Control: the snapshot ids reach tile.ps1 -Monitors as written, so the setup key is built from the ids the test wrote.
  Case 'control: tile -Monitors gives the snapshot ids as written' {
    $r = Run-Child "-File `"$tile`" -Monitors -From `"$snapFile`""
    $ids = (@($r.text | ConvertFrom-Json | % { $_ }) | % { [string]$_.id }) -join ','
    Check 'control: tile -Monitors gives the snapshot ids as written' ($r.code -eq 0 -and $ids -ceq 'LEN3,AUO1,DEL2') "exit $($r.code), ids: $ids"
  }

  # /snapshot names the plugged-in setup and registers it. A fresh config (no setups) gives the first setup the name Desk.
  Case 'snapshot: the reply names the setup, and the setup is registered in config' {
    $s = Start-Server (Join-Path $runDir 'home-snap') $snapFile
    try {
      $snap = ConvertFrom-Json (Get-Reply "$($s.url)snapshot").text
      if ($null -eq $snap.setup) { Check 'snapshot: the reply has a setup' $false 'no setup in the reply' }
      else {
        Check 'snapshot: setup.key is the sorted ids of the plugged-in monitors' ($snap.setup.key -ceq $keyDesk) "key: $($snap.setup.key)"
        Check 'snapshot: the first setup is named Desk' ($snap.setup.name -ceq 'Desk') "name: $($snap.setup.name)"
        $missing = @(@('key', 'name', 'follows') | ? { $null -eq $snap.setup.PSObject.Properties[$_] })
        Check 'snapshot: the setup has key, name and follows' ($missing.Count -eq 0) "missing: $($missing -join ',')"
      }
      Check 'snapshot: the monitors and windows are still in the reply (control)' ((@($snap.monitors).Count -eq 3) -and (@($snap.windows).Count -eq @($snapObj.windows).Count)) "monitors: $(@($snap.monitors).Count)"
      $cfg = ConvertFrom-Json (Get-Reply "$($s.url)config").text
      $sp = $cfg.setups.PSObject.Properties[$keyDesk]
      Check 'snapshot: the setup is saved in config under its key, named Desk, with its ids' ($null -ne $sp -and $sp.Value.name -ceq 'Desk' -and (Sorted $sp.Value.ids) -ceq (Sorted $plugged.id)) "setups: $(Keys-Of $cfg.setups)"
      Check 'snapshot: config knows each plugged-in monitor by id' ((Keys-Of $cfg.monitors) -ceq (Sorted $plugged.id)) "monitors: $(Keys-Of $cfg.monitors)"
    } finally { Stop-Server $s }
  }

  # POST /config with a stale copy of the whole config, as the page holds it (app.html:1685 posts clone(cfg)): the body carries every
  # key, with values the server no longer has. The copy is taken at load, before the page's own POST /layout for the plugged-in setup,
  # so it lacks that layout, unless $deskLayout seeds one (then the copy carries that older layout). $shape turns the copy into the
  # stale state; $label names the variant in each FAIL line.
  function Stale-Post([string]$label, [scriptblock]$shape, [string]$deskLayout = '') {
    $tileHome = Join-Path $runDir "home-stale-$label"; [void](Write-SeedConfig $tileHome $deskLayout)
    $s = Start-Server $tileHome $snapFile
    try {
      $copy = ConvertFrom-Json (Get-Reply "$($s.url)config").text
      $lay = Send-Post "$($s.url)layout" ('{"scene":"focus","key":"' + $keyDesk + '","layout":' + $layoutBody + '}')
      Check "config post ($label): the plugged-in layout save is accepted (scope)" ($lay.code -eq 200) "status $($lay.code)"
      $base = ConvertFrom-Json (Get-Reply "$($s.url)config").text   # the server's state, which the stale post must leave alone
      & $shape $copy
      $cf = @($copy.scenes | ? { $_.id -eq 'focus' })[0]; $cf.name = 'Focus edited'
      $p = Send-Post "$($s.url)config" (ConvertTo-Json -Depth 20 -Compress $copy)
      Check "config post ($label): the stale config is accepted (scope)" ($p.code -eq 200) "status $($p.code)"
      $after = ConvertFrom-Json (Get-Reply "$($s.url)config").text
      $fo = @($after.scenes | ? { $_.id -eq 'focus' })[0]; $bfo = @($base.scenes | ? { $_.id -eq 'focus' })[0]
      Check "config post ($label): the page's own scene edit is saved (control)" ($fo.name -ceq 'Focus edited') "name: $($fo.name)"
      Check "config post ($label): the server keeps its monitors" ((Canon $after.monitors) -ceq (Canon $base.monitors)) "monitors: $(Keys-Of $after.monitors)"
      Check "config post ($label): the server keeps its setups" ((Canon $after.setups) -ceq (Canon $base.setups)) "setups: $(Keys-Of $after.setups)"
      Check "config post ($label): the server keeps each scene's layouts, the plugged-in setup's too" ((Canon $fo.layouts) -ceq (Canon $bfo.layouts)) "layouts: $(Keys-Of $fo.layouts)"
    } finally { Stop-Server $s }
  }
  # Old values under the same keys: a renamed monitor, a renamed setup.
  Case 'config post: a stale copy with old values keeps the server''s monitors, setups and layouts' {
    Stale-Post 'old values' {
      param($c)
      foreach ($m in @($c.monitors.PSObject.Properties)) { $m.Value.name = "Old $($m.Name)" }
      foreach ($sp in @($c.setups.PSObject.Properties)) { $sp.Value.name = 'Old set' }
    }
  }
  # Empty values: a copy taken before the first snapshot registered the setup.
  Case 'config post: a stale copy with empty monitors, setups and layouts keeps the server''s' {
    Stale-Post 'empty' {
      param($c)
      Add-Member -Force -InputObject $c -NotePropertyName monitors -NotePropertyValue ([pscustomobject]@{})
      Add-Member -Force -InputObject $c -NotePropertyName setups -NotePropertyValue ([pscustomobject]@{})
      $f = @($c.scenes | ? { $_.id -eq 'focus' })[0]; Add-Member -Force -InputObject $f -NotePropertyName layouts -NotePropertyValue ([pscustomobject]@{})
    }
  }
  # The copy carries a Desk layout (the older one); the server's POST /layout replaces it with $layoutBody. The post must leave $layoutBody
  # on the server: a layout in a POST /config body is never written (serve.ps1 Save-PostedConfig).
  Case 'config post: a stale copy that carries the plugged-in layout keeps the layout the server saved since' {
    Stale-Post 'plugged layout' { param($c) } $layoutEarlier
  }

  # POST /config whose scene layouts carry keys that are not plugged in: one set up but not plugged in (Office, content changed), and one
  # no setup has. The rule is POST /layout's (409): nothing is written for such a key. The scene edit in the same body is saved (control).
  Case 'config post: a layout for a key that is not plugged in is not written' {
    $tileHome = Join-Path $runDir 'home-notplugged'; [void](Write-SeedConfig $tileHome)
    $s = Start-Server $tileHome $snapFile
    try {
      $base = ConvertFrom-Json (Get-Reply "$($s.url)config").text
      $bfo = @($base.scenes | ? { $_.id -eq 'focus' })[0]
      $officeBefore = Canon $bfo.layouts.PSObject.Properties[$keyOffice].Value
      $copy = ConvertFrom-Json (Get-Reply "$($s.url)config").text
      $cf = @($copy.scenes | ? { $_.id -eq 'focus' })[0]; $cf.name = 'Focus edited'
      $cf.layouts | Add-Member -Force -NotePropertyName $keyOffice -NotePropertyValue (ConvertFrom-Json $layoutBody)
      $cf.layouts | Add-Member -Force -NotePropertyName 'ZZZ9' -NotePropertyValue (ConvertFrom-Json $layoutBody)
      $p = Send-Post "$($s.url)config" (ConvertTo-Json -Depth 20 -Compress $copy)
      $after = ConvertFrom-Json (Get-Reply "$($s.url)config").text
      $fo = @($after.scenes | ? { $_.id -eq 'focus' })[0]
      Check 'config post: the scene edit in the same body is saved (control)' ($fo.name -ceq 'Focus edited') "status $($p.code), name: $($fo.name)"
      Check 'config post: the layout for a setup not plugged in (Office) is not written' ((Canon $fo.layouts.PSObject.Properties[$keyOffice].Value) -ceq $officeBefore) 'the Office layout changed'
      Check 'config post: a layout for a key no setup has is not written' ($null -eq $fo.layouts.PSObject.Properties['ZZZ9']) 'the key ZZZ9 was written'
    } finally { Stop-Server $s }
  }

  # POST /layout for a key the config knows but that is not plugged in: 409, and nothing is written.
  Case 'layout: a key that is not plugged in answers 409 and leaves the config as it was' {
    [void](Write-SeedConfig (Join-Path $runDir 'home-409'))
    $s = Start-Server (Join-Path $runDir 'home-409') $snapFile
    try {
      $before = Config-Shape (Get-Reply "$($s.url)config").text
      $r = Send-Post "$($s.url)layout" ('{"scene":"focus","key":"' + $keyOffice + '","layout":' + $layoutBody + '}')
      Check 'layout: a key that is not plugged in answers 409' ($r.code -eq 409) "status $($r.code)"
      $after = Config-Shape (Get-Reply "$($s.url)config").text
      Check 'layout: the refused write leaves the config as it was (control)' ($after -ceq $before) 'the config changed'
    } finally { Stop-Server $s }
  }

  # POST /layout for the plugged-in setup: 200, and the layout is stored for its scene. The Office layout on that scene is untouched.
  Case 'layout: the plugged-in setup''s layout is saved for its scene, and the other setup''s layout is untouched' {
    $seed = Write-SeedConfig (Join-Path $runDir 'home-200')
    $officeBefore = Canon (@($seed.scenes | ? { $_.id -eq 'focus' })[0].layouts.PSObject.Properties[$keyOffice].Value)
    $s = Start-Server (Join-Path $runDir 'home-200') $snapFile
    try {
      $r = Send-Post "$($s.url)layout" ('{"scene":"focus","key":"' + $keyDesk + '","layout":' + $layoutBody + '}')
      $fo = @((ConvertFrom-Json (Get-Reply "$($s.url)config").text).scenes | ? { $_.id -eq 'focus' })[0]
      $stored = $fo.layouts.PSObject.Properties[$keyDesk]
      Check 'layout: the plugged-in setup''s layout is saved for its scene (200, and stored)' (($r.code -eq 200) -and ($null -ne $stored) -and ($stored.Value.grids.AUO1.c -eq 3)) "status $($r.code), stored: $($null -ne $stored)"
      Check 'layout: the other setup''s layout for the scene is untouched (control)' ((Canon $fo.layouts.PSObject.Properties[$keyOffice].Value) -ceq $officeBefore) 'the Office layout changed'
    } finally { Stop-Server $s }
  }

  # GET /layouts: one entry per scene, each the layout Resolve-TileLayout gives that scene for the plugged-in setup (the product's own resolve).
  Case 'layouts: GET /layouts gives each scene the layout Resolve-TileLayout gives for the plugged-in setup' {
    [void](Write-SeedConfig (Join-Path $runDir 'home-layouts'))
    $s = Start-Server (Join-Path $runDir 'home-layouts') $snapFile
    try {
      $r = Get-Reply "$($s.url)layouts"
      Check 'layouts: GET /layouts answers 200' ($r.code -eq 200) "status $($r.code)"
      if ($r.code -eq 200) {
        $got = ConvertFrom-Json $r.text
        $cfg = ConvertFrom-Json (Get-Reply "$($s.url)config").text
        $differ = @($cfg.scenes | ? { (Canon $got.PSObject.Properties[$_.id].Value) -cne (Canon (Resolve-TileLayout $cfg $_ $keyDesk)) } | % { $_.id })
        Check 'layouts: each scene gets the layout Resolve-TileLayout gives for the plugged-in setup' ($differ.Count -eq 0 -and (Keys-Of $got) -ceq (Sorted @($cfg.scenes.id))) "differ: $($differ -join ',')"
      }
    } finally { Stop-Server $s }
  }

  # ---- Tray: a failed monitor read is not a change ----
  # Read-Monitors (tray.ps1) sits below -Lib's return, so its text is taken from tray.ps1 by the PowerShell parser and defined here. The
  # case then runs the product's own read. The seam (TILE_SCREENS_FILE) makes tile.ps1 -Monitors fail on a file that is never written.
  Add-Type -AssemblyName System.Windows.Forms   # the fallback read is Windows' own screen list
  $trayAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'tray.ps1'), [ref]$null, [ref]$null)
  $readFn = $trayAst.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-Monitors' }, $true)
  if ($readFn) { . ([scriptblock]::Create($readFn.Extent.Text)) }
  $screensGood = Join-Path $runDir 'screens-good.json'; $screensGone = Join-Path $runDir 'screens-gone.json'
  [IO.File]::WriteAllText($screensGood, (ConvertTo-Json -Depth 5 -Compress -InputObject @(
    [pscustomobject]@{ id = 'LEN3'; name = 'DISPLAY1'; x = 0; y = 1000; w = 1536; h = 960; bw = 1536; bh = 960; builtin = $true },
    [pscustomobject]@{ id = 'AUO1'; name = 'DISPLAY2'; x = 1536; y = 0; w = 4096; h = 1728; bw = 4096; bh = 1728; builtin = $false },
    [pscustomobject]@{ id = 'DEL2'; name = 'DISPLAY3'; x = 5632; y = 0; w = 1200; h = 1920; bw = 1200; bh = 1920; builtin = $false })), $utf8)
  # Reads the tray makes in order: a good read, a failed read, then a good read of the same monitors. Each read goes through the tick's
  # Get-MonitorKey, and each key through Step-Tray with the same fixed clock. The first read only seeds, so it applies nothing.
  Case 'tray: a failed monitor read fires no display trigger, and the good read after it fires none for the same monitors' {
    Check 'tray: the monitor read is Read-Monitors in tray.ps1 (scope)' ($null -ne $readFn) 'no Read-Monitors function in tray.ps1'
    if ($null -eq $readFn) { return }
    $saveSeam = $env:TILE_SCREENS_FILE
    try {
      $env:TILE_SCREENS_FILE = $screensGood; $k1 = Get-MonitorKey (Read-Monitors)
      $env:TILE_SCREENS_FILE = $screensGone; $failThrows = $false
      try { $null = & $tile -Monitors 3>$null } catch { $failThrows = $true }
      $k2 = Get-MonitorKey (Read-Monitors)
      $env:TILE_SCREENS_FILE = $screensGood; $k3 = Get-MonitorKey (Read-Monitors)
    } finally { $env:TILE_SCREENS_FILE = $saveSeam }
    Check 'tray: a good read gives the three monitor ids (scope)' ($k1 -ceq (Key-Of 'LEN3', 'AUO1', 'DEL2')) "key: $k1"
    Check 'tray: a failed read makes tile.ps1 -Monitors throw (scope)' $failThrows
    $ts = New-TrayState
    $a1 = Ids (Step-Tray $ts $d $trayCfg $k1 $null '')
    $a2 = Ids (Step-Tray $ts $d $trayCfg $k2 $null '')
    $a3 = Ids (Step-Tray $ts $d $trayCfg $k3 $null '')
    Check 'tray: the seeding read applies nothing (control)' ($a1 -eq '') "applied: '$a1'"
    Check 'tray: a failed monitor read fires no display trigger' ($a2 -eq '') "applied: '$a2'"
    Check 'tray: the good read after a failed read fires no display trigger (same monitors)' ($a3 -eq '') "applied: '$a3'"
  }
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  foreach ($p in $servers) { if (-not $p.HasExited) { $p.Kill() } }
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All setup-plumbing checks passed.'; exit 0 }

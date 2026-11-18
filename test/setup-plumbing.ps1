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
#     GET  /config    the config. GET /layouts: {<scene id>: {layout, follows}}. layout is Resolve-TileLayout's layout of that scene for the
#                     plugged-in setup; follows is the name of the closest known setup whose layout the scene holds while the plugged-in
#                     setup has none of its own there, else ''. The page takes both from here (it keeps no copy of the setup pick).
#     POST /layout    body {scene, key, layout}: 200 and stored when key is plugged in; 409 and no change when not.
#     POST /config    a whole config. The server keeps its monitors, setups and its layouts for every key, plugged in or not, whatever
#                     the body carries: POST /config writes no layout. Layouts are written only by POST /layout (409 for a key not plugged in).
#     POST /rename    body {kind, id, name}. kind 'monitor': id is the monitor id; kind 'setup': id is the setup key. 200 and the name is saved
#                     in config monitors or setups, and nothing else changes. 404 for an unknown kind or id.
#     POST /forget    body {kind, id}. 200 and the entry is removed from config. A forgotten setup's layouts go from every scene. Forgetting a
#                     monitor also forgets each setup it is in (decision monitor-setups, item 13). 409 and no change when the monitor is
#                     plugged in or the setup is the one in use (the refusal POST /layout gives a key not plugged in). 404 for an unknown kind or id.
#     Lock: the rename and the forget run under the config lock (Use-TileLock). The lock case holds that lock, writes a scene under it and
#     checks both changes survive. It cannot by itself show a missing lock: an unlocked rename passes when its read comes after the write.
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
  # $alsoOffice names more scenes that also get the Office layout (the focus scene always has it). Written into $tileHome before its
  # server starts. Returns the object it wrote.
  function Write-SeedConfig([string]$tileHome, [string]$deskLayout = '', [string[]]$alsoOffice = @()) {
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
    foreach ($id in $alsoOffice) {
      $sc = @($c.scenes | ? { $_.id -eq $id })[0]
      if (-not $sc.PSObject.Properties['layouts'] -or $null -eq $sc.layouts) { $sc | Add-Member -Force -NotePropertyName layouts -NotePropertyValue ([pscustomobject]@{}) }
      $sc.layouts | Add-Member -NotePropertyName $keyOffice -NotePropertyValue (ConvertFrom-Json $officeLayout)
    }
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

  # GET /layouts: one entry per scene, its layout the product's own Resolve-TileLayout gives for the plugged-in setup.
  Case 'layouts: GET /layouts gives each scene the layout Resolve-TileLayout gives for the plugged-in setup' {
    [void](Write-SeedConfig (Join-Path $runDir 'home-layouts'))
    $s = Start-Server (Join-Path $runDir 'home-layouts') $snapFile
    try {
      $r = Get-Reply "$($s.url)layouts"
      Check 'layouts: GET /layouts answers 200' ($r.code -eq 200) "status $($r.code)"
      if ($r.code -eq 200) {
        $got = ConvertFrom-Json $r.text
        $cfg = ConvertFrom-Json (Get-Reply "$($s.url)config").text
        $differ = @($cfg.scenes | ? { (Canon $got.PSObject.Properties[$_.id].Value.layout) -cne (Canon (Resolve-TileLayout $cfg $_ $keyDesk)) } | % { $_.id })
        Check 'layouts: each scene gets the layout Resolve-TileLayout gives for the plugged-in setup' ($differ.Count -eq 0 -and (Keys-Of $got) -ceq (Sorted @($cfg.scenes.id))) "differ: $($differ -join ',')"
      }
    } finally { Stop-Server $s }
  }

  # GET /layouts, the follows name. Focus has no layout of its own on Desk and holds Office's, which shares two monitors with Desk. Ridge
  # shares one and holds a Focus layout too, so Office is the closer. Review holds no layout on any setup. The names are written out here.
  # A missing field reads as $null, so it never matches the empty name.
  function Follows-Of($entry) { if ($null -eq $entry) { return $null }; $p = $entry.PSObject.Properties['follows']; if ($p) { $p.Value } else { $null } }
  Case 'layouts: each scene gives the name of the setup it follows, or none' {
    $home1 = Join-Path $runDir 'home-follows'
    [void](Write-SeedConfig $home1)
    $c = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $home1 'config.json'), $utf8))
    Add-Member -InputObject $c.setups -NotePropertyName 'LEN3' -NotePropertyValue ([pscustomobject]@{ name = 'Ridge'; ids = @('LEN3'); lastUsed = '2026-11-16T09:00:00' })
    $fc = @($c.scenes | ? { $_.id -eq 'focus' })[0]
    Add-Member -InputObject $fc.layouts -NotePropertyName 'LEN3' -NotePropertyValue (ConvertFrom-Json $officeLayout)
    [IO.File]::WriteAllText((Join-Path $home1 'config.json'), (ConvertTo-Json -Depth 20 -Compress -InputObject $c), $utf8)
    $s = Start-Server $home1 $snapFile
    try {
      $r = Get-Reply "$($s.url)layouts"
      Check 'layouts: GET /layouts answers 200 (scope)' ($r.code -eq 200) "status $($r.code)"
      if ($r.code -eq 200) {
        $got = ConvertFrom-Json $r.text
        $f = Follows-Of $got.focus; $rv = Follows-Of $got.review
        Check 'layouts: Focus follows Office, the closer setup (Desk has no layout of its own there)' ($f -ceq 'Office') "follows: $(if ($null -eq $f) { 'missing' } else { "'$f'" })"
        Check 'layouts: Review, with no layout on any setup, follows none' ($rv -ceq '') "follows: $(if ($null -eq $rv) { 'missing' } else { "'$rv'" })"
      }
    } finally { Stop-Server $s }
    # Desk has its own layout on Focus: Focus follows none.
    $home2 = Join-Path $runDir 'home-follows-own'
    [void](Write-SeedConfig $home2 $layoutBody)
    $s2 = Start-Server $home2 $snapFile
    try {
      $r2 = Get-Reply "$($s2.url)layouts"
      Check 'layouts: GET /layouts answers 200 with Desk''s own layout on Focus (scope)' ($r2.code -eq 200) "status $($r2.code)"
      if ($r2.code -eq 200) {
        $f2 = Follows-Of (ConvertFrom-Json $r2.text).focus
        Check 'layouts: Focus follows none once Desk has its own layout there' ($f2 -ceq '') "follows: $(if ($null -eq $f2) { 'missing' } else { "'$f2'" })"
      }
    } finally { Stop-Server $s2 }
  }

  # ---- Server: rename and forget (decision monitor-setups, item 13). Routes in the header. On 54b842b neither route is built, so each
  # answer is 404 and each case is red by assert, named "route absent". ----
  function Cfg-Of($s) { ConvertFrom-Json (Get-Reply "$($s.url)config").text }
  function Setup-Of($c, [string]$key) { $p = $c.setups.PSObject.Properties[$key]; if ($p) { $p.Value } }
  function Monitor-Of($c, [string]$id) { $p = $c.monitors.PSObject.Properties[$id]; if ($p) { $p.Value } }
  function Layout-Of($c, [string]$scene, [string]$key) { $sc = @($c.scenes | ? { $_.id -eq $scene })[0]; if ($sc -and $sc.PSObject.Properties['layouts'] -and $sc.layouts) { $p = $sc.layouts.PSObject.Properties[$key]; if ($p) { $p.Value } } }
  # A value as Canon reads it, with its name field left out: the other fields must come back as they were.
  function Without-Name($o) { if ($null -eq $o) { return 'null' }; $x = ConvertFrom-Json (ConvertTo-Json -Depth 10 -Compress -InputObject $o); [void]$x.PSObject.Properties.Remove('name'); Canon $x }
  # The status of a reply as a FAIL detail. A 404 names the route as absent (or an unknown id); any other wrong status shows both codes.
  function Note-Status($r, [string]$route, [int]$want) { if ($r.code -eq $want) { 'ok' } elseif ($r.code -eq 404) { "POST /$route answered 404: route absent, or the id is unknown" } else { "status $($r.code), want $want" } }

  Case 'rename: POST /rename changes a monitor''s name and the setup in use''s name in config, and keeps the other fields' {
    $hdir = Join-Path $runDir 'home-rename'; [void](Write-SeedConfig $hdir)
    $s = Start-Server $hdir $snapFile
    try {
      $before = Cfg-Of $s
      $rm = Send-Post "$($s.url)rename" '{"kind":"monitor","id":"AUO1","name":"Wide 49"}'
      Check 'rename monitor: POST /rename answers 200' ($rm.code -eq 200) (Note-Status $rm 'rename' 200)
      $rs = Send-Post "$($s.url)rename" ('{"kind":"setup","id":"' + $keyDesk + '","name":"Main desk"}')
      Check 'rename setup: POST /rename answers 200' ($rs.code -eq 200) (Note-Status $rs 'rename' 200)
      $after = Cfg-Of $s
      if ($rm.code -eq 200) {
        Check 'rename monitor: config holds the new name' ((Monitor-Of $after 'AUO1').name -ceq 'Wide 49') "name: $((Monitor-Of $after 'AUO1').name)"
        Check 'rename monitor: its other fields are kept' ((Without-Name (Monitor-Of $after 'AUO1')) -ceq (Without-Name (Monitor-Of $before 'AUO1'))) 'a field other than name changed'
      }
      if ($rs.code -eq 200) {
        Check 'rename setup: config holds the new name' ((Setup-Of $after $keyDesk).name -ceq 'Main desk') "name: $((Setup-Of $after $keyDesk).name)"
        Check 'rename setup: its monitors and last-used time are kept' ((Without-Name (Setup-Of $after $keyDesk)) -ceq (Without-Name (Setup-Of $before $keyDesk))) 'a field other than name changed'
      }
      Check 'rename: the other monitor and setup keep their names (control)' ((Monitor-Of $after 'LEN3').name -ceq 'Laptop' -and (Setup-Of $after $keyOffice).name -ceq 'Office') 'an unrelated name changed'
    } finally { Stop-Server $s }
  }

  # The page holds a copy of the whole config. A save of that copy after a dialog rename must not put the old names back: the server keeps
  # its monitors and setups under the lock, whatever the body carries.
  Case 'rename: a whole-config POST from a copy taken before the rename keeps the new names' {
    $hdir = Join-Path $runDir 'home-rename-stale'; [void](Write-SeedConfig $hdir)
    $s = Start-Server $hdir $snapFile
    try {
      $copy = Cfg-Of $s
      $rm = Send-Post "$($s.url)rename" '{"kind":"monitor","id":"AUO1","name":"Wide 49"}'
      $rs = Send-Post "$($s.url)rename" ('{"kind":"setup","id":"' + $keyDesk + '","name":"Main desk"}')
      $renamed = $rm.code -eq 200 -and $rs.code -eq 200
      Check 'stale copy: both renames answer 200 (scope)' $renamed "$(Note-Status $rm 'rename' 200) | $(Note-Status $rs 'rename' 200)"
      if ($renamed) {
        $p = Send-Post "$($s.url)config" (ConvertTo-Json -Depth 20 -Compress -InputObject $copy)
        Check 'stale copy: the whole-config POST is accepted (control)' ($p.code -eq 200) "status $($p.code)"
        $after = Cfg-Of $s
        Check 'stale copy: the monitor keeps its new name' ((Monitor-Of $after 'AUO1').name -ceq 'Wide 49') "name: $((Monitor-Of $after 'AUO1').name)"
        Check 'stale copy: the setup keeps its new name' ((Setup-Of $after $keyDesk).name -ceq 'Main desk') "name: $((Setup-Of $after $keyDesk).name)"
      }
    } finally { Stop-Server $s }
  }

  Case 'forget: POST /forget refuses the monitor plugged in and the setup in use, with 409 and no change' {
    $hdir = Join-Path $runDir 'home-forget-refused'; [void](Write-SeedConfig $hdir)
    $s = Start-Server $hdir $snapFile
    try {
      $before = Canon (Cfg-Of $s)
      $fm = Send-Post "$($s.url)forget" '{"kind":"monitor","id":"AUO1"}'
      Check 'forget monitor: a monitor plugged in is refused with 409' ($fm.code -eq 409) (Note-Status $fm 'forget' 409)
      if ($fm.code -eq 409) { Check 'forget monitor: the refused forget leaves the config as it was' ((Canon (Cfg-Of $s)) -ceq $before) 'the config changed' }
      $fs = Send-Post "$($s.url)forget" ('{"kind":"setup","id":"' + $keyDesk + '"}')
      Check 'forget setup: the setup in use is refused with 409' ($fs.code -eq 409) (Note-Status $fs 'forget' 409)
      if ($fs.code -eq 409) { Check 'forget setup: the refused forget leaves the config as it was' ((Canon (Cfg-Of $s)) -ceq $before) 'the config changed' }
    } finally { Stop-Server $s }
  }

  # The setup not in use has an Office layout on three scenes (focus, meetings, review). Forgetting it removes all three, and the
  # layout the setup in use has on focus stays.
  Case 'forget: POST /forget removes a setup not in use from config, and its layouts from every scene' {
    $hdir = Join-Path $runDir 'home-forget-setup'; [void](Write-SeedConfig $hdir $layoutBody @('meetings', 'review'))
    $s = Start-Server $hdir $snapFile
    try {
      $before = Cfg-Of $s
      $heldBefore = @($before.scenes | ? { $_.PSObject.Properties['layouts'] -and $_.layouts.PSObject.Properties[$keyOffice] } | % { $_.id })
      Check 'forget setup: the setup not in use has layouts on three scenes before the forget (scope)' ($heldBefore.Count -eq 3) "held on: $($heldBefore -join ',')"
      if ($heldBefore.Count -eq 3) {
        $r = Send-Post "$($s.url)forget" ('{"kind":"setup","id":"' + $keyOffice + '"}')
        Check 'forget setup: POST /forget answers 200' ($r.code -eq 200) (Note-Status $r 'forget' 200)
        if ($r.code -eq 200) {
          $after = Cfg-Of $s
          Check 'forget setup: the setup is gone from config' ($null -eq (Setup-Of $after $keyOffice)) 'the setup is still in config'
          $heldAfter = @($after.scenes | ? { $_.PSObject.Properties['layouts'] -and $_.layouts.PSObject.Properties[$keyOffice] } | % { $_.id })
          Check 'forget setup: no scene keeps a layout for it' ($heldAfter.Count -eq 0) "still on: $($heldAfter -join ',')"
          Check 'forget setup: the setup in use keeps its own Focus layout (control)' ($null -ne (Setup-Of $after $keyDesk) -and (Canon (Layout-Of $after 'focus' $keyDesk)) -ceq (Canon (ConvertFrom-Json $layoutBody))) 'the Desk setup or its Focus layout changed'
        }
      }
    } finally { Stop-Server $s }
  }

  # Forgetting a monitor not plugged in forgets each setup it is in (item 13), with that setup's layouts. Home 27 is in setup AUO1|H27,
  # which has a layout on the meetings scene.
  Case 'forget: POST /forget removes an unplugged monitor, and each setup it is in with its layouts' {
    $hdir = Join-Path $runDir 'home-forget-monitor'; $c = Write-SeedConfig $hdir
    $c.monitors | Add-Member -NotePropertyName 'H27' -NotePropertyValue ([pscustomobject]@{ name = 'Home 27'; builtin = $false; lastSeen = '2026-11-09T09:00:00'; bw = 2560; bh = 1440 })
    $c.setups | Add-Member -NotePropertyName 'AUO1|H27' -NotePropertyValue ([pscustomobject]@{ name = 'Home'; ids = @('AUO1', 'H27'); lastUsed = '2026-11-09T09:00:00' })
    $meet = @($c.scenes | ? { $_.id -eq 'meetings' })[0]
    if (-not $meet.PSObject.Properties['layouts'] -or $null -eq $meet.layouts) { $meet | Add-Member -Force -NotePropertyName layouts -NotePropertyValue ([pscustomobject]@{}) }
    $meet.layouts | Add-Member -NotePropertyName 'AUO1|H27' -NotePropertyValue (ConvertFrom-Json $officeLayout)
    [IO.File]::WriteAllText((Join-Path $hdir 'config.json'), (ConvertTo-Json -Depth 20 -Compress $c), $utf8)
    $s = Start-Server $hdir $snapFile
    try {
      $before = Cfg-Of $s
      Check 'forget monitor: the setup it is in has a layout on a scene before the forget (scope)' ($null -ne (Setup-Of $before 'AUO1|H27') -and $null -ne (Layout-Of $before 'meetings' 'AUO1|H27')) 'no Home setup or no layout for it'
      $r = Send-Post "$($s.url)forget" '{"kind":"monitor","id":"H27"}'
      Check 'forget monitor: POST /forget answers 200 for a monitor not plugged in' ($r.code -eq 200) (Note-Status $r 'forget' 200)
      if ($r.code -eq 200) {
        $after = Cfg-Of $s
        Check 'forget monitor: the monitor is gone from config' ($null -eq (Monitor-Of $after 'H27')) 'H27 is still in config'
        Check 'forget monitor: the setup it is in is gone, and so is its layout on every scene' ($null -eq (Setup-Of $after 'AUO1|H27') -and @($after.scenes | ? { $_.PSObject.Properties['layouts'] -and $_.layouts.PSObject.Properties['AUO1|H27'] }).Count -eq 0) 'the setup AUO1|H27 or a layout for it is still there'
        Check 'forget monitor: the setups it was not in are kept (control)' ($null -ne (Setup-Of $after $keyDesk) -and $null -ne (Setup-Of $after $keyOffice)) 'Desk or Office is gone'
      }
    } finally { Stop-Server $s }
  }

  # The rename runs under the config lock, as the other writers do. This case holds that lock (the mutex config.ps1 names for this home),
  # posts a rename, writes a scene's name under the lock, and lets go. Both the rename and the scene must survive.
  Case 'rename: a change written under the config lock survives a rename posted while the lock is held' {
    Add-Type -AssemblyName System.Net.Http
    $hdir = Join-Path $runDir 'home-lock'; [void](Write-SeedConfig $hdir)
    $s = Start-Server $hdir $snapFile
    try {
      $hash = [BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($hdir.ToLowerInvariant()))).Replace('-', '').Substring(0, 12)
      $mutex = New-Object Threading.Mutex($false, "Local\TileWindows-Write-$hash")
      $held = $false; $task = $null
      try {
        $held = $mutex.WaitOne(10000)
        Check 'rename under the lock: the test holds the config lock (scope)' $held 'another writer held the config lock'
        if ($held) {
          $task = (New-Object Net.Http.HttpClient).PostAsync("$($s.url)rename", (New-Object Net.Http.StringContent('{"kind":"monitor","id":"LEN3","name":"Built-in"}', $utf8, 'application/json')))
          $cfgPath = Join-Path $hdir 'config.json'
          $c = ConvertFrom-Json ([IO.File]::ReadAllText($cfgPath, $utf8))
          @($c.scenes | ? { $_.id -eq 'focus' })[0].name = 'Focus under lock'
          [IO.File]::WriteAllText($cfgPath, (ConvertTo-Json -Depth 20 -Compress $c), $utf8)
        }
      } finally { if ($held) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
      if ($held) {
        $code = [int]$task.Result.StatusCode
        Check 'rename under the lock: POST /rename answers 200 once the lock is free' ($code -eq 200) (Note-Status @{ code = $code } 'rename' 200)
        $after = Cfg-Of $s
        Check 'rename under the lock: the scene written under the lock is kept (control)' ((@($after.scenes | ? { $_.id -eq 'focus' })[0]).name -ceq 'Focus under lock') 'the scene name written under the lock is lost'
        if ($code -eq 200) { Check 'rename under the lock: the rename is kept' ((Monitor-Of $after 'LEN3').name -ceq 'Built-in') 'the rename is lost' }
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

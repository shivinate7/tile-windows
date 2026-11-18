# Serve app.html live on 127.0.0.1, with a random token in every URL.
#   GET  /<token>/          the page
#   GET  /<token>/snapshot  tile.ps1 -Json (kept: /preview lays scenes out on this same snapshot), plus setup {key, name, follows}:
#                           the plugged-in monitor set, registered in config (decision monitor-setups). follows = the closest known
#                           setup's name while this one has no layout of its own, else ''. A snapshot whose monitors carry no ids has key ''.
#   GET  /<token>/config    config.json (scenes and settings); created from scenes.json on first run
#   POST /<token>/config    body = whole config; validated, then written. It always keeps the server's monitors, setups and each scene's layouts.
#   GET  /<token>/layouts   {scene id: {layout, follows}}. layout is what Resolve-TileLayout gives that scene for the plugged-in setup; follows is the
#                           name of the setup it follows there (Get-TileFollows), '' when it has its own layout or none to follow.
#   POST /<token>/layout    body = {scene, key, layout}; saves that scene's layout for key. 409 and no change when key is not the plugged-in setup.
#   POST /<token>/rename    body = {kind: monitor|setup, id, name}; saves that monitor's or setup's name (decision monitor-setups, item 13). Allowed whether or not it is
#                           plugged in. 404 for an unknown kind or id; 400 for a missing or empty name.
#   POST /<token>/forget    body = {kind, id}; removes a monitor, or a setup with its layout in every scene. Forgetting a monitor also forgets each setup it is in.
#                           409 and no change for a monitor plugged in or the setup in use; 404 for an unknown kind or id.
#   GET  /<token>/state     state.json (scene last applied, recent log)
#   GET  /<token>/appnames  the display name of each app (appNames in scenes.json)
#   POST /<token>/preview   body = scene; answers tile.ps1 -Scene -From <last snapshot> -Json (moves nothing)
#   POST /<token>/scene     body = scene; answers tile.ps1 -Scene -Json results. ?dry=1 = -DryRun.
#   POST /<token>/apply     body = -Place array; answers tile.ps1 -Place -Json results. ?dry=1 = -DryRun.
#   POST /<token>/note      dismiss the recovery note (see X-Tile-Note)
#   POST /<token>/quit      stop the server
# Prints the URL as its first line, opens the browser (unless -NoBrowser), stops on Ctrl+C or /quit.
# -DryRun: every apply is a dry run (for tests). -From <snapshot.json>: show that snapshot instead of
# the live desktop; implies -DryRun, and keeps scenes in a throwaway folder under %TEMP% (unless TILE_HOME
# is set), so a sample session never writes your real scenes.
param([switch]$NoBrowser, [switch]$DryRun, [string]$From = '')

$tile = Join-Path $PSScriptRoot 'tile.ps1'
$page = Join-Path $PSScriptRoot 'app.html'
if ($From) { $From = (Resolve-Path -LiteralPath $From).Path; $DryRun = [switch]$true; if (-not $env:TILE_HOME) { $env:TILE_HOME = $sampleHome = Join-Path $env:TEMP "tile-windows-sample-$PID" } }
. (Join-Path $PSScriptRoot 'config.ps1')
$rb = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($rb)
$token = -join ($rb | % { $_.ToString('x2') })
$probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
$base = "http://127.0.0.1:$port/"
$http = [Net.HttpListener]::new(); $http.Prefixes.Add($base); $http.Start()
$url = "$base$token/"
$url
[Console]::Out.Flush()
if (-not $NoBrowser) { Start-Process $url }

function Send($ctx, [int]$code, [string]$type, [string]$body) {
  $b = [Text.Encoding]::UTF8.GetBytes($body)
  $ctx.Response.StatusCode = $code; $ctx.Response.ContentType = "$type; charset=utf-8"
  $ctx.Response.Headers['Cache-Control'] = 'no-store'; $ctx.Response.ContentLength64 = $b.Length
  # A read that recovered from a bad file (here or in the tray) says so on every answer until the page dismisses it.
  $n = Get-TileNote; if ($n) { $ctx.Response.Headers['X-Tile-Note'] = [Uri]::EscapeDataString($n) }
  $ctx.Response.OutputStream.Write($b, 0, $b.Length); $ctx.Response.Close()
}
# A JSON body of the given kind ('[' or '{'), or $null after answering 400.
function Body($ctx, $req, $open) {
  $body = [IO.StreamReader]::new($req.InputStream, [Text.Encoding]::UTF8).ReadToEnd()
  # An empty -Place or -Scene would fall through to grid tiling, which moves windows.
  if (-not $body.Trim().StartsWith($open)) { Send $ctx 400 'text/plain' ("Body must be a JSON " + $(if ($open -eq '[') { 'array.' } else { 'object.' })); return $null }
  try { $null = ConvertFrom-Json $body -ErrorAction Stop } catch { Send $ctx 400 'text/plain' "Bad JSON: $($_.Exception.Message)"; return $null }
  $body
}
$fromArg = @{}; if ($From) { $fromArg.From = $From }
# The plugged-in monitors, with ids: from the -From snapshot, else tile.ps1 -Monitors.
function Get-Plugged {
  if ($From) { return @((ConvertFrom-Json ([IO.File]::ReadAllText($From, [Text.Encoding]::UTF8))).monitors | % { $_ }) }
  @((ConvertFrom-Json ((& $tile -Monitors 2>$null) -join '')) | % { $_ })
}
# Writes the config as the product's own text, nested deeper than ConvertTo-Json's default depth.
function Save-TileConfigObject($cfg) { Save-TileConfigText (ConvertTo-Json -Depth 20 -Compress -InputObject $cfg) }
# The name of the closest known setup other than $key, while $key has no layout of its own in any scene (Get-TileClosestSetup's pick, the one
# Resolve-TileLayout makes, over the keys any scene holds a layout for); '' when it has its own layout or none shares a monitor.
function Get-SetupFollows($cfg, [string]$key) {
  $held = @($cfg.scenes | ? { $_.layouts } | % { $_.layouts.PSObject.Properties.Name })
  if ($held -ccontains $key) { return '' }
  $mine = $cfg.setups.PSObject.Properties[$key]; if (-not $mine) { return '' }
  $pick = Get-TileClosestSetup $cfg @($mine.Value.ids) $held $key
  if ($pick) { [string]$pick.Value.name } else { '' }
}
# $text (the snapshot) with setup {key, name, follows} added. The setup is registered in config under the lock. A snapshot with no
# monitor ids (an older file) has no setup to register: key ''.
function Add-SnapshotSetup([string]$text) {
  try { $mons = @((ConvertFrom-Json $text).monitors | % { $_ }) } catch { return $text }
  $key = Get-TileKnownSetupKey $mons; $name = ''; $follows = ''
  if ($key) {
    $r = Use-TileLock {
      $cfg = ConvertFrom-Json (Get-TileConfigText)
      [void](Register-TileSetup $cfg $mons); Save-TileConfigObject $cfg
      [pscustomobject]@{ name = [string]$cfg.setups.PSObject.Properties[$key].Value.name; follows = Get-SetupFollows $cfg $key }
    }
    $name = $r.name; $follows = $r.follows
  }
  $setup = ConvertTo-Json -Compress -InputObject ([pscustomobject]@{ key = $key; name = $name; follows = $follows })
  $t = $text.TrimEnd(); if (-not $t.EndsWith('}')) { return $text }
  $t.Substring(0, $t.Length - 1) + ',"setup":' + $setup + '}'
}
# A posted whole config, validated, with what the page does not own put back. The page posts its whole copy, which may be stale
# (app.html clone(cfg)); it owns the scenes, not the monitors, setups or layouts. Under the lock the server's monitors, setups and
# each scene's layouts replace the body's. Only POST /layout writes a layout.
function Save-PostedConfig([string]$body) {
  Test-TileConfig $body
  Use-TileLock {
    $new = ConvertFrom-Json $body; $cur = ConvertFrom-Json (Get-TileConfigText)
    $asPosted = ConvertTo-Json -Depth 20 -Compress -InputObject $new
    foreach ($k in 'monitors', 'setups') {
      $c = $cur.PSObject.Properties[$k]
      $n = $new.PSObject.Properties[$k]   # set in place, so the key order of a clean save is the page's
      if ($c -and $n) { $n.Value = $c.Value } elseif ($c) { $new | Add-Member $k $c.Value } elseif ($n) { $new.PSObject.Properties.Remove($k) }
    }
    foreach ($sc in @($new.scenes)) {
      $mine = $sc.PSObject.Properties['layouts']; $old = @($cur.scenes | ? { $_.id -eq $sc.id })[0]
      $lay = [pscustomobject]@{}
      if ($old -and $old.layouts) { foreach ($p in @($old.layouts.PSObject.Properties)) { $lay | Add-Member $p.Name $p.Value } }
      if ($mine) { $mine.Value = $lay } elseif (@($lay.PSObject.Properties).Count) { $sc | Add-Member layouts $lay }
    }
    # The text as posted when nothing was put back or dropped, so a clean save is byte for byte what the page sent.
    $out = ConvertTo-Json -Depth 20 -Compress -InputObject $new
    Save-TileConfigText $(if ($out -ceq $asPosted) { $body } else { $out })
  }
}
# POST /layout: the answer's status code. The config is read again under the lock, so a write from the tray or another page is not lost.
function Save-SceneLayout($b, $mons) {
  Use-TileLock {
    $key = Get-TileKnownSetupKey $mons
    if (-not $key -or [string]$b.key -cne $key) { return 409 }
    $cfg = ConvertFrom-Json (Get-TileConfigText)
    $sc = @($cfg.scenes | ? { $_.id -eq $b.scene })[0]
    if (-not $sc) { return 404 }
    [void](Register-TileSetup $cfg $mons)
    if ($null -eq $sc.PSObject.Properties['layouts'] -or $null -eq $sc.layouts) { $sc | Add-Member -Force layouts ([pscustomobject]@{}) }
    $sc.layouts | Add-Member -Force -NotePropertyName $key -NotePropertyValue $b.layout
    Save-TileConfigObject $cfg
    return 200
  }
}
# POST /rename: the answer's status code. The config is read again under the lock, so only the name changes, whatever else another writer saved.
function Rename-Known($b) {
  $coll = switch ([string]$b.kind) { 'monitor' { 'monitors' } 'setup' { 'setups' } default { return 404 } }
  Use-TileLock {
    $cfg = ConvertFrom-Json (Get-TileConfigText)
    $hold = $cfg.PSObject.Properties[$coll]; $p = if ($hold) { $hold.Value.PSObject.Properties[[string]$b.id] }
    if (-not $p) { return 404 }
    $p.Value | Add-Member -Force name ([string]$b.name).Trim()
    Save-TileConfigObject $cfg
    return 200
  }
}
# POST /forget: the answer's status code. $mons is the plugged-in monitors (read before the lock, as for /layout). A setup goes with its layout in every
# scene; a monitor goes with each setup it is in. A scene aimed at a forgotten setup is switched off and loses its setupKey.
function Forget-Known($b, $mons) {
  $kind = [string]$b.kind; $id = [string]$b.id
  if ($kind -ne 'monitor' -and $kind -ne 'setup') { return 404 }
  Use-TileLock {
    $cfg = ConvertFrom-Json (Get-TileConfigText)
    $inUse = Get-TileKnownSetupKey $mons
    $drop = @()
    if ($kind -eq 'monitor') {
      if (-not $cfg.monitors -or -not $cfg.monitors.PSObject.Properties[$id]) { return 404 }
      if (@($mons | ? { $_ } | % { [string]$_.id }) -ccontains $id) { return 409 }
      $drop = @($cfg.setups.PSObject.Properties | ? { @($_.Value.ids) -ccontains $id } | % { $_.Name })
    } else {
      if (-not $cfg.setups -or -not $cfg.setups.PSObject.Properties[$id]) { return 404 }
      # The setup in use; or, when a plugged-in monitor has no id and the key cannot be computed, any setup that holds a plugged-in monitor.
      $held = @($cfg.setups.PSObject.Properties[$id].Value.ids)
      if ($inUse) { if ($id -ceq $inUse) { return 409 } }
      elseif (@($mons | ? { $_ -and $_.id } | % { [string]$_.id } | ? { $held -ccontains $_ }).Count) { return 409 }
      $drop = @($id)
    }
    foreach ($k in $drop) {
      $cfg.setups.PSObject.Properties.Remove($k)
      foreach ($sc in @($cfg.scenes)) { if ($sc.layouts -and $sc.layouts.PSObject.Properties[$k]) { $sc.layouts.PSObject.Properties.Remove($k) } }
    }
    if ($kind -eq 'monitor') { $cfg.monitors.PSObject.Properties.Remove($id) }
    # A scene aimed at a forgotten setup has its switch off, and a note asks for a pick (as Update-TileSetupSwitch does). Note first, then save.
    $gone = @(Clear-TileSetupTriggers $cfg $drop)
    if ($gone.Count) { Add-TileNote "A setup you forgot was the one $($gone -join ', ') used, so Use This Scene on This Setup is off for it. $(Get-TilePickSetupAsk)" }
    Save-TileConfigObject $cfg
    return 200
  }
}
$snap = '{"monitors":[],"windows":[]}'

try {
  $run = $true
  while ($run -and $http.IsListening) {
    $ar = $http.BeginGetContext($null, $null)
    while (-not $ar.AsyncWaitHandle.WaitOne(250)) {}  # short waits so Ctrl+C gets through
    $ctx = $http.EndGetContext($ar); $req = $ctx.Request
    # One request's failure (say, the browser hung up) must not stop the server.
    try {
      $path = $req.Url.AbsolutePath
      if (-not $path.StartsWith("/$token/")) { Send $ctx 403 'text/plain' 'Forbidden'; continue }
      $route = $req.HttpMethod + ' ' + $path.Substring($token.Length + 2)
      $dry = $DryRun -or $req.QueryString['dry'] -eq '1'
      switch ($route) {
        'GET ' { Send $ctx 200 'text/html' ([IO.File]::ReadAllText($page, [Text.Encoding]::UTF8)) }
        'GET snapshot' {
          if ($DryRun) { $ctx.Response.Headers['X-Dry-Run'] = '1' }
          $snap = if ($From) { [IO.File]::ReadAllText($From, [Text.Encoding]::UTF8) } else { (& $tile -Json 2>$null) -join '' }
          Send $ctx 200 'application/json' (Add-SnapshotSetup $snap)
        }
        'GET layouts' {
          $key = Get-TileKnownSetupKey (Get-Plugged)
          $cfg = ConvertFrom-Json (Get-TileConfigText); $out = [ordered]@{}
          if ($key) { foreach ($sc in @($cfg.scenes)) { $out[[string]$sc.id] = [ordered]@{ layout = Resolve-TileLayout $cfg $sc $key; follows = Get-TileFollows $cfg $sc $key } } }
          Send $ctx 200 'application/json' (ConvertTo-Json -Depth 20 -Compress -InputObject $out)
        }
        'GET config' { Send $ctx 200 'application/json' (Get-TileConfigText) }
        'GET appnames' { Send $ctx 200 'application/json' (ConvertTo-Json -Compress (Get-TileAppNames)) }
        'GET state' { Send $ctx 200 'application/json' (Get-TileStateText) }
        'POST config' {
          if (-not ($body = Body $ctx $req '{')) { continue }
          try { Save-PostedConfig $body } catch { Send $ctx 400 'text/plain' "$($_.Exception.Message)"; continue }
          Send $ctx 200 'text/plain' 'Saved'
        }
        'POST layout' {
          if (-not ($body = Body $ctx $req '{')) { continue }
          $b = ConvertFrom-Json $body
          if (-not $b.scene -or -not $b.key -or $b.layout -isnot [pscustomobject]) { Send $ctx 400 'text/plain' 'Body needs scene, key and a layout object.'; continue }
          switch (Save-SceneLayout $b @(Get-Plugged)) {
            200 { Send $ctx 200 'text/plain' 'Saved' }
            404 { Send $ctx 404 'text/plain' "No scene '$($b.scene)'." }
            default { Send $ctx 409 'text/plain' 'That setup is not the one plugged in.' }
          }
        }
        'POST rename' {
          if (-not ($body = Body $ctx $req '{')) { continue }
          $b = ConvertFrom-Json $body
          if (-not $b.kind -or -not $b.id -or $b.name -isnot [string] -or -not $b.name.Trim()) { Send $ctx 400 'text/plain' 'Body needs kind, id and a name.'; continue }
          switch (Rename-Known $b) {
            200 { Send $ctx 200 'text/plain' 'Saved' }
            default { Send $ctx 404 'text/plain' "No $($b.kind) '$($b.id)'." }
          }
        }
        'POST forget' {
          if (-not ($body = Body $ctx $req '{')) { continue }
          $b = ConvertFrom-Json $body
          if (-not $b.kind -or -not $b.id) { Send $ctx 400 'text/plain' 'Body needs kind and id.'; continue }
          switch (Forget-Known $b @(Get-Plugged)) {
            200 { Send $ctx 200 'text/plain' 'Forgotten' }
            409 { Send $ctx 409 'text/plain' 'That monitor is plugged in, or that setup is the one in use.' }
            default { Send $ctx 404 'text/plain' "No $($b.kind) '$($b.id)'." }
          }
        }
        'POST preview' {
          if (-not ($body = Body $ctx $req '{')) { continue }
          Send $ctx 200 'application/json' ((& $tile -Scene $body -From $snap -Json 3>$null) -join '')
        }
        'POST scene' {
          if (-not ($body = Body $ctx $req '{')) { continue }
          $out = (& $tile -Scene $body -Json -DryRun:$dry @fromArg 3>$null) -join ''
          if (-not $dry) { $s = ConvertFrom-Json $body; $n = @((ConvertFrom-Json $out).placed | ? { $_.note -eq 'moved' }).Count; Add-TileLog ([string]$s.id) "$($s.name) applied from the app. Moved $n window(s)." }
          Send $ctx 200 'application/json' $out
        }
        'POST apply' {
          if (-not ($body = Body $ctx $req '[')) { continue }
          Send $ctx 200 'application/json' ((& $tile -Place $body -Json -DryRun:$dry @fromArg 3>$null) -join '')
        }
        'POST note' { Clear-TileNote; Send $ctx 200 'text/plain' 'Dismissed' }
        'POST quit' {
          $ctx.Response.KeepAlive = $false  # else Stop() resets the open connection before the client reads 'Bye'
          Send $ctx 200 'text/plain' 'Bye'; $run = $false
        }
        default { Send $ctx 404 'text/plain' 'Not found' }
      }
    } catch { try { Send $ctx 500 'text/plain' "$_" } catch {} }
  }
} finally { $http.Stop(); $http.Close(); if ($sampleHome) { Remove-Item -LiteralPath $sampleHome -Recurse -Force -ErrorAction SilentlyContinue } }

# Serve app.html live on 127.0.0.1, with a random token in every URL.
#   GET  /<token>/          the page
#   GET  /<token>/snapshot  tile.ps1 -Json (kept: /preview lays scenes out on this same snapshot), plus setup {key, name, follows}:
#                           the plugged-in monitor set, registered in config (decision monitor-setups). follows = the closest known
#                           setup's name while this one has no layout of its own, else ''. A snapshot whose monitors carry no ids has key ''.
#   GET  /<token>/config    config.json (scenes and settings); created from scenes.json on first run
#   POST /<token>/config    body = whole config; validated, then written. A body without monitors, setups or a scene's layouts keeps the server's.
#   GET  /<token>/layouts   {scene id: the layout Resolve-TileLayout gives that scene for the plugged-in setup}
#   POST /<token>/layout    body = {scene, key, layout}; saves that scene's layout for key. 409 and no change when key is not the plugged-in setup.
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
# The name of the closest known setup other than $key, while $key has no layout of its own in any scene (Resolve-TileLayout's closest pick:
# the most shared monitors that holds a layout, a tie to the one used last); '' when it has its own layout or none shares a monitor.
function Get-SetupFollows($cfg, [string]$key) {
  $held = @($cfg.scenes | ? { $_.layouts } | % { $_.layouts.PSObject.Properties.Name })
  if ($held -ccontains $key) { return '' }
  $mine = $cfg.setups.PSObject.Properties[$key]; if (-not $mine) { return '' }
  $best = $null; $bestN = 0; $bestUsed = ''
  foreach ($p in @($cfg.setups.PSObject.Properties | ? { $_.Name -cne $key -and $held -ccontains $_.Name })) {
    $n = @($p.Value.ids | ? { @($mine.Value.ids) -ccontains $_ }).Count
    $u = $p.Value.lastUsed; $used = if ($u -is [datetime]) { $u.ToString('s') } else { [string]$u }
    if ($n -gt $bestN -or ($n -eq $bestN -and $n -and $used -gt $bestUsed)) { $best = $p.Value.name; $bestN = $n; $bestUsed = $used }
  }
  [string]$best
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
# A posted whole config, validated, with what the page does not own put back: the server's monitors and setups, and a scene's layouts,
# when the body lacks them (the page edits scenes; layouts arrive by POST /layout). The text is saved as posted when nothing is put back.
function Save-PostedConfig([string]$body) {
  Test-TileConfig $body
  Use-TileLock {
    $new = ConvertFrom-Json $body; $cur = ConvertFrom-Json (Get-TileConfigText); $kept = $false
    foreach ($k in 'monitors', 'setups') {
      $c = $cur.PSObject.Properties[$k]
      if (-not $new.PSObject.Properties[$k] -and $c -and @($c.Value.PSObject.Properties).Count) { $new | Add-Member $k $c.Value; $kept = $true }
    }
    foreach ($sc in @($new.scenes)) {
      if ($sc.PSObject.Properties['layouts']) { continue }
      $old = @($cur.scenes | ? { $_.id -eq $sc.id })[0]
      if ($old -and $old.layouts -and @($old.layouts.PSObject.Properties).Count) { $sc | Add-Member layouts $old.layouts; $kept = $true }
    }
    Save-TileConfigText $(if ($kept) { ConvertTo-Json -Depth 20 -Compress -InputObject $new } else { $body })
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
          if ($key) { foreach ($sc in @($cfg.scenes)) { $out[[string]$sc.id] = Resolve-TileLayout $cfg $sc $key } }
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

# Serve app.html live on 127.0.0.1, with a random token in every URL.
#   GET  /<token>/          the page
#   GET  /<token>/snapshot  tile.ps1 -Json (kept: /preview lays scenes out on this same snapshot)
#   GET  /<token>/config    config.json (scenes and settings); created from scenes.json on first run
#   POST /<token>/config    body = whole config; validated, then written
#   GET  /<token>/state     state.json (scene last applied, recent log)
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
          Send $ctx 200 'application/json' $snap
        }
        'GET config' { Send $ctx 200 'application/json' (Get-TileConfigText) }
        'GET state' { Send $ctx 200 'application/json' (Get-TileStateText) }
        'POST config' {
          if (-not ($body = Body $ctx $req '{')) { continue }
          try { Save-TileConfigText $body } catch { Send $ctx 400 'text/plain' "$($_.Exception.Message)"; continue }
          Send $ctx 200 'text/plain' 'Saved'
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

# Serve sandbox.html live on 127.0.0.1, with a random token in every URL.
#   GET  /<token>/          the page
#   GET  /<token>/snapshot  tile.ps1 -Json
#   POST /<token>/apply     body = -Place array; answers tile.ps1 -Place -Json results. ?dry=1 = -DryRun.
#   POST /<token>/quit      stop the server
# Prints the URL as its first line, opens the browser (unless -NoBrowser), stops on Ctrl+C or /quit.
# -DryRun: every apply is a dry run (for tests).
param([switch]$NoBrowser, [switch]$DryRun)

$tile = Join-Path $PSScriptRoot 'tile.ps1'
$page = Join-Path $PSScriptRoot 'sandbox.html'
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
  $ctx.Response.OutputStream.Write($b, 0, $b.Length); $ctx.Response.Close()
}

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
      switch ($route) {
        'GET ' { Send $ctx 200 'text/html' ([IO.File]::ReadAllText($page, [Text.Encoding]::UTF8)) }
        'GET snapshot' { Send $ctx 200 'application/json' ((& $tile -Json 2>$null) -join '') }
        'POST apply' {
          $body = [IO.StreamReader]::new($req.InputStream, [Text.Encoding]::UTF8).ReadToEnd()
          # An empty -Place would fall through to grid tiling, which moves windows.
          if (-not $body.Trim().StartsWith('[')) { Send $ctx 400 'text/plain' 'Body must be a JSON array.'; continue }
          try { $null = ConvertFrom-Json $body -ErrorAction Stop } catch { Send $ctx 400 'text/plain' "Bad JSON: $($_.Exception.Message)"; continue }
          $dry = $DryRun -or $req.QueryString['dry'] -eq '1'
          Send $ctx 200 'application/json' ((& $tile -Place $body -Json -DryRun:$dry 3>$null) -join '')
        }
        'POST quit' {
          $ctx.Response.KeepAlive = $false  # else Stop() resets the open connection before the client reads 'Bye'
          Send $ctx 200 'text/plain' 'Bye'; $run = $false
        }
        default { Send $ctx 404 'text/plain' 'Not found' }
      }
    } catch { try { Send $ctx 500 'text/plain' "$_" } catch {} }
  }
} finally { $http.Stop(); $http.Close() }

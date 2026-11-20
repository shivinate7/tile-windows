# A stand-in for serve.ps1 in front of a real one, for the preview failure case in test/run.ps1. Every request goes on to -Target,
# except a POST to .../preview for the scene -Fail: that gets a 500 with a message, and each forced failure is added to -CountFile.
# Prints its own tokened URL on its first line, as serve.ps1 does, and runs until its process is killed.
param([string]$Target, [string]$Fail, [string]$CountFile)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding $false
$origin = $Target -replace '^(https?://[^/]+).*$', '$1'
$token = $Target -replace '^https?://[^/]+/', ''
$probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
$base = "http://127.0.0.1:$port/"
$http = [Net.HttpListener]::new(); $http.Prefixes.Add($base); $http.Start()
"$base$token"
# Passes the X- headers on: the page reads X-Dry-Run (its self-tests run only on a dry-run server) and X-Tile-Note.
function Reply($res, [int]$code, [string]$type, [byte[]]$bytes, $hdrs) {
  $res.StatusCode = $code; if ($type) { $res.ContentType = $type }
  if ($hdrs) { foreach ($k in @($hdrs.Keys)) { if ($k -like 'X-*') { $res.Headers[$k] = $hdrs[$k] } } }
  $res.ContentLength64 = $bytes.Length; $res.OutputStream.Write($bytes, 0, $bytes.Length); $res.Close()
}
while ($true) {
  $ctx = $http.GetContext(); $req = $ctx.Request; $res = $ctx.Response
  try {
    $in = $null
    if ($req.HasEntityBody) { $ms = New-Object IO.MemoryStream; $req.InputStream.CopyTo($ms); $in = $ms.ToArray() }
    $id = $null
    if ($req.HttpMethod -eq 'POST' -and $req.RawUrl -like '*/preview' -and $in) { try { $id = ($utf8.GetString($in) | ConvertFrom-Json).id } catch { } }
    if ($id -and $id -eq $Fail) {
      Add-Content -LiteralPath $CountFile -Value $id -Encoding ASCII
      Reply $res 500 'text/plain; charset=utf-8' ($utf8.GetBytes('Preview failed for the test.')) $null
      continue
    }
    $fwd = @{ Uri = $origin + $req.RawUrl; Method = $req.HttpMethod; UseBasicParsing = $true }
    if ($in) { $fwd.Body = $in; $fwd.ContentType = $req.ContentType }
    try {
      $r = Invoke-WebRequest @fwd
      Reply $res ([int]$r.StatusCode) ($r.Headers['Content-Type']) ($r.RawContentStream.ToArray()) $r.Headers
    } catch {
      $er = $_.Exception.Response
      if ($null -eq $er) { Reply $res 502 'text/plain; charset=utf-8' ($utf8.GetBytes('No answer from the server.')) $null }
      else {
        # The error answer is read and closed, so its connection goes back to the pool.
        $sr = New-Object IO.StreamReader($er.GetResponseStream(), $utf8); $text = $sr.ReadToEnd(); $sr.Close(); $er.Close()
        Reply $res ([int]$er.StatusCode) ($er.ContentType) ($utf8.GetBytes($text)) $er.Headers
      }
    }
  } catch { try { $res.Abort() } catch { } }
}

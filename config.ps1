# The one home for scenes and settings: %USERPROFILE%\.tile-windows\config.json.
# Dot-sourced by tile.ps1, serve.ps1 and tray.ps1. The first read copies scenes.json (the starters).
$TileHome = Join-Path $env:USERPROFILE '.tile-windows'
$TileConfig = Join-Path $TileHome 'config.json'
$TileState = Join-Path $TileHome 'state.json'
$TileStarters = Join-Path $PSScriptRoot 'scenes.json'
$TileUtf8 = New-Object Text.UTF8Encoding $false

# Write next to the target, then swap, so a crash mid-write cannot lose the file.
function Write-TileFile([string]$path, [string]$text) {
  if (-not (Test-Path -LiteralPath $TileHome)) { New-Item -ItemType Directory -Path $TileHome | Out-Null }
  $tmp = "$path.tmp"; [IO.File]::WriteAllText($tmp, $text, $TileUtf8)
  if (Test-Path -LiteralPath $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
}

function Get-TileConfigText {
  if (-not (Test-Path -LiteralPath $TileConfig)) { Save-TileConfigText ([IO.File]::ReadAllText($TileStarters, $TileUtf8)) }
  [IO.File]::ReadAllText($TileConfig, $TileUtf8)
}

# Validates, then writes the text as given: a round trip through objects would cut nesting (ConvertTo-Json depth).
function Save-TileConfigText([string]$text) {
  $c = ConvertFrom-Json $text -ErrorAction Stop
  if (-not ($c.scenes -is [array]) -or @($c.scenes | ? { -not $_.id -or -not $_.name -or -not $_.grids }).Count) { throw 'Config needs a scenes array; each scene needs id, name and grids.' }
  if (@($c.scenes.id | Select-Object -Unique).Count -ne @($c.scenes).Count) { throw 'Scene ids must be unique.' }
  Write-TileFile $TileConfig $text
}

# A scene by id or name, with the config's app -> category map attached as .cats.
function Get-TileScene([string]$key, $config) {
  if (-not $config) { $config = ConvertFrom-Json (Get-TileConfigText) }
  $s = @($config.scenes | ? { $_.id -eq $key -or $_.name -eq $key })[0]
  if (-not $s) { throw "No scene named '$key'. Scenes: $(@($config.scenes.name) -join ', ')." }
  $s | Add-Member -Force cats $config.cats; $s | Add-Member -Force categories $config.categories; $s
}

# state.json: the scene last applied and a short log, for the page and the tray.
function Get-TileStateText { if (Test-Path -LiteralPath $TileState) { [IO.File]::ReadAllText($TileState, $TileUtf8) } else { '{"active":"","log":[]}' } }
function Add-TileLog([string]$active, [string]$text) {
  $s = ConvertFrom-Json (Get-TileStateText)
  $log = @([pscustomobject]@{ t = (Get-Date).ToString('yyyy-MM-dd HH:mm'); x = $text }) + @($s.log | Select-Object -First 19)
  Write-TileFile $TileState (ConvertTo-Json -Depth 4 -Compress ([pscustomobject]@{ active = $active; log = $log }))
}

# Install Tile Windows for this user. No admin rights.
#   irm https://raw.githubusercontent.com/shivinate7/tile-windows/main/install.ps1 | iex
# From a clone: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-NoStartup] [-NoLaunch]
# Puts the app in %USERPROFILE%\.tile-windows\app, adds a "Tile Windows" Start menu shortcut and, unless
# -NoStartup, starts the tray agent at login. Your scenes stay in %USERPROFILE%\.tile-windows\config.json.
# A piped install takes no parameters, so environment variables stand in for them:
#   TILE_NO_STARTUP=1, TILE_NO_LAUNCH=1, TILE_SOURCE=<folder to copy from instead of GitHub>.
param([switch]$NoStartup, [switch]$NoLaunch)
& {
  $ErrorActionPreference = 'Stop'
  $files = 'tile.ps1', 'serve.ps1', 'app.html', 'config.ps1', 'scenes.json', 'tray.ps1', 'uninstall.ps1', 'SKILL.md', 'README.md'
  $app = Join-Path $env:USERPROFILE '.tile-windows\app'
  $src = if ($env:TILE_SOURCE) { $env:TILE_SOURCE } elseif ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'tile.ps1'))) { $PSScriptRoot }
  New-Item -ItemType Directory -Force -Path $app | Out-Null
  if ($src) { foreach ($f in $files) { Copy-Item -LiteralPath (Join-Path $src $f) -Destination (Join-Path $app $f) -Force } }
  else {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    foreach ($f in $files) { Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/shivinate7/tile-windows/main/$f" -OutFile (Join-Path $app $f) }
  }
  Get-ChildItem -LiteralPath $app | Unblock-File

  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  $sh = New-Object -ComObject WScript.Shell
  function Link($path, $flags) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    $l = $sh.CreateShortcut($path); $l.TargetPath = $ps; $l.WorkingDirectory = $app; $l.WindowStyle = 7
    $l.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$app\tray.ps1`" $flags"
    $l.IconLocation = "$env:SystemRoot\System32\imageres.dll,174"; $l.Description = 'Arrange your windows into grids and scenes.'; $l.Save()
  }
  Link (Join-Path $programs 'Tile Windows.lnk') '-Open'
  $startup = Join-Path $programs 'Startup\Tile Windows tray.lnk'
  if ($NoStartup -or $env:TILE_NO_STARTUP) { if (Test-Path -LiteralPath $startup) { Remove-Item -LiteralPath $startup } } else { Link $startup '' }

  "Installed Tile Windows to $app."
  "Open it from the Start menu: Tile Windows."
  if (-not ($NoLaunch -or $env:TILE_NO_LAUNCH)) { Start-Process $ps -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$app\tray.ps1`"", '-Open' }
}

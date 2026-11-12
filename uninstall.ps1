# Remove Tile Windows for this user: stops the tray agent, removes the app folder, both shortcuts and the tilewindows:// link.
# Keeps your scenes (%USERPROFILE%\.tile-windows\config.json) unless -Purge.
#   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.tile-windows\app\uninstall.ps1" [-Purge]
param([switch]$Purge)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tray.ps1') -Lib
try { [void][Threading.EventWaitHandle]::OpenExisting((TrayName 'Quit')).Set(); Start-Sleep -Seconds 2 } catch [Threading.WaitHandleCannotBeOpenedException] {}
$programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
foreach ($l in (Join-Path $programs 'Tile Windows.lnk'), (Join-Path $programs 'Startup\Tile Windows tray.lnk')) { if (Test-Path -LiteralPath $l) { Remove-Item -LiteralPath $l } }
# The tilewindows:// link (TILE_NO_REGISTRY=1 skips every registry write and delete; tests set it).
if (-not $env:TILE_NO_REGISTRY) { $linkRoot = @(Get-UndoProtocolKeys)[0].path; if (Test-Path -LiteralPath $linkRoot) { Remove-Item -LiteralPath $linkRoot -Recurse -Force } }
$app = Join-Path $TileHome 'app'
if (Test-Path -LiteralPath $app) { Remove-Item -LiteralPath $app -Recurse -Force }
if ($Purge -and (Test-Path -LiteralPath $TileHome)) { Remove-Item -LiteralPath $TileHome -Recurse -Force }
"Removed Tile Windows." + $(if (-not $Purge) { " Your scenes are still in $TileConfig." } else { '' })

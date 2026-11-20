# Install Tile Windows for this user. No admin rights.
#   irm https://raw.githubusercontent.com/shivinate7/tile-windows/main/install.ps1 | iex
# From a clone: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-NoStartup] [-NoLaunch]
# Puts the app in %USERPROFILE%\.tile-windows\app, adds a "Tile Windows" Start menu shortcut and, unless
# -NoStartup, starts the tray agent at login. Your scenes stay in %USERPROFILE%\.tile-windows\config.json.
# A piped install takes no parameters, so environment variables stand in for them:
#   TILE_NO_STARTUP=1, TILE_NO_LAUNCH=1, TILE_SOURCE=<folder to copy from instead of GitHub>.
# TILE_NO_REGISTRY=1 skips every registry write (the tilewindows:// link that the run toast's Undo button opens); tests set it.
param([switch]$NoStartup, [switch]$NoLaunch)
& {
  $ErrorActionPreference = 'Stop'
  $files = 'tile.ps1', 'serve.ps1', 'app.html', 'config.ps1', 'scenes.json', 'tray.ps1', 'uninstall.ps1', 'SKILL.md', 'README.md'
  $home_ = Join-Path $env:USERPROFILE '.tile-windows'; $app = Join-Path $home_ 'app'
  $src = if ($env:TILE_SOURCE) { $env:TILE_SOURCE } elseif ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'tile.ps1'))) { $PSScriptRoot }
  # Stage the new copy beside the old one; a failed download leaves the old install as it was.
  $new = Join-Path $home_ "app.new-$PID"
  New-Item -ItemType Directory -Force -Path $new | Out-Null
  try {
    if ($src) { foreach ($f in $files) { Copy-Item -LiteralPath (Join-Path $src $f) -Destination (Join-Path $new $f) -Force } }
    else {
      [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
      foreach ($f in $files) { Invoke-WebRequest -UseBasicParsing "https://raw.githubusercontent.com/shivinate7/tile-windows/main/$f" -OutFile (Join-Path $new $f) }
    }
    Get-ChildItem -LiteralPath $new | Unblock-File
  } catch { Remove-Item -LiteralPath $new -Recurse -Force -ErrorAction SilentlyContinue; throw }
  # A running tray agent holds the old code: ask it to quit, and wait for it, before the swap.
  . (Join-Path $new 'tray.ps1') -Lib
  try { [void][Threading.EventWaitHandle]::OpenExisting((TrayName 'Quit')).Set() } catch [Threading.WaitHandleCannotBeOpenedException] {}
  for ($i = 0; $i -lt 50; $i++) { $m = $null; if (-not [Threading.Mutex]::TryOpenExisting((TrayName 'Agent'), [ref]$m)) { break }; $m.Dispose(); Start-Sleep -Milliseconds 100 }
  # The agent lets go of its mutex before its process exits, and the process still holds the app folder until then. The agent
  # writes its process id to tray.pid at start, so wait (up to 10 s) for that process to end. Only a PowerShell process counts, since the id may have been reused.
  $trayPid = 0
  try { [void][int]::TryParse(([IO.File]::ReadAllText((Join-Path $home_ 'tray.pid'))).Trim(), [ref]$trayPid) } catch {}
  # The wait is best-effort: a process this user cannot open or wait on (a stale id) skips it, and the rename retry below still covers a late exit.
  if ($trayPid -gt 0 -and $trayPid -ne $PID) {
    try {
      $tp = Get-Process -Id $trayPid -ErrorAction Stop
      if ($tp.ProcessName -match '^(powershell|pwsh)$') { [void]$tp.WaitForExit(10000) }
    } catch {}
  }
  # Swap by renames: the old app is put back if any step fails, so a failed install leaves it working.
  $old = Join-Path $home_ "app.old-$PID"
  try {
    if (Test-Path -LiteralPath $app) {
      # A process with the app folder as its working directory (a board, a terminal or Explorer window) makes the rename fail until it lets go: retry for about 15 s.
      $deadline = [Diagnostics.Stopwatch]::StartNew()
      while ($true) {
        try { Rename-Item -LiteralPath $app -NewName (Split-Path $old -Leaf); break }
        catch [IO.IOException], [UnauthorizedAccessException] {
          # Only a lock clears by waiting: sharing violation (Win32 32), lock violation (33) or a refused handle. Any other failure (say, app.old-<pid> already exists) cannot.
          $hr = $_.Exception.HResult
          $isLock = $_.Exception -is [UnauthorizedAccessException] -or ((($hr -shr 16) -band 0xFFFF) -eq 0x8007 -and (($hr -band 0xFFFF) -in 32, 33))
          if (-not $isLock) { throw "Could not move the old app folder aside: $($_.Exception.Message)" }
          if ($deadline.ElapsedMilliseconds -ge 15000) { throw "The app folder is in use, most likely by a running board or a terminal or Explorer window open in it. Close those and run the install again. ($($_.Exception.Message))" }
          Start-Sleep -Milliseconds 250
        }
      }
    }
    # The morning task writes agenda.json in the app folder and the tray reads it there, so carry the old file into the new copy (a byte copy).
    # A copy that fails warns and the install goes on: the morning task writes the file again.
    $oldAgenda = Join-Path $old 'agenda.json'
    if (Test-Path -LiteralPath $oldAgenda) {
      try { Copy-Item -LiteralPath $oldAgenda -Destination (Join-Path $new 'agenda.json') -Force } catch { Write-Warning "agenda.json was not carried over: $($_.Exception.Message)" }
    }
    if ($env:TILE_TEST_SWAP_FAIL) { throw 'Test: the swap failed.' }  # test seam: a failure between the renames
    Rename-Item -LiteralPath $new -NewName 'app'
  } catch {
    if ((Test-Path -LiteralPath $old) -and -not (Test-Path -LiteralPath $app)) { Rename-Item -LiteralPath $old -NewName 'app' }
    Remove-Item -LiteralPath $new -Recurse -Force -ErrorAction SilentlyContinue; throw
  }
  Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue

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
  # The toast header says "Tile Windows" only when the Start shortcut carries the AppUserModelID the tray sends toasts as (TileShortcut is tray.ps1's).
  try { [TileShortcut]::SetAppId((Join-Path $programs 'Tile Windows.lnk'), $TileAppId) } catch { Write-Warning "The run toast will not say Tile Windows: $($_.Exception.Message)" }
  $startup = Join-Path $programs 'Startup\Tile Windows tray.lnk'
  if ($NoStartup -or $env:TILE_NO_STARTUP) { if (Test-Path -LiteralPath $startup) { Remove-Item -LiteralPath $startup } } else { Link $startup '' }

  # The link the run toast's Undo button opens: tilewindows://undo?run=<id> runs tray.ps1, which tells the running agent.
  if (-not $env:TILE_NO_REGISTRY) {
    foreach ($k in (Get-UndoProtocolKeys $app)) {
      if (-not (Test-Path -LiteralPath $k.path)) { New-Item -Path $k.path -Force | Out-Null }
      Set-ItemProperty -LiteralPath $k.path -Name $k.name -Value $k.value
    }
  }

  "Installed Tile Windows to $app."
  "Open it from the Start menu: Tile Windows."
  if (-not ($NoLaunch -or $env:TILE_NO_LAUNCH)) {
    # The tray must start like one from the Start menu, with no agent-shell marker: tile.ps1's live-move guard would refuse its live applies.
    # The names are the ones that guard reads (TILE_TEST_SUITE is left alone, so a tray a test starts stays guarded). The child copies this
    # process's environment at launch, so the markers are cleared around the launch only and put back for the caller's shell.
    $agentMarkers = 'CLAUDECODE'
    $held = @{}; foreach ($m in $agentMarkers) { $held[$m] = [Environment]::GetEnvironmentVariable($m) }
    try {
      foreach ($m in $agentMarkers) { [Environment]::SetEnvironmentVariable($m, $null) }
      Start-Process $ps -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$app\tray.ps1`"", '-Open'
    } finally {
      foreach ($m in $agentMarkers) { [Environment]::SetEnvironmentVariable($m, $held[$m]) }
    }
  }
}

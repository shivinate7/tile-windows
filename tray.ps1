# Tile Windows tray agent: an icon in the notification area.
#   Menu: Open Tile Windows, Apply scene >, Quit. Double-click opens the app.
#   Applies scenes on their trigger: a schedule (days + time), or when the monitor set changes.
# -Open: open the app (starts the agent first if it is not running).
# -NoIcon: run without the icon (tests). -NoApply: every apply is a dry run (tests).
# -Lib: define the functions and return (tests dot-source it).
# One agent per profile. Signal the Quit event (as uninstall.ps1 does) to stop it.
param([switch]$Open, [switch]$NoIcon, [switch]$NoApply, [switch]$Lib)
. (Join-Path $PSScriptRoot 'config.ps1')

# Named objects are per profile, so a test profile never talks to the real agent.
function TrayName([string]$kind) {
  $h = [BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($TileHome.ToLowerInvariant()))).Replace('-', '').Substring(0, 12)
  "Local\TileWindows-$kind-$h"
}
# Scenes due now on a schedule. $fired: scene id -> 'yyyy-MM-dd HH:mm' last fired, so a scene fires once a minute at most.
function Get-DueScenes($config, [datetime]$now, $fired) {
  $stamp = $now.ToString('yyyy-MM-dd HH:mm'); $day = [int]$now.DayOfWeek; $hm = $now.ToString('HH:mm')
  @($config.scenes | ? { $_.trigger.type -eq 'time' -and @($_.trigger.days) -contains $day -and $_.trigger.time -eq $hm -and $fired[$_.id] -ne $stamp })
}
# The monitor set as one string: a change in it (a monitor added, removed or moved) fires 'display' scenes.
function Get-MonitorKey($screens) { (@($screens | % { "$($_.DeviceName)=$($_.Bounds.Width)x$($_.Bounds.Height)@$($_.Bounds.X),$($_.Bounds.Y)" }) | Sort-Object) -join ';' }
function Get-DisplayScenes($config) { @($config.scenes | ? { $_.trigger.type -eq 'display' }) }
if ($Lib) { return }

$quitName = TrayName 'Quit'; $openName = TrayName 'Open'
$created = $false; $mutex = New-Object Threading.Mutex($true, (TrayName 'Agent'), [ref]$created)
if (-not $created) { if ($Open) { $e = [Threading.EventWaitHandle]::OpenExisting($openName); [void]$e.Set() }; return }
$quitEv = New-Object Threading.EventWaitHandle($false, 'AutoReset', $quitName)
$openEv = New-Object Threading.EventWaitHandle($false, 'AutoReset', $openName)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# The handler only sets a flag: SystemEvents may call it off the PowerShell thread. The timer does the work.
Add-Type @'
public static class TileDisplayWatch {
  public static volatile bool Dirty;
  public static void Start() { Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (s, e) => { Dirty = true; }; }
}
'@
[TileDisplayWatch]::Start()
$tile = Join-Path $PSScriptRoot 'tile.ps1'; $serve = Join-Path $PSScriptRoot 'serve.ps1'
$srv = $null; $url = ''; $fired = @{}; $lastKey = Get-MonitorKey ([Windows.Forms.Screen]::AllScreens); $dirtyAt = $null

function Note([string]$text) { if ($icon) { $icon.ShowBalloonTip(4000, 'Tile Windows', $text, 'Info') } }
function Apply-Scene($s, [string]$why) {
  try {
    $r = (& $tile -Scene $s.id -Json -DryRun:$NoApply 3>$null) -join '' | ConvertFrom-Json
    $n = @($r.placed | ? { $_.note -eq 'moved' }).Count
    $msg = "$($s.name) applied $why. Moved $n window(s)."
    if (-not $NoApply) { Add-TileLog $s.id $msg }
    Note $msg
  } catch { Note "$($s.name) failed: $($_.Exception.Message)" }
}
function Open-App {
  if (-not $srv -or $srv.HasExited) {
    $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass -File `"$serve`" -NoBrowser"
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
    $script:srv = [Diagnostics.Process]::Start($psi); $script:url = $srv.StandardOutput.ReadLine()
  }
  if ($url -match '^http://127\.0\.0\.1:') { Start-Process $url } else { Note 'The app server did not start.' }
}
function Stop-App { if ($srv -and -not $srv.HasExited) { try { [void](Invoke-WebRequest -UseBasicParsing "${url}quit" -Method Post -Body 'quit' -TimeoutSec 3) } catch {}; if (-not $srv.WaitForExit(3000)) { $srv.Kill() } } }

$menu = New-Object Windows.Forms.ContextMenuStrip
$openItem = $menu.Items.Add('Open Tile Windows'); $openItem.Font = New-Object Drawing.Font($openItem.Font, [Drawing.FontStyle]::Bold)
$openItem.add_Click({ Open-App })
$scenesItem = New-Object Windows.Forms.ToolStripMenuItem 'Apply scene'; [void]$menu.Items.Add($scenesItem)
[void]$menu.Items.Add('-')
$quitItem = $menu.Items.Add('Quit'); $quitItem.add_Click({ [Windows.Forms.Application]::Exit() })
# Rebuild the scene list each time the menu opens, so it follows config.json.
$menu.add_Opening({
  $scenesItem.DropDownItems.Clear()
  try { $cfg = ConvertFrom-Json (Get-TileConfigText) } catch { $cfg = $null }
  foreach ($s in @($cfg.scenes)) { $it = $scenesItem.DropDownItems.Add($s.name); $it.Tag = $s; $it.add_Click({ param($o) Apply-Scene $o.Tag 'from the tray' }) }
})

$icon = $null
if (-not $NoIcon) {
  # A three-pane glyph drawn at run time: no icon file to ship.
  $bmp = New-Object Drawing.Bitmap 16, 16; $g = [Drawing.Graphics]::FromImage($bmp); $g.Clear([Drawing.Color]::Transparent)
  $br = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(31, 107, 255))
  $g.FillRectangle($br, 1, 2, 6, 5); $g.FillRectangle($br, 9, 2, 6, 5); $g.FillRectangle($br, 1, 9, 14, 5); $g.Dispose()
  $icon = New-Object Windows.Forms.NotifyIcon
  $icon.Icon = [Drawing.Icon]::FromHandle($bmp.GetHicon()); $icon.Text = 'Tile Windows'; $icon.ContextMenuStrip = $menu; $icon.Visible = $true
  $icon.add_DoubleClick({ Open-App })
}

$timer = New-Object Windows.Forms.Timer; $timer.Interval = 1000
$timer.add_Tick({
  if ($quitEv.WaitOne(0)) { [Windows.Forms.Application]::Exit(); return }
  if ($openEv.WaitOne(0)) { Open-App }
  try { $cfg = ConvertFrom-Json (Get-TileConfigText) } catch { return }
  foreach ($s in (Get-DueScenes $cfg (Get-Date) $fired)) { $fired[$s.id] = (Get-Date).ToString('yyyy-MM-dd HH:mm'); Apply-Scene $s 'on schedule' }
  # Wait for the display to settle (2 s after the last change), then act only if the monitor set changed.
  if ([TileDisplayWatch]::Dirty) { [TileDisplayWatch]::Dirty = $false; $script:dirtyAt = Get-Date }
  if ($dirtyAt -and ((Get-Date) - $dirtyAt).TotalSeconds -ge 2) {
    $script:dirtyAt = $null; $k = Get-MonitorKey ([Windows.Forms.Screen]::AllScreens)
    if ($k -ne $lastKey) { $script:lastKey = $k; foreach ($s in (Get-DisplayScenes $cfg)) { Apply-Scene $s 'because the monitors changed' } }
  }
})
$timer.Start()
if ($Open) { Open-App }
try { [Windows.Forms.Application]::Run() }
finally {
  $timer.Stop(); Stop-App
  if ($icon) { $icon.Visible = $false; $icon.Dispose() }
  $mutex.ReleaseMutex(); $mutex.Dispose(); $quitEv.Dispose(); $openEv.Dispose()
}

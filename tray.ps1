# Tile Windows tray agent: an icon in the notification area.
#   Menu: Open Tile Windows, Apply Scene >, Quit. Double-click opens the app.
#   Applies scenes on their trigger: a schedule (days + time), when the monitor set changes, or when a
#   Teams call starts (and, if the scene says so, goes back to the scene before when the call ends).
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

# Is a Teams call on? $mic: [{name, stop}] from Windows' microphone privacy store (Get-MicUsage); stop = 0
# means the app holds the microphone now. $null means the store could not be read: only then do the
# Teams window titles decide, and only a title in Teams' own meeting-window form counts.
function Test-TeamsCall($mic, $wins) {
  if ($null -ne $mic) { return [bool]@($mic | ? { $_.name -match '(?i)(^|[#\\])(ms-teams|teams)\.exe$|^MSTeams_' -and [int64]$_.stop -eq 0 }).Count }
  [bool]@($wins | ? { $_.app -match '(?i)^(ms-teams|teams)$' -and $_.title -match '(?i)^(meeting|call)( (with|in) [^|]+)? \| Microsoft Teams$' }).Count
}
# What a change in call state does. Returns {apply: scene id or '', back: scene id to remember}.
# Call starts: apply the first 'call' scene and remember the scene on screen. Call ends: if that scene
# has trigger.back, apply the remembered one.
function Step-CallTrigger([bool]$was, [bool]$now, $config, [string]$active, [string]$before) {
  $s = @($config.scenes | ? { $_.trigger.type -eq 'call' })[0]
  if (-not $s -or $was -eq $now) { return [pscustomobject]@{ apply = ''; back = $before } }
  if ($now) { return [pscustomobject]@{ apply = $s.id; back = $(if ($active -ne $s.id) { $active } else { $before }) } }
  [pscustomobject]@{ apply = $(if ($s.trigger.back -and $before -and @($config.scenes.id) -contains $before) { $before } else { '' }); back = '' }
}
# What the tick remembers between ticks.
function New-TrayState { [pscustomobject]@{ fired = @{}; lastKey = $null; inCall = $null; streak = 0; before = ''; callSet = $null } }
# One tick of the agent, with no side effects but on $s. Returns the scenes to apply: [{id, why}].
# $key: the monitor key once the display has settled, else $null. $call: a call reading, or $null (not polled).
# The first key and the first call reading only seed $s, so starting the agent (or restarting it mid-call)
# applies nothing. A call starts or ends only after 2 readings in a row agree.
function Step-Tray($s, [datetime]$now, $cfg, $key, $call, [string]$active) {
  $out = @()
  foreach ($x in (Get-DueScenes $cfg $now $s.fired)) { $s.fired[$x.id] = $now.ToString('yyyy-MM-dd HH:mm'); $out += [pscustomobject]@{ id = $x.id; why = 'on schedule' } }
  if ($key) {
    $d = @(Get-DisplayScenes $cfg)[0]
    if ($s.lastKey -and $key -ne $s.lastKey -and $d) { $out += [pscustomobject]@{ id = $d.id; why = 'because the monitors changed' } }
    $s.lastKey = $key
  }
  # A changed set of call scenes starts the call reading over (seed again, no pending streak).
  $set = @($cfg.scenes | ? { $_.trigger.type -eq 'call' } | % { "$($_.id):$([bool]$_.trigger.back)" }) -join ','
  if ($set -ne $s.callSet) { $s.callSet = $set; $s.inCall = $null; $s.streak = 0; $s.before = '' }
  if ($null -ne $call) {
    if ($null -eq $s.inCall) { $s.inCall = [bool]$call }
    elseif ([bool]$call -eq $s.inCall) { $s.streak = 0 }
    elseif (++$s.streak -ge 2) {
      $st = Step-CallTrigger $s.inCall ([bool]$call) $cfg $active $s.before
      $s.inCall = [bool]$call; $s.streak = 0; $s.before = $st.back
      if ($st.apply) { $out += [pscustomobject]@{ id = $st.apply; why = $(if ($call) { 'because a Teams call started' } else { 'because the call ended' }) } }
    }
  }
  $out
}
# Microphone use per app, from HKCU ...\CapabilityAccessManager\ConsentStore\microphone: desktop apps under
# NonPackaged (key name = exe path with # for \), Store apps (new Teams: MSTeams_8wekyb3d8bbwe) by package.
# $null when the store cannot be read.
function Get-MicUsage {
  $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
  if (-not (Test-Path -LiteralPath $k)) { return $null }
  , @(Get-ChildItem -LiteralPath $k, "$k\NonPackaged" -ErrorAction SilentlyContinue | ? { $_.PSChildName -ne 'NonPackaged' } |
    % { $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue; if ($p -and $null -ne $p.LastUsedTimeStop) { [pscustomobject]@{ name = $_.PSChildName; stop = [int64]$p.LastUsedTimeStop } } })
}
function Get-TeamsWindows { @(Get-Process ms-teams, Teams -ErrorAction SilentlyContinue | ? { $_.MainWindowTitle } | % { [pscustomobject]@{ app = $_.Name; title = $_.MainWindowTitle } }) }
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
$srv = $null; $url = ''; $state = New-TrayState; $dirtyAt = $null; $tick = 0; $first = $true

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
$scenesItem = New-Object Windows.Forms.ToolStripMenuItem 'Apply Scene'; [void]$menu.Items.Add($scenesItem)
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
  # The monitor key: on the first tick (seeds), then 2 s after the display last changed.
  if ([TileDisplayWatch]::Dirty) { [TileDisplayWatch]::Dirty = $false; $script:dirtyAt = Get-Date }
  $key = $null
  if ($first -or ($dirtyAt -and ((Get-Date) - $dirtyAt).TotalSeconds -ge 2)) { $script:first = $false; $script:dirtyAt = $null; $key = Get-MonitorKey ([Windows.Forms.Screen]::AllScreens) }
  # Teams calls: poll every 3 s, only while some scene uses the trigger.
  $call = $null
  if ((++$script:tick % 3) -eq 0 -and @($cfg.scenes | ? { $_.trigger.type -eq 'call' }).Count) { $call = Test-TeamsCall (Get-MicUsage) (Get-TeamsWindows) }
  $active = try { (ConvertFrom-Json (Get-TileStateText)).active } catch { '' }
  # A read here recovered from a bad file: the page shows the note until dismissed; the tray says it once.
  if ($TileNote) { Note $TileNote; $script:TileNote = '' }
  foreach ($a in (Step-Tray $state (Get-Date) $cfg $key $call $active)) { $sc = @($cfg.scenes | ? { $_.id -eq $a.id })[0]; if ($sc) { Apply-Scene $sc $a.why } }
})
$timer.Start()
if ($Open) { Open-App }
try { [Windows.Forms.Application]::Run() }
finally {
  $timer.Stop(); Stop-App
  if ($icon) { $icon.Visible = $false; $icon.Dispose() }
  $mutex.ReleaseMutex(); $mutex.Dispose(); $quitEv.Dispose(); $openEv.Dispose()
}

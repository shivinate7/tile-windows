# Tile visible windows of the named apps into a grid on one monitor.
# -Proc order = tile order (e.g. -Proc msedge,claude puts the browser first).
# -Monitor: 'wide' (widest), 'laptop' (smallest), 'tall' (portrait), or a 0-based index.
# -Pin 'chrome:RFP=1;ms-teams=5+10': put an app's first window (title containing the text after ':', if given) in given slots (spans the box around them).
# -Json: print monitors + windows as JSON (default -Proc '*'), move nothing.
# -Place '<json>' / -PlaceFile <path>: move windows to [{app,title,x,y,w,h,id?}] screen rects (match id, else app + title). Honors -DryRun.
#   With -Json, print one result per entry as JSON instead of text.
# Slots number row by row from 1 (top-left).
# -Cells n: grid with n cells (rows picked for you). Ultrawide default = 10 cells (5x2).
param([int]$Cols = 0, [int]$Rows = 0, [int]$Cells = 0, [string[]]$Proc = @('claude'), [string]$Monitor = 'wide', [string]$Pin = '', [switch]$List, [switch]$DryRun, [switch]$Json, [string]$Place = '', [string]$PlaceFile = '', [switch]$Default,
  # -Order 'a|b|c': windows whose title contains a, then b, then c come first, in that order.
  [string]$Order = '',
  [string[]]$Skip = @('TextInputHost', 'PowerToys*', 'ShellExperienceHost', 'SearchHost', 'StartMenuExperienceHost', 'LockApp'))

Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int n);
  // A real app window: visible, titled, not owned by another window, not a tool window, not cloaked (hidden UWP shell).
  public static bool IsAppWindow(IntPtr h) {
    int c; DwmGetWindowAttribute(h, 14, out c, 4);
    return IsWindowVisible(h) && GetWindowTextLength(h) > 0 && GetWindow(h, 4) == IntPtr.Zero
        && (GetWindowLong(h, -20) & 0x80) == 0 && c == 0;
  }
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
}
'@

# Default setup: portrait = Outlook classic (top) + Teams (bottom); laptop = new Outlook;
# ultrawide 5x2 = Claude, then Chrome, then everything else.
if ($Default) {
  $me = $PSCommandPath; $x = @{}; if ($DryRun) { $x.DryRun = $true }
  & $me -Monitor tall -Cols 1 -Rows 2 -Proc '' -Pin 'outlook:- Outlook=1;ms-teams=2' @x
  & $me -Monitor laptop -Cols 1 -Rows 1 -Proc '' -Pin 'olk=1' @x
  & $me -Monitor wide -Cols 5 -Rows 2 -Proc 'claude,chrome,*' -Skip ($Skip + 'outlook', 'olk', 'ms-teams') @x
  return
}
if (($Json -or $Place -or $PlaceFile) -and -not $PSBoundParameters.ContainsKey('Proc')) { $Proc = @('*') }
$Proc = @($Proc -split ',' | ? { $_ })  # -File passes 'a,b' as one string
$pins = @(); foreach ($e in ($Pin -split ';' | ? { $_ })) { $a, $b = $e -split '='; $app, $t = $a.Trim() -split ':', 2; $pins += [pscustomobject]@{ App = $app; Match = $t; Slots = @($b -split '\+' | % { [int]$_ - 1 }) } }
$fill = @($Proc)  # apps that fill open slots; pinned-only apps place one window
$Proc = @(@($pins.App) + @($Proc | ? { $pins.App -notcontains $_ }) | ? { $_ })
$screens = [System.Windows.Forms.Screen]::AllScreens
$scr = switch ($Monitor) {
  'wide'   { $screens | Sort-Object { $_.Bounds.Width } -Descending | Select-Object -First 1 }
  'laptop' { $screens | Sort-Object { $_.Bounds.Width * $_.Bounds.Height } | Select-Object -First 1 }
  'tall'   { $screens | Where-Object { $_.Bounds.Height -gt $_.Bounds.Width } | Select-Object -First 1 }
  default  { $screens[[int]$Monitor] }
}
if (-not $scr) { throw "No monitor matches '$Monitor'." }
$area = $scr.WorkingArea
# pid -> rank of its app in -Proc, so windows sort in -Proc order.
$rank = @{}
$Skip = @($Skip -split ',' | ? { $_ })
# '*' in -Proc = every other app not in -Skip, ranked at its place in the list.
for ($k = 0; $k -lt $Proc.Count; $k++) {
  $ps = if ($Proc[$k] -eq '*') { Get-Process | ? { $n = $_.Name; -not ($Skip | ? { $n -like $_ }) } } else { Get-Process $Proc[$k] -ErrorAction SilentlyContinue }
  $ps | % { if (-not $rank.ContainsKey("$($_.Id)")) { $rank["$($_.Id)"] = $k } }
}

$wins = [System.Collections.Generic.List[IntPtr]]::new()
[W]::EnumWindows({ param($h, $l)
  $p = 0; [void][W]::GetWindowThreadProcessId($h, [ref]$p)
  if ($rank.ContainsKey("$p") -and [W]::IsAppWindow($h)) { $wins.Add($h) }
  $true }, [IntPtr]::Zero) | Out-Null
function Info($h) {
  $p = 0; [void][W]::GetWindowThreadProcessId($h, [ref]$p)
  $r = New-Object W+RECT; [void][W]::GetWindowRect($h, [ref]$r)
  $sb = New-Object System.Text.StringBuilder 256; [void][W]::GetWindowText($h, $sb, 256)
  [pscustomobject]@{ H = $h; Rank = $rank["$p"]; X = $r.L; Y = $r.T; Wd = $r.R - $r.L; Ht = $r.B - $r.T; App = (Get-Process -Id $p).Name; Title = "$sb" }
}
$items = @($wins | % { Info $_ })
if ($List) { $items | Format-Table App, Title -AutoSize | Out-String -Width 200; $screens | % { $_.DeviceName + ' ' + $_.WorkingArea }; return }

# One move path for slots and -Place: restore, move twice, warn if the size is off.
function Move-Win($win, $x, $y, $ww, $hh) {
  [void][W]::ShowWindow($win, 9)  # restore if maximized/minimized
  # A window that crosses into a monitor with another display scale gets resized by Windows
  # after the first move, so set the size again once it has landed.
  [void][W]::MoveWindow($win, $x, $y, $ww, $hh, $true)
  [void][W]::MoveWindow($win, $x, $y, $ww, $hh, $true)
  $r = New-Object W+RECT; [void][W]::GetWindowRect($win, [ref]$r)
  if ([Math]::Abs(($r.R - $r.L) - $ww) -gt 20 -or [Math]::Abs(($r.B - $r.T) - $hh) -gt 20) {
    Write-Warning ("Off size: '{0}' is {1}x{2}, wanted {3}x{4}." -f ($items | ? { $_.H -eq $win }).Title, ($r.R - $r.L), ($r.B - $r.T), $ww, $hh)
    "off size: is {0}x{1}" -f ($r.R - $r.L), ($r.B - $r.T)
  }
}
if ($Json -and -not ($Place -or $PlaceFile)) {
  # Minimized windows sit at about -25600 (or -32000) and cannot be drawn; leave them out.
  $min = @($items | ? { $_.X -le -20000 }); if ($min) { [Console]::Error.WriteLine("Left out $($min.Count) minimized window(s).") }
  [pscustomobject]@{
    monitors = @($screens | % { [pscustomobject]@{ name = $_.DeviceName; x = $_.WorkingArea.X; y = $_.WorkingArea.Y; w = $_.WorkingArea.Width; h = $_.WorkingArea.Height } })
    windows  = @($items | ? { $_.X -gt -20000 -and $_.Title -ne 'Program Manager' } | % { [pscustomobject]@{ id = [int64]$_.H; app = $_.App; title = $_.Title; x = $_.X; y = $_.Y; w = $_.Wd; h = $_.Ht } })
  } | ConvertTo-Json -Depth 4 -Compress
  return
}

if ($Place -or $PlaceFile) {
  $raw = if ($PlaceFile) { Get-Content -Raw -Encoding UTF8 -LiteralPath $PlaceFile -ErrorAction Stop } else { $Place }
  $spec = @(ConvertFrom-Json $raw | % { $_ })
  if ($spec.Count -eq 1 -and $spec[0].windows) { $spec = @($spec[0].windows | % { $_ }) }  # accept the whole -Json object
  $taken = @{}; $ok = 0; $miss = 0; $res = @()
  foreach ($e in $spec) {
    $c = @($items | ? { -not $taken.ContainsKey("$($_.H)") -and $_.App -eq $e.app })
    # id (window handle from -Json) tells apart windows with the same title.
    $it = if ($e.id) { @($c | ? { [int64]$_.H -eq [int64]$e.id })[0] }
    if (-not $it) { $it = @($c | ? { $_.Title -eq $e.title })[0] }
    if (-not $it) { $it = @($c | ? { $_.Title.Contains([string]$e.title) })[0] }
    if (-not $it) { $miss++; Write-Warning "No open window for $($e.app): '$($e.title)'."; $res += [pscustomobject]@{ app = $e.app; title = $e.title; ok = $false; note = 'no open window' }; continue }
    $taken["$($it.H)"] = 1; $ok++
    $x = [int]$e.x; $y = [int]$e.y; $ww = [int]$e.w; $hh = [int]$e.h
    if ($DryRun) {
      $cur = if ($it.X -eq $x -and $it.Y -eq $y -and $it.Wd -eq $ww -and $it.Ht -eq $hh) { 'at current rect' } else { "from x=$($it.X) y=$($it.Y) $($it.Wd)x$($it.Ht)" }
      if (-not $Json) { "{0,-9} x={1} y={2} {3}x{4}  [{5}]  {6}" -f $it.App, $x, $y, $ww, $hh, $cur, $it.Title }
      $note = "dry run: $cur"
    } else { $note = Move-Win $it.H $x $y $ww $hh; if (-not $note) { $note = 'moved' } }
    $res += [pscustomobject]@{ app = $it.App; title = $it.Title; ok = $true; note = $note }
  }
  if ($Json) { ConvertTo-Json -InputObject @($res) -Compress } else { "Placed $ok of $($ok + $miss) ($miss unmatched)." }
  return
}

# Pinned windows: first window of each pinned app (leftmost, then topmost).
$placed = @(); $used = @{}
foreach ($pn in $pins) {
  $it = $items | ? { $_.App -eq $pn.App -and (-not $pn.Match -or $_.Title -like "*$($pn.Match)*") -and -not $placed.Contains($_) } | Sort-Object X, Y | Select-Object -First 1
  if (-not $it) { Write-Warning "No open window for '$($pn.App)'."; continue }
  $placed += $it; $pn.Slots | % { $used[$_] = 1 }
  $pn | Add-Member Item $it
}
$free = @($items | ? { $placed -notcontains $_ -and ($fill -contains $_.App -or ($fill -contains '*' -and $Proc -notcontains $_.App)) -and $_.Title -ne 'Program Manager' })

# Auto grid sized to fit, unless -Cols/-Rows given.
$need = $free.Count + $used.Count
$maxSlot = ($pins.Slots | Measure-Object -Maximum).Maximum + 1
if ($Cols -le 0 -and $Rows -le 0 -and $Cells -le 0 -and $Monitor -eq 'wide') { $Cells = 10 }
if ($Cells -gt 0) { $need = [Math]::Max($Cells, $maxSlot) }
if ($Rows -le 0) { $Rows = if ($need -le 4) { 1 } elseif ($need -le 12) { 2 } else { 3 } }
if ($Cols -le 0) { $Cols = [Math]::Max([Math]::Ceiling($need / $Rows), [Math]::Ceiling($maxSlot / $Rows)) }
$w = [int]($area.Width / $Cols); $h = [int]($area.Height / $Rows)

function Put($win, $slots) {
  $cs = $slots | % { $_ % $Cols }; $rs = $slots | % { [Math]::Floor($_ / $Cols) }
  $c0 = ($cs | Measure -Min).Minimum; $c1 = ($cs | Measure -Max).Maximum
  $r0 = ($rs | Measure -Min).Minimum; $r1 = ($rs | Measure -Max).Maximum
  $x = $area.X + $c0 * $w; $y = $area.Y + $r0 * $h; $ww = ($c1 - $c0 + 1) * $w; $hh = ($r1 - $r0 + 1) * $h
  if ($DryRun) { "{0,-9} slots {1,-6} x={2} y={3} {4}x{5}  {6}" -f ($items | ? { $_.H -eq $win }).App, (($slots | % { $_ + 1 }) -join '+'), $x, $y, $ww, $hh, ($items | ? { $_.H -eq $win }).Title; return }
  $null = Move-Win $win $x $y $ww $hh
}
foreach ($pn in $pins) { if ($pn.Item) { Put $pn.Item.H $pn.Slots } }

# Free windows fill the open slots row by row, in -Proc order, then current
# position (top row first, left to right), so re-running keeps your arrangement.
$ord = @($Order -split '\|' | ? { $_ })
function OrdIdx($t) { for ($k = 0; $k -lt $ord.Count; $k++) { if ($t -like "*$($ord[$k])*") { return $k } }; $ord.Count }
$free = @($free | Sort-Object Rank, { OrdIdx $_.Title }, { [Math]::Floor(($_.Y - $area.Y + $h / 2) / $h) }, X)
$open = @(0..($Cols * $Rows - 1) | ? { -not $used.ContainsKey($_) })
$n = [Math]::Min($free.Count, $open.Count)
for ($i = 0; $i -lt $n; $i++) { Put $free[$i].H @($open[$i]) }
"Grid ${Cols}x${Rows} ($w x $h per slot): pinned $($placed.Count), tiled $n of $($free.Count) others."

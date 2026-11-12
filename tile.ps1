# Tile visible windows of the named apps into a grid on one monitor.
# -Proc order = tile order (e.g. -Proc msedge,claude puts the browser first).
# -Monitor: 'wide' (widest), 'laptop' (smallest), 'tall' (portrait), or a 0-based index.
# -Pin 'chrome:RFP=1;ms-teams=5+10': put an app's first window (title containing the text after ':', if given) in given slots (spans the box around them).
# -Json: print monitors (with their role) + windows as JSON (default -Proc '*'), move nothing. Minimized windows carry "min":true.
# -Place '<json>' / -PlaceFile <path>: move windows to [{app,title,x,y,w,h,id?}] screen rects (match id, else app + title). Honors -DryRun.
#   With -Json, print one result per entry as JSON instead of text.
# -Scene <name|path|json>: run a scene (one grid per monitor role, pins, fill) from config.json or a file. See scenes.json.
#   With -Json, print {placed,missing,left} as JSON, each placed window with its from and to rect.
#   A scene's zones ({mon, slots, app | cat}) fill their cells with that app's or category's windows in
#   fill order, after pins (a pin wins its cell). Its bay ([{app, title}]) holds windows that stay put.
#   left[].why says where a window without a cell came from: 'no free cell', 'zone full' or 'in the bay'.
#   A pin's behind ([{app, match}]) stacks windows on its rect: each is placed with behind=true and the pin's index, never filled.
#   A pin's lock (true) is read by the page, not here: a pin already beats zones and the fill for its cells.
# -From <path|json>: use a -Json snapshot instead of the live desktop. Always a dry run.
# -Lib: define Move-Win and the Win32 reads and writes behind it, then return (tests dot-source it and swap those for fakes).
# Slots number row by row from 1 (top-left).
# -Cells n: grid with n cells (rows picked for you). Ultrawide default = 10 cells (5x2).
param([int]$Cols = 0, [int]$Rows = 0, [int]$Cells = 0, [string[]]$Proc = @('claude'), [string]$Monitor = 'wide', [string]$Pin = '', [switch]$List, [switch]$DryRun, [switch]$Json, [string]$Place = '', [string]$PlaceFile = '', [switch]$Default,
  # -Order 'a|b|c': windows whose title contains a, then b, then c come first, in that order.
  [string]$Order = '',
  # -Sort app|category|title|position: fill order. app = -Proc order (then -Order, then where windows sit now).
  [string]$Sort = 'app',
  [string]$Scene = '', [string]$From = '', [switch]$Lib,
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
  [StructLayout(LayoutKind.Sequential)] public struct WPL { public int length, flags, showCmd, minX, minY, maxX, maxY; public RECT normal; }
  [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h, ref WPL p);
  [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr h, ref WPL p);
  [DllImport("user32.dll")] static extern bool IsWindowArranged(IntPtr h);
  // Snapped or vertically maximized (Windows 11). Older Windows has no such call: never arranged.
  public static bool Arranged(IntPtr h) { try { return IsWindowArranged(h); } catch (EntryPointNotFoundException) { return false; } }
}
'@
. (Join-Path $PSScriptRoot 'config.ps1')

# The Win32 reads and writes behind Move-Win, so a test can swap them for fakes and move no window.
function Get-WinRect($win) { $r = New-Object W+RECT; [void][W]::GetWindowRect($win, [ref]$r); [pscustomobject]@{ W = $r.R - $r.L; H = $r.B - $r.T } }
# A placement rect (rcNormalPosition) is in workspace coordinates: screen coordinates less the primary work area's offset.
function Get-WorkspaceOffset { $s = [System.Windows.Forms.Screen]::PrimaryScreen; [pscustomobject]@{ X = $s.WorkingArea.X - $s.Bounds.X; Y = $s.WorkingArea.Y - $s.Bounds.Y } }
# Where Windows sends a window when it is restored (screen coordinates), and whether it holds the window snapped.
function Get-WinRestore($win) {
  $p = New-Object W+WPL; $p.length = [Runtime.InteropServices.Marshal]::SizeOf($p); [void][W]::GetWindowPlacement($win, [ref]$p)
  $o = Get-WorkspaceOffset
  [pscustomobject]@{ X = $p.normal.L + $o.X; Y = $p.normal.T + $o.Y; W = $p.normal.R - $p.normal.L; H = $p.normal.B - $p.normal.T; Arranged = [W]::Arranged($win) }
}
# A copy of $placement showing normal, with a new restore rect for the cell (screen coordinates x, y, ww, hh less the workspace offset).
# The rect is built as a whole struct and assigned whole: `$p.normal.L = ...` would change a copy of the nested struct, never the placement.
function New-CellPlacement($placement, $x, $y, $ww, $hh, $offset) {
  $r = New-Object W+RECT; $r.L = $x - $offset.X; $r.T = $y - $offset.Y; $r.R = $r.L + $ww; $r.B = $r.T + $hh
  $q = New-Object W+WPL
  $q.length = $placement.length; $q.flags = $placement.flags; $q.showCmd = 1
  $q.minX = $placement.minX; $q.minY = $placement.minY; $q.maxX = $placement.maxX; $q.maxY = $placement.maxY
  $q.normal = $r
  $q
}
# Show normal and set the restore rect in one call. Unlike ShowWindow, this also ends a snapped state.
function Set-WinRestore($win, $x, $y, $ww, $hh) {
  $p = New-Object W+WPL; $p.length = [Runtime.InteropServices.Marshal]::SizeOf($p); [void][W]::GetWindowPlacement($win, [ref]$p)
  $q = New-CellPlacement $p $x $y $ww $hh (Get-WorkspaceOffset)
  [void][W]::SetWindowPlacement($win, [ref]$q)
}
function Show-WinNormal($win) { [void][W]::ShowWindow($win, 9) }
function Move-WinRect($win, $x, $y, $ww, $hh) { [void][W]::MoveWindow($win, $x, $y, $ww, $hh, $true) }

# One move path for slots and -Place: restore, move twice, warn if the size is off.
function Move-Win($win, $x, $y, $ww, $hh) {
  # A snapped window keeps its own restore rect, and moving it never touches that rect. Windows (or the
  # app) later falls back to it, so the window lands the right width and a stale height (684 x 2663 for a
  # cell of 683 x 840). ShowWindow does not end the snap, so set the restore rect to the cell first.
  if ((Get-WinRestore $win).Arranged) { Set-WinRestore $win $x $y $ww $hh } else { Show-WinNormal $win }  # restore if maximized/minimized
  # A window that crosses into a monitor with another display scale gets resized by Windows
  # after the first move, so set the size again once it has landed.
  Move-WinRect $win $x $y $ww $hh
  Move-WinRect $win $x $y $ww $hh
  $r = Get-WinRect $win; $rs = Get-WinRestore $win
  if ([Math]::Abs($r.W - $ww) -gt 20 -or [Math]::Abs($r.H - $hh) -gt 20 -or [Math]::Abs($rs.W - $ww) -gt 20 -or [Math]::Abs($rs.H - $hh) -gt 20) {
    Write-Warning ("Off size: '{0}' is {1}x{2} (restore rect {3}x{4}), wanted {5}x{6}." -f @($items | ? { $_.H -eq $win })[0].Title, $r.W, $r.H, $rs.W, $rs.H, $ww, $hh)
    "off size: is {0}x{1}, restore rect {2}x{3}" -f $r.W, $r.H, $rs.W, $rs.H
  }
}
if ($Lib) { return }

function JsonText($s) { if ($s -match '^\s*[\[{]') { $s } else { [IO.File]::ReadAllText((Resolve-Path -LiteralPath $s), $TileUtf8) } }

# Default setup = the "default" scene in scenes.json: portrait = Outlook classic (top) + Teams (bottom);
# laptop = new Outlook; ultrawide 5x2 = Claude, then Chrome, then everything else.
$sc = $null
if ($Default) { $st = ConvertFrom-Json ([IO.File]::ReadAllText($TileStarters, $TileUtf8)); $sc = @($st.scenes | ? { $_.id -eq 'default' })[0]; $sc | Add-Member cats $st.cats; $sc | Add-Member categories $st.categories }
elseif ($Scene) { $sc = if ($Scene -match '^\s*\{' -or (Test-Path -LiteralPath $Scene -PathType Leaf)) { ConvertFrom-Json (JsonText $Scene) } else { Get-TileScene $Scene } }

if (($Json -or $Place -or $PlaceFile) -and -not $PSBoundParameters.ContainsKey('Proc')) { $Proc = @('*') }
$Proc = @($Proc -split ',' | ? { $_ })  # -File passes 'a,b' as one string
$Skip = @($Skip -split ',' | ? { $_ })

# Monitors: bounds pick the role, the working area is where windows go.
if ($From) {
  $DryRun = [switch]$true
  $snapIn = ConvertFrom-Json (JsonText $From)
  $screens = @($snapIn.monitors | % { [pscustomobject]@{ Name = $_.name; BW = [int]$(if ($_.bw) { $_.bw } else { $_.w }); BH = [int]$(if ($_.bh) { $_.bh } else { $_.h }); X = [int]$_.x; Y = [int]$_.y; W = [int]$_.w; H = [int]$_.h } })
} else {
  $screens = @([System.Windows.Forms.Screen]::AllScreens | % { $a = $_.WorkingArea; [pscustomobject]@{ Name = $_.DeviceName; BW = $_.Bounds.Width; BH = $_.Bounds.Height; X = $a.X; Y = $a.Y; W = $a.Width; H = $a.Height } })
}
function Pick($role, $taken = @()) {
  $s = @($screens | ? { $taken -notcontains $_.Name })
  switch ($role) {
    'wide'   { $s | Sort-Object BW -Descending | Select-Object -First 1 }
    'laptop' { $s | Sort-Object { $_.BW * $_.BH } | Select-Object -First 1 }
    'tall'   { $s | Where-Object { $_.BH -gt $_.BW } | Select-Object -First 1 }
    default  { $screens[[int]$role] }
  }
}
# Scene roles get distinct screens, widest first, so one screen never holds two grids.
function Roles { $r = @{}; $t = @(); foreach ($k in 'wide', 'tall', 'laptop') { $s = Pick $k $t; if ($s) { $r[$k] = $s; $t += $s.Name } }; $r }

# Windows: every real app window. Each pass ranks them by its own -Proc list.
if ($From) {
  $items = @($snapIn.windows | % { [pscustomobject]@{ H = [int64]$_.id; Rank = $null; X = [int]$_.x; Y = [int]$_.y; Wd = [int]$_.w; Ht = [int]$_.h; App = [string]$_.app; Title = [string]$_.title } })
} else {
  $pname = @{}; Get-Process | % { $pname["$($_.Id)"] = $_.Name }
  $wins = [System.Collections.Generic.List[IntPtr]]::new()
  [W]::EnumWindows({ param($h, $l) if ([W]::IsAppWindow($h)) { $wins.Add($h) }; $true }, [IntPtr]::Zero) | Out-Null
  $items = @($wins | % {
    $p = 0; [void][W]::GetWindowThreadProcessId($_, [ref]$p)
    $r = New-Object W+RECT; [void][W]::GetWindowRect($_, [ref]$r)
    $sb = New-Object System.Text.StringBuilder 256; [void][W]::GetWindowText($_, $sb, 256)
    if ($pname["$p"]) { [pscustomobject]@{ H = $_; Rank = $null; X = $r.L; Y = $r.T; Wd = $r.R - $r.L; Ht = $r.B - $r.T; App = $pname["$p"]; Title = "$sb" } }
  })
}
$claimed = @{}  # windows a scene pass already placed
# Rank = place of the window's app in the list; '*' = every other app not in -Skip.
function Ranked($procs, $skip) {
  foreach ($it in $items) {
    if ($claimed.ContainsKey("$($it.H)")) { continue }
    $it.Rank = $null
    for ($k = 0; $k -lt $procs.Count; $k++) {
      $a = $it.App
      if (($procs[$k] -eq '*' -and -not ($skip | ? { $a -like $_ })) -or ($procs[$k] -ne '*' -and $a -like $procs[$k])) { $it.Rank = $k; break }
    }
    if ($null -ne $it.Rank) { $it }
  }
}
function Contains($t, $m) { $t.IndexOf($m, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
$pins = @(); foreach ($e in ($Pin -split ';' | ? { $_ })) { $a, $b = $e -split '='; $app, $t = $a.Trim() -split ':', 2; $pins += [pscustomobject]@{ App = $app; Match = $t; Slots = @($b -split '\+' | % { [int]$_ - 1 }); Index = $pins.Count } }
$allProc = @(@($pins.App) + @($Proc | ? { $pins.App -notcontains $_ }) | ? { $_ })

if ($List) { Ranked $allProc $Skip | Format-Table App, Title -AutoSize | Out-String -Width 200; $screens | % { "$($_.Name) {X=$($_.X),Y=$($_.Y),Width=$($_.W),Height=$($_.H)}" }; return }

if ($Json -and -not ($Place -or $PlaceFile -or $sc)) {
  $roles = Roles
  [pscustomobject]@{
    monitors = @($screens | % { $n = $_.Name; [pscustomobject]@{ name = $n; role = @($roles.Keys | ? { $roles[$_].Name -eq $n })[0]; x = $_.X; y = $_.Y; w = $_.W; h = $_.H; bw = $_.BW; bh = $_.BH } })
    # Minimized windows sit at about -25600 (or -32000); a scene still tiles them, so they stay in, marked.
    windows  = @(Ranked $allProc $Skip | ? { $_.Title -ne 'Program Manager' } | % { $o = [ordered]@{ id = [int64]$_.H; app = $_.App; title = $_.Title; x = $_.X; y = $_.Y; w = $_.Wd; h = $_.Ht }; if ($_.X -le -20000) { $o.min = $true }; [pscustomobject]$o })
  } | ConvertTo-Json -Depth 4 -Compress
  return
}

if ($Place -or $PlaceFile) {
  $items = @(Ranked $allProc $Skip)
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

$missing = @(); $left = @(); $roleState = @{}
# One grid on one monitor. Pinned windows take their slots; the -Proc apps fill the open
# slots. Emits text (-DryRun), result objects (-Json), or moves windows.
# A scene runs it once per phase on every monitor ('pins', then 'zones', then 'fill'), so a pin on any
# monitor beats every zone, and every zone beats the fill. In a scene a minimized window stays where it
# is (in the bay) unless a pin names it by title. -Proc runs (phase 'all') keep the old single pass.
function Pass($area, [int]$Cols, [int]$Rows, [int]$Cells, $fill, $pins, $skip, $order, $sort, $isWide, $role, $zones = @(), $phase = 'all', $held = @()) {
  $scene = $phase -ne 'all'
  $all = @(@($pins.App) + @($fill | ? { $pins.App -notcontains $_ }) | ? { $_ })
  if (-not $script:roleState.ContainsKey("$role")) { $script:roleState["$role"] = @{ used = @{}; pinned = 0 } }
  $state = $script:roleState["$role"]; $used = $state.used
  $up = { -not $scene -or $_.X -gt -20000 }  # not minimized (scenes only)
  $its = @(Ranked $all $skip)
  # Pinned windows: first window of each pinned app (visible first, then leftmost, then topmost).
  $placed = @()
  if ($phase -in 'all', 'pins') {
    foreach ($pn in $pins) {
      $it = $its | ? { $_.App -eq $pn.App -and (-not $pn.Match -or (Contains $_.Title $pn.Match)) -and -not $placed.Contains($_) -and ($pn.Match -or (& $up)) } | Sort-Object { $_.X -le -20000 }, X, Y | Select-Object -First 1
      if ($it) { $placed += $it } else { Write-Warning "No open window for '$($pn.App)'."; $script:missing += [pscustomobject]@{ pin = $pn.Index; app = $pn.App; match = $pn.Match; why = 'no open window' } }
      # Windows stacked behind this pin: same rect, never in the fill. A minimized one counts (Apply restores it).
      $bis = @(foreach ($b in @($pn.Behind)) {
        $bi = @($items | ? { -not $script:claimed.ContainsKey("$($_.H)") -and -not $placed.Contains($_) -and $_.App -eq $b.App -and (-not $b.Match -or (Contains $_.Title $b.Match)) } | Sort-Object { $_.X -le -20000 }, X, Y | Select-Object -First 1)[0]
        if ($bi) { $placed += $bi; $bi } else { Write-Warning "No open window for '$($b.App)' behind '$($pn.App)'."; $script:missing += [pscustomobject]@{ pin = $pn.Index; app = $b.App; match = $b.Match; why = 'no open window' } }
      })
      # The front is not open: the first open back window takes its cell as the new front, as the board promotes one when its front leaves.
      if (-not $it -and $bis.Count) { $it = $bis[0]; $bis = @($bis | Select-Object -Skip 1) }
      $pn | Add-Member -Force Item $it
      # Fill off: a pin for a closed window still keeps its cell, so nothing held lands on it.
      if (-not $it) { if ($script:sceneFillOff) { $pn.Slots | % { $used[$_] = 1 } }; continue }
      $pn | Add-Member -Force BehindItems $bis
      $pn.Slots | % { $used[$_] = 1 }
    }
    $state.pinned = @($pins | ? { $_.Item }).Count
  }
  $free = @($its | ? { $placed -notcontains $_ -and ($fill -contains $_.App -or ($fill -contains '*' -and $all -notcontains $_.App)) -and $_.Title -ne 'Program Manager' -and (& $up) })

  # Auto grid sized to fit, unless -Cols/-Rows given.
  $need = $free.Count + $used.Count
  $maxSlot = ($pins.Slots | Measure-Object -Maximum).Maximum + 1
  if ($Cols -le 0 -and $Rows -le 0 -and $Cells -le 0 -and $isWide) { $Cells = 10 }
  if ($Cells -gt 0) { $need = [Math]::Max($Cells, $maxSlot) }
  if ($Rows -le 0) { $Rows = if ($need -le 4) { 1 } elseif ($need -le 12) { 2 } else { 3 } }
  if ($Cols -le 0) { $Cols = [Math]::Max([Math]::Ceiling($need / $Rows), [Math]::Ceiling($maxSlot / $Rows)) }
  $w = [int]($area.W / $Cols); $h = [int]($area.H / $Rows)

  # Fill order. app: in -Proc order, then -Order, then current position (top row first, left to right),
  # so re-running keeps your arrangement. A zone ranks apps by their place in the fill list.
  $ord = @($order -split '\|' | ? { $_ })
  function OrdIdx($t) { for ($k = 0; $k -lt $ord.Count; $k++) { if (Contains $t $ord[$k]) { return $k } }; $ord.Count }
  function CatIdx($a) { $c = if ($script:cats) { $script:cats.$a }; $i = [array]::IndexOf($script:catOrder, [string]$c); if ($i -lt 0) { $script:catOrder.Count } else { $i } }
  function FillIdx($a, $f) { for ($k = 0; $k -lt @($f).Count; $k++) { if (@($f)[$k] -eq $a -or (@($f)[$k] -eq '*' -and @($f) -notcontains $a)) { return $k } }; @($f).Count }
  $row = { [Math]::Floor(($_.Y - $area.Y + $h / 2) / $h) }
  function KeysFor($rank) { switch ($sort) {
    'title'    { 'Title', $row, 'X' }
    'position' { $row, 'X' }
    'category' { { CatIdx $_.App }, $rank, { OrdIdx $_.Title }, $row, 'X' }
    default    { $rank, { OrdIdx $_.Title }, $row, 'X' }
  } }

  function Put($it, $slots, $pin, $zone = -1, [switch]$behind) {
    $cs = $slots | % { $_ % $Cols }; $rs = $slots | % { [Math]::Floor($_ / $Cols) }
    $c0 = ($cs | Measure -Min).Minimum; $c1 = ($cs | Measure -Max).Maximum
    $r0 = ($rs | Measure -Min).Minimum; $r1 = ($rs | Measure -Max).Maximum
    $x = $area.X + $c0 * $w; $y = $area.Y + $r0 * $h; $ww = ($c1 - $c0 + 1) * $w; $hh = ($r1 - $r0 + 1) * $h
    $script:claimed["$($it.H)"] = 1
    if ($Json) {
      $note = if ($DryRun) { 'dry run' } else { $m = Move-Win $it.H $x $y $ww $hh; if ($m) { "$m" } else { 'moved' } }
      $o = [pscustomobject]@{ id = [int64]$it.H; app = $it.App; title = $it.Title; mon = $role; slots = @($slots | % { $_ + 1 }); pin = $pin; zone = $zone; x = $x; y = $y; w = $ww; h = $hh
        from = [pscustomobject]@{ x = $it.X; y = $it.Y; w = $it.Wd; h = $it.Ht }; ok = $true; note = $note }
      if ($behind) { $o | Add-Member behind $true }
      return $o
    }
    if ($DryRun) { "{0,-9} slots {1,-6} x={2} y={3} {4}x{5}  {6}" -f $it.App, (($slots | % { $_ + 1 }) -join '+'), $x, $y, $ww, $hh, $it.Title; return }
    $null = Move-Win $it.H $x $y $ww $hh
  }
  # A back window moves first, so the front window (moved last) ends on top: a restore activates the window.
  if ($phase -in 'all', 'pins') { foreach ($pn in $pins) { if ($pn.Item) { foreach ($bi in @($pn.BehindItems)) { Put $bi $pn.Slots $pn.Index -behind }; Put $pn.Item $pn.Slots $pn.Index } } }

  # Fill Empty Cells off (scene fill.held): each held window goes back in its held cells, after every pin has taken its own.
  # A held cell a pin (open or closed) or an earlier hold has taken is skipped. An entry holds one window, matched as a pin
  # matches: by its handle when it has one (a stale handle holds nothing), else by its app, and by its title only when the app
  # has several windows (open, or held in the scene): its exact title first, else a title that contains it. A closed, minimized or already placed window is not held: the sweep after
  # the phase loop lists the open ones as 'fill is off'.
  if ($phase -eq 'held') {
    foreach ($hd in $held) {
      if (@($hd.Slots | ? { $used.ContainsKey($_) }).Count) { continue }
      $pool = @($items | ? { -not $script:claimed.ContainsKey("$($_.H)") -and $_.App -eq $hd.App -and (& $up) })
      $it = if ($hd.Id) { @($pool | ? { [int64]$_.H -eq [int64]$hd.Id })[0] }
      else {
        $many = @($items | ? { $_.App -eq $hd.App }).Count -gt 1 -or @($sc.fill.held | ? { $_ -and [string]$_.app -eq $hd.App }).Count -gt 1
        # An exact title wins over a containing one, so 'Projects' never takes 'Projects archive'; position orders only the chosen set.
        $cand = $pool
        if ($many) { $cand = @($pool | ? { $_.Title -ceq $hd.Title }); if (-not $cand.Count) { $cand = @($pool | ? { $hd.Title -and (Contains $_.Title $hd.Title) }) } }
        @($cand | Sort-Object { $_.X -le -20000 }, X, Y)[0]
      }
      if (-not $it) { continue }
      $hd.Slots | % { $used[$_] = 1 }
      Put $it $hd.Slots (-1)
    }
  }

  # Zones: each takes its cells (pins on every monitor already won theirs) and fills them with its app's
  # or category's windows in fill order, row by row. A category zone leaves out skipped apps, as the fill
  # does for '*'. Windows that do not fit go to the bay.
  # Fill Empty Cells off (scene fill.off): pins and held windows (fill.held) are placed. The zone and fill steps place nothing; the
  # scene names the other windows, which stay where they are, once every pass has run (see the sweep after the phase loop).
  $fillOff = $scene -and $script:sceneFillOff
  if ($phase -eq 'zones' -and -not $fillOff) {
    $zkeys = KeysFor { FillIdx $_.App $script:zFill }
    foreach ($z in $zones) {
      $cand = @($items | ? { -not $script:claimed.ContainsKey("$($_.H)") -and $_.Title -ne 'Program Manager' -and (& $up) -and $(if ($z.App) { $_.App -eq $z.App } else { $a = $_.App; -not ($script:zSkip | ? { $a -like $_ }) -and $(if ($script:cats -and $script:cats.$a) { [string]$script:cats.$a } else { 'other' }) -eq $z.Cat }) } | Sort-Object $zkeys)
      $zc = @($z.Slots | Sort-Object | ? { -not $used.ContainsKey($_) }); $z.Slots | % { $used[$_] = 1 }
      $k = [Math]::Min($cand.Count, $zc.Count)
      for ($i = 0; $i -lt $k; $i++) { Put $cand[$i] @($zc[$i]) (-1) $z.Index }
      foreach ($it in ($cand | Select-Object -Skip $k)) { $script:claimed["$($it.H)"] = 1; $script:left += [pscustomobject]@{ id = [int64]$it.H; app = $it.App; title = $it.Title; why = 'zone full' } }
    }
  }

  # Free windows fill the open slots row by row.
  if ($phase -in 'all', 'fill' -and -not $fillOff) {
    $free = @($free | ? { -not $script:claimed.ContainsKey("$($_.H)") } | Sort-Object (KeysFor 'Rank'))
    $open = @(0..($Cols * $Rows - 1) | ? { -not $used.ContainsKey($_) })
    $n = [Math]::Min($free.Count, $open.Count)
    for ($i = 0; $i -lt $n; $i++) { Put $free[$i] @($open[$i]) (-1) }
    $script:left += @($free | Select-Object -Skip $n | % { [pscustomobject]@{ id = [int64]$_.H; app = $_.App; title = $_.Title; why = 'no free cell' } })
    if (-not $Json) { "Grid ${Cols}x${Rows} ($w x $h per slot): pinned $($state.pinned), tiled $n of $($free.Count) others." }
  }
}

# App -> category for -Sort category: the scene's map, else the starters'.
$cs = if ($sc -and $sc.cats) { $sc } else { ConvertFrom-Json ([IO.File]::ReadAllText($TileStarters, $TileUtf8)) }
$cats = $cs.cats; $catOrder = @($cs.categories | % { [string]$_[0] }); if (-not $catOrder.Count) { $catOrder = @('code', 'browse', 'comms', 'other') }
if (-not $sc) {
  $scr = Pick $Monitor
  if (-not $scr) { throw "No monitor matches '$Monitor'." }
  Pass $scr $Cols $Rows $Cells $Proc $pins $Skip $Order $Sort ($Monitor -eq 'wide') $Monitor
  return
}

# A scene: pins on every monitor, then zones, then the fill; each phase runs portrait, laptop, ultrawide.
$roles = Roles; $out = @(); $passes = @()
# Zones on every monitor rank by the scene's fill list and leave out its skipped apps.
$sceneFillOff = [bool]$sc.fill.off
$zFill = @($sc.fill.apps); $zSkip = @($Skip + @($sc.fill.skip) | ? { $_ })
# Windows that stay put never move. Held by window handle and app (the page sends a handle only within
# its session; saved scenes drop it), else by app and exact title, one window per entry.
foreach ($b in @($sc.bay | ? { $_ })) {
  $it = if ($b.id) { @($items | ? { -not $claimed.ContainsKey("$($_.H)") -and [int64]$_.H -eq [int64]$b.id -and $_.App -eq [string]$b.app })[0] }
  if (-not $it -and $b.title) { $it = @($items | ? { -not $claimed.ContainsKey("$($_.H)") -and $_.App -eq [string]$b.app -and $_.Title -ceq [string]$b.title })[0] }
  if ($it) { $claimed["$($it.H)"] = 1; $left += [pscustomobject]@{ id = [int64]$it.H; app = $it.App; title = $it.Title; why = 'in the bay' } }
}
foreach ($role in 'tall', 'laptop', 'wide') {
  $g = $sc.grids.$role; if (-not $g) { continue }
  $gc = [int]$g.c; $gr = [int]$g.r
  $ps = @(for ($i = 0; $i -lt @($sc.pins).Count; $i++) {
    $p = @($sc.pins)[$i]; if ($p.mon -ne $role) { continue }
    $sl = @($p.slots | % { [int]$_ } | ? { $_ -ge 0 -and $_ -lt $gc * $gr })
    if (-not $sl.Count) { $missing += [pscustomobject]@{ pin = $i; app = $p.app; match = [string]$p.match; why = 'slots outside the grid' }; continue }
    [pscustomobject]@{ App = [string]$p.app; Match = [string]$p.match; Slots = $sl; Index = $i; Behind = @(@($p.behind | ? { $_ }) | % { [pscustomobject]@{ App = [string]$_.app; Match = [string]$_.match } }) }
  })
  $zs = @(for ($i = 0; $i -lt @($sc.zones | ? { $_ }).Count; $i++) {
    $z = @($sc.zones)[$i]; if ($z.mon -ne $role) { continue }
    $sl = @($z.slots | % { [int]$_ } | ? { $_ -ge 0 -and $_ -lt $gc * $gr })
    if ($sl.Count -and ($z.app -or $z.cat)) { [pscustomobject]@{ App = [string]$z.app; Cat = [string]$z.cat; Slots = $sl; Index = $i } }
  })
  $hs = @(if ($sceneFillOff) { for ($i = 0; $i -lt @($sc.fill.held | ? { $_ }).Count; $i++) {
    $h = @($sc.fill.held)[$i]; if ($h.mon -ne $role) { continue }
    $sl = @($h.slots | % { [int]$_ } | ? { $_ -ge 0 -and $_ -lt $gc * $gr })
    if ($sl.Count) { [pscustomobject]@{ Id = $h.id; App = [string]$h.app; Title = [string]$h.title; Slots = $sl } }
  } })
  $isFill = $sc.fill.mon -eq $role
  if (-not $ps.Count -and -not $isFill -and -not $zs.Count -and -not $hs.Count) { continue }
  $scr = $roles[$role]
  if (-not $scr) { Write-Warning "No $role monitor. That part of the scene is skipped."; $missing += @($ps | % { [pscustomobject]@{ pin = $_.Index; app = $_.App; match = $_.Match; why = "no $role monitor" } }); continue }
  $passes += [pscustomobject]@{ Scr = $scr; C = $gc; R = $gr; Fill = $(if ($isFill) { @($sc.fill.apps) } else { @() }); Pins = $ps; Zones = $zs; Held = $hs; Role = $role
    Skip = $(if ($isFill) { @($Skip + @($sc.fill.skip) | ? { $_ }) } else { $Skip }); Sort = $(if ($sc.fill.sort) { [string]$sc.fill.sort } else { 'app' }) }
}
foreach ($phase in 'pins', 'held', 'zones', 'fill') {
  foreach ($q in $passes) {
    $r = Pass $q.Scr $q.C $q.R 0 $q.Fill $q.Pins $q.Skip ([string]$sc.fill.order) $q.Sort ($q.Role -eq 'wide') $q.Role $q.Zones $phase $q.Held
    if ($Json) { $out += @($r) } else { $r }
  }
}
# Fill off: every window the page lists (as -Json does) that no pin, back slot or bay claimed and that is not minimized goes to
# the list as 'fill is off', whatever its app: an app with a pinned window included.
if ($sceneFillOff) {
  $left += @(Ranked @('*') $Skip | ? { $_.Title -ne 'Program Manager' -and $_.X -gt -20000 } | % { $claimed["$($_.H)"] = 1; [pscustomobject]@{ id = [int64]$_.H; app = $_.App; title = $_.Title; why = 'fill is off' } })
}
if ($Json) { ConvertTo-Json -Depth 6 -Compress ([pscustomobject]@{ placed = @($out); missing = @($missing); left = @($left) }) }

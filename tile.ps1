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
# -From <path|json>: use a -Json snapshot instead of the live desktop. Always a dry run.
# Slots number row by row from 1 (top-left).
# -Cells n: grid with n cells (rows picked for you). Ultrawide default = 10 cells (5x2).
param([int]$Cols = 0, [int]$Rows = 0, [int]$Cells = 0, [string[]]$Proc = @('claude'), [string]$Monitor = 'wide', [string]$Pin = '', [switch]$List, [switch]$DryRun, [switch]$Json, [string]$Place = '', [string]$PlaceFile = '', [switch]$Default,
  # -Order 'a|b|c': windows whose title contains a, then b, then c come first, in that order.
  [string]$Order = '',
  # -Sort app|category|title|position: fill order. app = -Proc order (then -Order, then where windows sit now).
  [string]$Sort = 'app',
  [string]$Scene = '', [string]$From = '',
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
. (Join-Path $PSScriptRoot 'config.ps1')

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

$missing = @(); $left = @()
# One grid on one monitor. Pinned windows take their slots; the -Proc apps fill the open
# slots. Emits text (-DryRun), result objects (-Json), or moves windows.
function Pass($area, [int]$Cols, [int]$Rows, [int]$Cells, $fill, $pins, $skip, $order, $sort, $isWide, $role, $zones = @()) {
  $all = @(@($pins.App) + @($fill | ? { $pins.App -notcontains $_ }) | ? { $_ })
  $its = @(Ranked $all $skip)
  # Pinned windows: first window of each pinned app (leftmost, then topmost).
  $placed = @(); $used = @{}
  foreach ($pn in $pins) {
    $it = $its | ? { $_.App -eq $pn.App -and (-not $pn.Match -or (Contains $_.Title $pn.Match)) -and -not $placed.Contains($_) } | Sort-Object X, Y | Select-Object -First 1
    $pn | Add-Member -Force Item $it
    if (-not $it) { Write-Warning "No open window for '$($pn.App)'."; $script:missing += [pscustomobject]@{ pin = $pn.Index; app = $pn.App; match = $pn.Match; why = 'no open window' }; continue }
    $placed += $it; $pn.Slots | % { $used[$_] = 1 }
  }
  $free = @($its | ? { $placed -notcontains $_ -and ($fill -contains $_.App -or ($fill -contains '*' -and $all -notcontains $_.App)) -and $_.Title -ne 'Program Manager' })

  # Auto grid sized to fit, unless -Cols/-Rows given.
  $need = $free.Count + $used.Count
  $maxSlot = ($pins.Slots | Measure-Object -Maximum).Maximum + 1
  if ($Cols -le 0 -and $Rows -le 0 -and $Cells -le 0 -and $isWide) { $Cells = 10 }
  if ($Cells -gt 0) { $need = [Math]::Max($Cells, $maxSlot) }
  if ($Rows -le 0) { $Rows = if ($need -le 4) { 1 } elseif ($need -le 12) { 2 } else { 3 } }
  if ($Cols -le 0) { $Cols = [Math]::Max([Math]::Ceiling($need / $Rows), [Math]::Ceiling($maxSlot / $Rows)) }
  $w = [int]($area.W / $Cols); $h = [int]($area.H / $Rows)

  # Fill order. app: in -Proc order, then -Order, then current position (top row first, left to right),
  # so re-running keeps your arrangement. Zones use the same order.
  $ord = @($order -split '\|' | ? { $_ })
  function OrdIdx($t) { for ($k = 0; $k -lt $ord.Count; $k++) { if (Contains $t $ord[$k]) { return $k } }; $ord.Count }
  function CatIdx($a) { $c = if ($script:cats) { $script:cats.$a }; $i = [array]::IndexOf($script:catOrder, [string]$c); if ($i -lt 0) { $script:catOrder.Count } else { $i } }
  $row = { [Math]::Floor(($_.Y - $area.Y + $h / 2) / $h) }
  $keys = switch ($sort) {
    'title'    { 'Title', $row, 'X' }
    'position' { $row, 'X' }
    'category' { { CatIdx $_.App }, 'Rank', { OrdIdx $_.Title }, $row, 'X' }
    default    { 'Rank', { OrdIdx $_.Title }, $row, 'X' }
  }

  function Put($it, $slots, $pin, $zone = -1) {
    $cs = $slots | % { $_ % $Cols }; $rs = $slots | % { [Math]::Floor($_ / $Cols) }
    $c0 = ($cs | Measure -Min).Minimum; $c1 = ($cs | Measure -Max).Maximum
    $r0 = ($rs | Measure -Min).Minimum; $r1 = ($rs | Measure -Max).Maximum
    $x = $area.X + $c0 * $w; $y = $area.Y + $r0 * $h; $ww = ($c1 - $c0 + 1) * $w; $hh = ($r1 - $r0 + 1) * $h
    $script:claimed["$($it.H)"] = 1
    if ($Json) {
      $note = if ($DryRun) { 'dry run' } else { $m = Move-Win $it.H $x $y $ww $hh; if ($m) { "$m" } else { 'moved' } }
      return [pscustomobject]@{ id = [int64]$it.H; app = $it.App; title = $it.Title; mon = $role; slots = @($slots | % { $_ + 1 }); pin = $pin; zone = $zone; x = $x; y = $y; w = $ww; h = $hh
        from = [pscustomobject]@{ x = $it.X; y = $it.Y; w = $it.Wd; h = $it.Ht }; ok = $true; note = $note }
    }
    if ($DryRun) { "{0,-9} slots {1,-6} x={2} y={3} {4}x{5}  {6}" -f $it.App, (($slots | % { $_ + 1 }) -join '+'), $x, $y, $ww, $hh, $it.Title; return }
    $null = Move-Win $it.H $x $y $ww $hh
  }
  foreach ($pn in $pins) { if ($pn.Item) { Put $pn.Item $pn.Slots $pn.Index } }

  # Zones: each takes its cells (pins already won theirs) and fills them with its app's or category's
  # windows in fill order, row by row. Windows that do not fit go to the bay.
  foreach ($z in $zones) {
    $cand = @($items | ? { -not $script:claimed.ContainsKey("$($_.H)") -and $_.Title -ne 'Program Manager' -and $(if ($z.App) { $_.App -eq $z.App } else { $(if ($script:cats -and $script:cats.($_.App)) { [string]$script:cats.($_.App) } else { 'other' }) -eq $z.Cat }) } | Sort-Object $keys)
    $zc = @($z.Slots | Sort-Object | ? { -not $used.ContainsKey($_) }); $z.Slots | % { $used[$_] = 1 }
    $k = [Math]::Min($cand.Count, $zc.Count)
    for ($i = 0; $i -lt $k; $i++) { Put $cand[$i] @($zc[$i]) (-1) $z.Index }
    foreach ($it in ($cand | Select-Object -Skip $k)) { $script:claimed["$($it.H)"] = 1; $script:left += [pscustomobject]@{ id = [int64]$it.H; app = $it.App; title = $it.Title; why = 'zone full' } }
  }

  # Free windows fill the open slots row by row.
  $free = @($free | ? { -not $script:claimed.ContainsKey("$($_.H)") } | Sort-Object $keys)
  $open = @(0..($Cols * $Rows - 1) | ? { -not $used.ContainsKey($_) })
  $n = [Math]::Min($free.Count, $open.Count)
  for ($i = 0; $i -lt $n; $i++) { Put $free[$i] @($open[$i]) (-1) }
  $script:left += @($free | Select-Object -Skip $n | % { [pscustomobject]@{ id = [int64]$_.H; app = $_.App; title = $_.Title; why = 'no free cell' } })
  if (-not $Json) { "Grid ${Cols}x${Rows} ($w x $h per slot): pinned $($placed.Count), tiled $n of $($free.Count) others." }
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

# A scene: one pass per monitor role, portrait, then laptop, then ultrawide.
$roles = Roles; $out = @()
# The bay: windows the owner took off the board stay where they are (or stay minimized).
foreach ($b in @($sc.bay | ? { $_ })) {
  $it = @($items | ? { -not $claimed.ContainsKey("$($_.H)") -and $_.App -eq [string]$b.app -and $_.Title -eq [string]$b.title })[0]
  if ($it) { $claimed["$($it.H)"] = 1; $left += [pscustomobject]@{ id = [int64]$it.H; app = $it.App; title = $it.Title; why = 'in the bay' } }
}
foreach ($role in 'tall', 'laptop', 'wide') {
  $g = $sc.grids.$role; if (-not $g) { continue }
  $gc = [int]$g.c; $gr = [int]$g.r
  $ps = @(for ($i = 0; $i -lt @($sc.pins).Count; $i++) {
    $p = @($sc.pins)[$i]; if ($p.mon -ne $role) { continue }
    $sl = @($p.slots | % { [int]$_ } | ? { $_ -ge 0 -and $_ -lt $gc * $gr })
    if (-not $sl.Count) { $missing += [pscustomobject]@{ pin = $i; app = $p.app; match = [string]$p.match; why = 'slots outside the grid' }; continue }
    [pscustomobject]@{ App = [string]$p.app; Match = [string]$p.match; Slots = $sl; Index = $i }
  })
  $zs = @(for ($i = 0; $i -lt @($sc.zones | ? { $_ }).Count; $i++) {
    $z = @($sc.zones)[$i]; if ($z.mon -ne $role) { continue }
    $sl = @($z.slots | % { [int]$_ } | ? { $_ -ge 0 -and $_ -lt $gc * $gr })
    if ($sl.Count -and ($z.app -or $z.cat)) { [pscustomobject]@{ App = [string]$z.app; Cat = [string]$z.cat; Slots = $sl; Index = $i } }
  })
  $isFill = $sc.fill.mon -eq $role
  if (-not $ps.Count -and -not $isFill -and -not $zs.Count) { continue }
  $scr = $roles[$role]
  if (-not $scr) { Write-Warning "No $role monitor. That part of the scene is skipped."; $missing += @($ps | % { [pscustomobject]@{ pin = $_.Index; app = $_.App; match = $_.Match; why = "no $role monitor" } }); continue }
  $fl = if ($isFill) { @($sc.fill.apps) } else { @() }
  $sk = if ($isFill) { @($Skip + @($sc.fill.skip) | ? { $_ }) } else { $Skip }
  $srt = if ($sc.fill.sort) { [string]$sc.fill.sort } else { 'app' }
  if ($Json) { $out += @(Pass $scr $gc $gr 0 $fl $ps $sk ([string]$sc.fill.order) $srt ($role -eq 'wide') $role $zs) }
  else { Pass $scr $gc $gr 0 $fl $ps $sk ([string]$sc.fill.order) $srt ($role -eq 'wide') $role $zs }
}
if ($Json) { ConvertTo-Json -Depth 6 -Compress ([pscustomobject]@{ placed = @($out); missing = @($missing); left = @($left) }) }

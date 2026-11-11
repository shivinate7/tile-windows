# Checks for Move-Win in tile.ps1: a snapped window must end with its restore rect at its cell, and a stale restore rect must be reported.
# Moves no window. Move-Win's Win32 calls reach one model of one window (below). Every handle passed is IntPtr.Zero, which is no window.
#   tile.ps1 with -Lib: its five wrappers (Get-WinRect, Get-WinRestore, Set-WinRestore, Show-WinNormal, Move-WinRect) are replaced by fakes over the model.
#   tile.ps1 without -Lib (an older copy): Move-Win is taken from its parse tree, and a stand-in W forwards its ShowWindow, MoveWindow and
#     GetWindowRect to the model. The copy itself is never run, since without -Lib it would run a scene.
# The model follows what the live desktop showed: moving a snapped window leaves its restore rect alone, ShowWindow does not end the snap,
# and setting the placement ends it and sets both rects. So a green run proves Move-Win's logic on that model, not Windows itself.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\move.ps1 [-Tile <path to a tile.ps1 copy>]
# test\run.ps1 dot-sources this file.
param([string]$Tile = (Join-Path (Split-Path $PSScriptRoot) 'tile.ps1'))
$standalone = -not (Get-Command Check -ErrorAction SilentlyContinue)
if ($standalone) {
  $ErrorActionPreference = 'Stop'; $script:fail = 0
  function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
}
& {
  # The stand-in W for an older copy: the three Win32 calls Move-Win makes there, each forwarding to a hook set below.
  $standIn = @'
using System;
public static class W {
  public struct RECT { public int L, T, R, B; }
  public static Func<IntPtr, int, bool> ShowHook;
  public static Func<IntPtr, int, int, int, int, bool> MoveHook;
  public static Func<IntPtr, int[]> RectHook;
  public static bool ShowWindow(IntPtr h, int cmd) { return ShowHook(h, cmd); }
  public static bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool repaint) { return MoveHook(h, x, y, w, hh); }
  public static bool GetWindowRect(IntPtr h, ref RECT r) { int[] v = RectHook(h); r.L = v[0]; r.T = v[1]; r.R = v[2]; r.B = v[3]; return true; }
}
'@
  $tree = [Management.Automation.Language.Parser]::ParseFile($Tile, [ref]$null, [ref]$null)
  $hasLib = [bool]($tree.ParamBlock -and @($tree.ParamBlock.Parameters | ? { $_.Name.VariablePath.UserPath -eq 'Lib' }).Count)
  if ($hasLib) { . $Tile -Lib }
  else {
    Add-Type -TypeDefinition $standIn
    foreach ($f in $tree.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Move-Win' }, $false)) { . ([scriptblock]::Create($f.Extent.Text)) }
  }

  # One window, screen coordinates. Live and Restore are x, y, w, h. Arr: the window is snapped. Works: false means Windows refuses a placement.
  function New-Win($live, $restore, $arranged, $works = $true) { $script:mvWin = @{ Live = $live; Restore = $restore; Arr = $arranged; Works = $works; Moves = 0; Sets = 0 } }
  function Mv-Live($win) { $script:mvWin.Live }
  function Mv-Restore($win) { $s = $script:mvWin; [pscustomobject]@{ X = $s.Restore[0]; Y = $s.Restore[1]; W = $s.Restore[2]; H = $s.Restore[3]; Arranged = $s.Arr } }
  function Mv-Show($win, $cmd) { }   # ShowWindow does not end a snap, and a plain window is already normal
  function Mv-Move($win, $x, $y, $w, $h) {
    $s = $script:mvWin; $s.Moves++; $s.Live = @($x, $y, $w, $h)
    if (-not $s.Arr) { $s.Restore = @($x, $y, $w, $h) }   # a normal window's restore rect follows its move; a snapped one keeps its own
  }
  function Mv-Set($win, $x, $y, $w, $h) {
    $s = $script:mvWin; $s.Sets++
    if ($s.Works) { $s.Arr = $false; $s.Live = @($x, $y, $w, $h); $s.Restore = @($x, $y, $w, $h) }
  }

  # The five wrappers, as fakes over the model. The older copy's Move-Win calls the stand-in W instead.
  function Get-WinRect($win) { $r = Mv-Live $win; [pscustomobject]@{ W = $r[2]; H = $r[3] } }
  function Get-WinRestore($win) { Mv-Restore $win }
  function Show-WinNormal($win) { Mv-Show $win 9 }
  function Set-WinRestore($win, $x, $y, $ww, $hh) { Mv-Set $win $x $y $ww $hh }
  function Move-WinRect($win, $x, $y, $ww, $hh) { Mv-Move $win $x $y $ww $hh }
  if (-not $hasLib) {
    [W]::ShowHook = { param($h, $c) Mv-Show $h $c; $true }
    [W]::MoveHook = { param($h, $x, $y, $w, $hh) Mv-Move $h $x $y $w $hh; $true }
    [W]::RectHook = { param($h) $r = Mv-Live $h; , [int[]]@($r[0], $r[1], ($r[0] + $r[2]), ($r[1] + $r[3])) }
  }

  # Scope first: every seam is a fake over the model (no [W] call in it), and Move-Win is the one loaded here.
  $fakes = @('Get-WinRect', 'Get-WinRestore', 'Set-WinRestore', 'Show-WinNormal', 'Move-WinRect') | % { $b = (Get-Command $_ -CommandType Function).ScriptBlock.ToString(); $b -match 'Mv-' -and $b -notmatch '\[W\]::' }
  $hooked = $hasLib -or ($null -ne [W]::ShowHook -and $null -ne [W]::MoveHook -and $null -ne [W]::RectHook)
  Check 'move: Move-Win runs against the test model, never Win32' ((@($fakes) -notcontains $false) -and $hooked -and [bool](Get-Command Move-Win -CommandType Function -ErrorAction SilentlyContinue)) "fakes $(@($fakes) -join ','), hooked $hooked"

  function Same($a, $b) { (@($a) -join ',') -eq (@($b) -join ',') }
  $cell = 683, 0, 683, 840    # the right-hand cell: x, y, w, h
  $stale = 0, 0, 684, 2663    # the restore rect the owner's desktop showed
  $snapped = 0, 0, 696, 846   # the live rect of that arranged window
  $plain = 0, 0, 480, 560
  $h0 = [IntPtr]::Zero
  $items = @()                # Move-Win reads this to name the window in its warning; the model has no titles

  # 1. A snapped window with a stale restore rect is moved into the cell.
  New-Win $snapped $stale $true
  $null = Move-Win $h0 683 0 683 840 3>$null
  $w = $script:mvWin
  Check 'move: a snapped window ends with its restore rect at the cell' ((Same $w.Restore $cell) -and -not $w.Arr) "restore $($w.Restore -join ','), snapped $($w.Arr)"
  Check 'move: a snapped window ends at the cell' (Same $w.Live $cell) "window $($w.Live -join ',')"

  # 2. A snapped window placed right gives no off-size note.
  New-Win $snapped $stale $true
  $note = Move-Win $h0 683 0 683 840 3>$null
  Check 'move: a snapped window placed right gives no off-size note' ((-not $note) -and (Same $script:mvWin.Live $cell)) "note '$note', window $($script:mvWin.Live -join ',')"

  # 3. A plain window is moved twice to the cell, with no note and no placement call.
  New-Win $plain $plain $false
  $note = Move-Win $h0 683 0 683 840 3>$null
  $w = $script:mvWin
  Check 'move: a plain window ends at the cell, restore rect too, with no note' ((Same $w.Live $cell) -and (Same $w.Restore $cell) -and -not $w.Arr -and -not $note) "window $($w.Live -join ','), restore $($w.Restore -join ','), snapped $($w.Arr), note '$note'"
  Check 'move: a plain window is moved twice' ($w.Moves -eq 2) "moves $($w.Moves)"
  Check 'move: a plain window gets no placement call' ($w.Sets -eq 0) "placement calls $($w.Sets)"

  # 4. Windows refuses the placement: the stale restore rect is reported with the live size.
  New-Win $snapped $stale $true $false
  $note = Move-Win $h0 683 0 683 840 3>$null
  Check 'move: a stale restore rect is reported with the live size' ("$note" -eq 'off size: is 683x840, restore rect 684x2663') "note '$note'"
}
if ($standalone) { if ($script:fail) { "$script:fail check(s) failed"; exit 1 } else { 'all pass' } }

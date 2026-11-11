# Checks for Move-Win and the placement it uses in tile.ps1. Three kinds, each with its own scope:
#   Model (cases 1-7): Move-Win runs on one window of a model, with its five wrappers faked. No Win32 call, no window touched.
#   Placement: the real Set-WinRestore and Get-WinRestore on a hidden message-only window this file makes (no screen, no user window).
#     Only the workspace offset is faked (10,40). Each case reads the rect back through the real GetWindowPlacement.
#   Arranged: tile.ps1's own W.Arranged, compiled from a copy of its C# with IsWindowArranged stubbed (no snapped window can be made on demand).
# The placement cases fail on a stale restore rect, a dropped workspace offset, or a placement that is never sent. The New-CellPlacement
# case calls tile.ps1's pure placement builder (placement, x, y, w, h, offset -> a copy that shows normal, with its flags and min/max
# copied and a whole new normal RECT). It fails on a dropped showCmd, flags, min/max or offset. A missing or faked name fails its scope check
# first, and the case's other checks do not run.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\move.ps1 [-Tile <path to a tile.ps1 copy>]
# test\run.ps1 dot-sources this file in a child scope, so the variables it makes stay there.
param([string]$Tile = (Join-Path (Split-Path $PSScriptRoot) 'tile.ps1'))
$standalone = -not (Get-Command Check -ErrorAction SilentlyContinue)
if ($standalone) {
  $ErrorActionPreference = 'Stop'; $script:fail = 0
  function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
}
& {
  # The stand-in W for an older copy: the three Win32 calls its Move-Win makes, each forwarding to a hook set below.
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

  # Placement: the real Set-WinRestore and Get-WinRestore, before any fake of them is defined below. Nothing shows on screen.
  if (-not $hasLib) { 'SKIP  placement: needs tile.ps1 with -Lib (an older copy has no Set-WinRestore)' }
  else {
    $setBody = (Get-Command Set-WinRestore -CommandType Function).ScriptBlock.ToString()
    Check 'placement: Set-WinRestore is tile.ps1''s own, not a fake' (($setBody -match '\[W\]::SetWindowPlacement') -and ($setBody -notmatch 'Mv-')) 'the function in scope is not the one in tile.ps1'
    function Get-WorkspaceOffset { [pscustomobject]@{ X = 10; Y = 40 } }
    function Get-PlaceRect($h) { $p = New-Object W+WPL; $p.length = [Runtime.InteropServices.Marshal]::SizeOf($p); [void][W]::GetWindowPlacement($h, [ref]$p); $p.normal }
    function Set-PlaceRect($h, $l, $t, $r, $b) {
      $p = New-Object W+WPL; $p.length = [Runtime.InteropServices.Marshal]::SizeOf($p); [void][W]::GetWindowPlacement($h, [ref]$p)
      $p.showCmd = 1; $rc = New-Object W+RECT; $rc.L = $l; $rc.T = $t; $rc.R = $r; $rc.B = $b; $p.normal = $rc
      [void][W]::SetWindowPlacement($h, [ref]$p)
    }
    $nw = $null; $made = $false; $madeErr = ''
    try {
      $cp = New-Object System.Windows.Forms.CreateParams; $cp.Parent = [IntPtr](-3)   # HWND_MESSAGE: a window with no screen presence
      $nw = New-Object System.Windows.Forms.NativeWindow; $nw.CreateHandle($cp); $made = $nw.Handle -ne [IntPtr]::Zero
    } catch { $madeErr = "$_" }
    Check 'placement: a hidden window of this test can be made' $made "no handle: $madeErr"
    if ($made) {
      try {
        $h = $nw.Handle
        Set-PlaceRect $h 100 200 300 400
        $g = Get-PlaceRect $h
        Check 'placement: the readback returns the rect a placement wrote' ((@($g.L, $g.T, $g.R, $g.B) -join ',') -eq '100,200,300,400') "read $($g.L),$($g.T),$($g.R),$($g.B)"
        # The stale restore rect the owner's desktop showed (684 x 2663), then the real call to the cell 683,0 683x840.
        Set-PlaceRect $h 0 0 684 2663
        Set-WinRestore $h 683 0 683 840
        $n = Get-PlaceRect $h
        Check 'placement: Set-WinRestore replaces a stale restore rect with the cell size' (($n.R - $n.L) -eq 683 -and ($n.B - $n.T) -eq 840) "restore rect $($n.R - $n.L)x$($n.B - $n.T), wanted 683x840"
        Check 'placement: Set-WinRestore puts the restore rect at the cell, less the workspace offset' ((@($n.L, $n.T, $n.R, $n.B) -join ',') -eq '673,-40,1356,800') "restore rect at $($n.L),$($n.T) to $($n.R),$($n.B), wanted 673,-40 to 1356,800"
      } finally { $nw.DestroyHandle() }
    }
    # New-CellPlacement, tile.ps1's pure builder, called directly on a placement whose flags and min/max are not zero.
    # Scope first: the name must be tile.ps1's own before it is called.
    $npCmd = Get-Command New-CellPlacement -CommandType Function -ErrorAction SilentlyContinue
    $npOwn = [bool]$npCmd -and ($npCmd.ScriptBlock.ToString() -match 'New-Object W\+WPL')
    Check 'placement: New-CellPlacement is tile.ps1''s own, not a fake or missing' $npOwn 'no New-CellPlacement from tile.ps1 in scope'
    if ($npOwn) {
      $placement = New-Object W+WPL; $placement.length = [Runtime.InteropServices.Marshal]::SizeOf($placement)
      $placement.flags = 2; $placement.showCmd = 3; $placement.minX = 11; $placement.minY = 22; $placement.maxX = 33; $placement.maxY = 44
      $oldRect = New-Object W+RECT; $oldRect.L = 0; $oldRect.T = 0; $oldRect.R = 684; $oldRect.B = 2663; $placement.normal = $oldRect
      $q = New-CellPlacement $placement 683 0 683 840 ([pscustomobject]@{ X = 10; Y = 40 })
      Check 'placement: New-CellPlacement shows the window normal (showCmd 1)' ($q.showCmd -eq 1) "showCmd $($q.showCmd), wanted 1"
      Check 'placement: New-CellPlacement copies the flags' ($q.flags -eq 2) "flags $($q.flags), wanted 2"
      Check 'placement: New-CellPlacement copies the min and max positions' ((@($q.minX, $q.minY, $q.maxX, $q.maxY) -join ',') -eq '11,22,33,44') "min and max $(@($q.minX, $q.minY, $q.maxX, $q.maxY) -join ','), wanted 11,22,33,44"
      Check 'placement: New-CellPlacement puts the normal rect at the cell, less the offset' ((@($q.normal.L, $q.normal.T, $q.normal.R, $q.normal.B) -join ',') -eq '673,-40,1356,800') "rect $(@($q.normal.L, $q.normal.T, $q.normal.R, $q.normal.B) -join ','), wanted 673,-40,1356,800"
    }
  }

  # Arranged: the real W.Arranged. The fakes never reach it, and no window can be made arranged on demand, so the copy is
  # tile.ps1's own C# with its class renamed and IsWindowArranged stubbed to a flag. Arranged runs as written over that stub.
  if (-not $hasLib) { 'SKIP  arranged: needs tile.ps1 with -Lib (an older copy has no W.Arranged)' }
  else {
    $csNodes = @($tree.FindAll({ param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -match 'public static class W \{' }, $true))
    $src = if ($csNodes.Count) { [string]$csNodes[0].Value } else { '' }
    $stub = $src -replace 'public static class W \{', 'public static class WArr {' -replace '\[DllImport\("user32\.dll"\)\]\s*static extern bool IsWindowArranged\(IntPtr h\);', 'public static bool ArrangedStub; static bool IsWindowArranged(IntPtr h) { return ArrangedStub; }'
    $seamFound = ($stub -match 'class WArr \{') -and ($stub -match 'ArrangedStub; static bool IsWindowArranged')
    Check 'arranged: tile.ps1 holds the Arranged seam (its C# class and IsWindowArranged)' $seamFound "no seam in $Tile"
    $compiled = $false; $compileErr = ''
    if ($seamFound) { try { Add-Type -TypeDefinition $stub -ErrorAction Stop; $compiled = $true } catch { $compileErr = "$_" } }
    Check 'arranged: the copy of W with the stub compiles' $compiled "compile error: $compileErr"
    if ($compiled) {
      [WArr]::ArrangedStub = $true
      Check 'arranged: a window the API reports arranged reads as arranged' ([WArr]::Arranged([IntPtr]::Zero)) 'Arranged gave false while IsWindowArranged gave true'
      [WArr]::ArrangedStub = $false
      Check 'arranged: a window the API reports not arranged reads as not' (-not [WArr]::Arranged([IntPtr]::Zero)) 'Arranged gave true while IsWindowArranged gave false'
    }
  }

  # The model: one window in screen coordinates. Live and Restore are x, y, w, h. Arr: snapped. A maximized or minimized window is
  # modelled as a plain one: Move-Win restores any window that is not snapped, whatever its state.
  # Works: false means Windows refuses a placement. Log lists the calls in order, so a case can check their order.
  function New-Win($live, $restore, $arranged, $works = $true) {
    [pscustomobject]@{ Live = $live; Restore = $restore; Arr = $arranged; Works = $works; Moves = 0; Sets = 0; Log = @(); FirstMoveRestore = $null }
  }
  function Mv-Live($win) { $mv.Live }
  function Mv-Restore($win) { $s = $mv; [pscustomobject]@{ X = $s.Restore[0]; Y = $s.Restore[1]; W = $s.Restore[2]; H = $s.Restore[3]; Arranged = $s.Arr } }
  function Mv-Show($win, $cmd) { $s = $mv; $s.Log += "show $cmd" }
  function Mv-Move($win, $x, $y, $w, $h) {
    $s = $mv; $s.Moves++; $s.Log += 'move'
    if ($s.Moves -eq 1) { $s.FirstMoveRestore = $s.Restore }
    $s.Live = @($x, $y, $w, $h)
    if (-not $s.Arr) { $s.Restore = @($x, $y, $w, $h) }   # a normal window's restore rect follows its move; a snapped one keeps its own
  }
  function Mv-Set($win, $x, $y, $w, $h) {
    $s = $mv; $s.Sets++; $s.Log += 'set'
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
  Check 'move: the model cases run Move-Win against the test model, never Win32' ((@($fakes) -notcontains $false) -and $hooked -and [bool](Get-Command Move-Win -CommandType Function -ErrorAction SilentlyContinue)) "fakes $(@($fakes) -join ','), hooked $hooked"

  function Same($a, $b) { (@($a) -join ',') -eq (@($b) -join ',') }
  $cell = 683, 0, 683, 840    # the right-hand cell: x, y, w, h
  $stale = 0, 0, 684, 2663    # the restore rect the owner's desktop showed
  $snapped = 0, 0, 696, 846   # the live rect of that arranged window
  $plain = 0, 0, 480, 560
  $minimized = -32000, -32000, 160, 28   # where Windows parks a minimized window
  $h0 = [IntPtr]::Zero
  $items = @()                # Move-Win reads this to name the window in its warning; the model has no titles

  # 1. A snapped window with a stale restore rect is moved into the cell.
  $mv = New-Win $snapped $stale $true
  $null = Move-Win $h0 683 0 683 840 3>$null
  $w = $mv
  Check 'move: a snapped window ends with its restore rect at the cell' ((Same $w.Restore $cell) -and -not $w.Arr) "restore $($w.Restore -join ','), snapped $($w.Arr)"
  Check 'move: a snapped window ends at the cell' (Same $w.Live $cell) "window $($w.Live -join ',')"

  # 2. A snapped window placed right gives no off-size note.
  $mv = New-Win $snapped $stale $true
  $note = Move-Win $h0 683 0 683 840 3>$null
  Check 'move: a snapped window placed right gives no off-size note' ((-not $note) -and (Same $mv.Live $cell)) "note '$note', window $($mv.Live -join ',')"

  # 3. A plain window is moved twice to the cell, with no note and no placement call.
  $mv = New-Win $plain $plain $false
  $note = Move-Win $h0 683 0 683 840 3>$null
  $w = $mv
  Check 'move: a plain window ends at the cell, restore rect too, with no note' ((Same $w.Live $cell) -and (Same $w.Restore $cell) -and -not $w.Arr -and -not $note) "window $($w.Live -join ','), restore $($w.Restore -join ','), snapped $($w.Arr), note '$note'"
  Check 'move: a plain window is moved twice' ($w.Moves -eq 2) "moves $($w.Moves)"
  Check 'move: a plain window gets no placement call' ($w.Sets -eq 0) "placement calls $($w.Sets)"

  # 4. Windows refuses the placement: the stale restore rect is reported with the live size.
  $mv = New-Win $snapped $stale $true $false
  $note = Move-Win $h0 683 0 683 840 3>$null
  Check 'move: a stale restore rect is reported with the live size' ("$note" -eq 'off size: is 683x840, restore rect 684x2663') "note '$note'"

  # 5. A snapped window's placement sets its restore rect before the window first moves: moves never set it for a snapped window.
  $mv = New-Win $snapped $stale $true
  $null = Move-Win $h0 683 0 683 840 3>$null
  Check 'move: a snapped window has its restore rect at the cell before its first move' (Same $mv.FirstMoveRestore $cell) "first move saw restore $($mv.FirstMoveRestore -join ',')"

  # 6. A maximized window that is not snapped is restored (ShowWindow 9) before its first move.
  $mv = New-Win $plain $plain $false
  $null = Move-Win $h0 683 0 683 840 3>$null
  Check 'move: a maximized window is restored before its first move' (($mv.Log.Count -gt 0) -and ($mv.Log[0] -eq 'show 9')) "calls $($mv.Log -join ' > ')"

  # 7. A minimized window that is not snapped is restored (ShowWindow 9) before its first move.
  $mv = New-Win $minimized $plain $false
  $null = Move-Win $h0 683 0 683 840 3>$null
  Check 'move: a minimized window is restored before its first move' (($mv.Log.Count -gt 0) -and ($mv.Log[0] -eq 'show 9')) "calls $($mv.Log -join ' > ')"
}
if ($standalone) { if ($script:fail) { "$script:fail check(s) failed"; exit 1 } else { 'all pass' } }

# Config v4 (decision monitor-setups): the v3 -> v4 migration, setup keys, setup registration, and the layout a setup
# resolves to. Plus deep layouts through the config path. Plain asserts, one FAIL line per failing check.
# Touches no real profile: TILE_HOME and USERPROFILE point into this run's folder, set before config.ps1 is read.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\setup-config.ps1
# test\run.ps1 runs this file in a child powershell and counts its FAIL lines.
#
# Shape under test (what the builder must meet):
#   monitors: {<id>: {name, builtin, lastSeen}}      setups: {<key>: {name, ids[], lastUsed}}
#   scene.layouts: {<key>: {grids: {<id>: {c, r}}, pins, zones, fill: {mon, held}, bay}}
#   scene.grids, pins and fill stay role-keyed (wide, tall, laptop): they are the seed template.
# Seeding (coordinator pick, 2026-11-17 13:26 CST): laptop = the built-in screen; wide = the widest non-builtin landscape screen, any
#   aspect, 16:9 included; tall = a non-builtin screen taller than wide. Each role goes to one screen (the widest, then the lowest id).
#   A zero width or height has no shape. A 16:9 external that takes wide is named "Monitor N" unless wider than 2:1 ("Ultrawide").
#   A lone plugged screen holds laptop and wide, and tall when it is portrait, as on main (coordinator ruling 2026-11-17 17:42 CST).
#   With two or more screens the rule above stands: a built-in never takes wide.
# A key is the sorted monitor ids joined. Its separator is not pinned: every key here comes from the product.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
# One case. An error inside it (a name the code does not define yet, say) is one FAIL line, and the run goes on.
function Case([string]$name, [scriptblock]$body) { try { & $body } catch { $script:fail++; "FAIL  $name  threw: $($_.Exception.Message)" } }

# Run folder (test-temp-standard): one temp root for this repo, one <pid>-<uuid> folder per run. The first request of a run
# removes sibling run folders over a day old and keeps newer ones. Teardown removes this run's folder.
. (Join-Path $PSScriptRoot 'run-folders.ps1')
function Remove-OldRunFolders([string]$Root, [string]$Own, [datetime]$Now) {
  Invoke-RunFolderSweep $Root '^\d+-[0-9a-f]{32}$' ([TimeSpan]::FromDays(1)) $Now $Own
}
$tempRoot = Join-Path $env:TEMP 'tile-windows-test'
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
Remove-OldRunFolders -Root $tempRoot -Own '' -Now (Get-Date)
$runDir = Join-Path $tempRoot ('{0}-{1}' -f $PID, ([guid]::NewGuid().ToString('n')))
New-Item -ItemType Directory -Path $runDir | Out-Null

# Canonical JSON: keys sorted, so a test never depends on the order the file writes them in. Arrays keep their order.
function Canon($o) {
  if ($null -eq $o) { return 'null' }
  if ($o -is [System.Management.Automation.PSCustomObject]) {
    $pairs = @($o.PSObject.Properties | Sort-Object Name | ForEach-Object { (ConvertTo-Json -Compress -InputObject $_.Name) + ':' + (Canon $_.Value) })
    return '{' + ($pairs -join ',') + '}'
  }
  if ($o -is [Array]) { $items = @($o); return '[' + ((@($items | ForEach-Object { Canon $_ })) -join ',') + ']' }
  return (ConvertTo-Json -Compress -InputObject $o)
}
# The first path where a value in $old is missing from $new or changed. $null when every old value is kept as it was.
# $Skip lists paths that are allowed to change, such as '$.version' (the schema version moves on purpose).
function Find-Lost($old, $new, [string]$path = '$', [string[]]$Skip = @()) {
  if ($old -is [System.Management.Automation.PSCustomObject]) {
    if ($new -isnot [System.Management.Automation.PSCustomObject]) { return "$path (not an object)" }
    foreach ($p in @($old.PSObject.Properties)) {
      if ($Skip -ccontains "$path.$($p.Name)") { continue }
      $np = @($new.PSObject.Properties | Where-Object { $_.Name -ceq $p.Name })[0]
      if ($null -eq $np) { return "$path.$($p.Name) (missing)" }
      $d = Find-Lost $p.Value $np.Value "$path.$($p.Name)" $Skip
      if ($d) { return $d }
    }
    return $null
  }
  if ($old -is [Array]) {
    $oa = @($old); $na = @($new)
    if ($new -isnot [Array] -or $oa.Count -ne $na.Count) { return "$path (array changed)" }
    for ($i = 0; $i -lt $oa.Count; $i++) { $d = Find-Lost $oa[$i] $na[$i] "$path[$i]" $Skip; if ($d) { return $d } }
    return $null
  }
  if ((Canon $old) -ceq (Canon $new)) { return $null }
  return "$path ($(Canon $old) -> $(Canon $new))"
}
function Count-Props($o) { if ($null -eq $o) { 0 } else { @($o.PSObject.Properties).Count } }
function IsV4($cfg) { [bool]$cfg.PSObject.Properties['monitors'] -and [bool]$cfg.PSObject.Properties['setups'] }
function SceneOf($cfg, [string]$id) { @($cfg.scenes | Where-Object { $_.id -eq $id })[0] }
# A grid cell as "c,r", or "none" when the grids object has no entry for that monitor id.
function Cell($grids, [string]$id) { $g = $grids.$id; if ($null -eq $g) { 'none' } else { '{0},{1}' -f $g.c, $g.r } }
function New-Grid($c, $r) { [pscustomobject]@{ c = $c; r = $r } }
function New-Layout($grids) {
  [pscustomobject]@{ grids = (New-Object PSObject -Property $grids); pins = @(); zones = @(); fill = [pscustomobject]@{ mon = $null; held = @() }; bay = [pscustomobject]@{} }
}
function Set-Layout($scene, [string]$key, $layout) {
  if (-not $scene.PSObject.Properties['layouts']) { $scene | Add-Member -NotePropertyName layouts -NotePropertyValue ([pscustomobject]@{}) }
  $scene.layouts | Add-Member -NotePropertyName $key -NotePropertyValue $layout -Force
}
function Set-Used($cfg, [string]$key, [string]$when) { $cfg.setups.$key | Add-Member -NotePropertyName lastUsed -NotePropertyValue $when -Force }
# A monitor object as the snapshot gives it. bw and bh are the native size; w and h are the size at the current scale.
function New-Mon([string]$id, [string]$name, [int]$x, [int]$y, [int]$w, [int]$h, [bool]$builtin = $false, $bw = $null, $bh = $null) {
  [pscustomobject]@{ id = $id; name = $name; x = $x; y = $y; w = $w; h = $h; bw = $(if ($null -eq $bw) { $w } else { $bw }); bh = $(if ($null -eq $bh) { $h } else { $bh }); builtin = $builtin }
}
# Neutral display names: the shape names come from the product, so a fixture never carries one.
$Laptop = New-Mon 'laptop' 'Panel A' 0 1200 1920 1200 $true
$Ultra = New-Mon 'ultra' 'Panel B' 1920 0 3440 1440     # wider than 2:1
$Port = New-Mon 'port' 'Panel C' -1080 0 1080 1920      # taller than wide
$Uhd = New-Mon 'uhd' 'Panel D' 5360 0 3840 2160         # widest in pixels and 16:9: the widest landscape screen takes wide (pick 2026-11-17 13:26 CST)
# Screens for the seeding pick (2026-11-17 13:26 CST). The ids sort so the wider 16:9 screen comes after the narrower one.
$Lap15 = New-Mon 'laptop' 'Panel A' 0 1200 1536 960 $true   # the built-in screen at 1536x960 (a 1.6:1 panel)
$Ext1 = New-Mon 'ext1' 'Panel E' 1536 0 1920 1080           # 16:9 external, narrower
$Ext2 = New-Mon 'ext2' 'Panel F' 3456 0 2560 1440           # 16:9 external, wider
$TieA = New-Mon 'tie1' 'Panel G' 6016 0 2560 1440           # 16:9, the same width as tie2
$TieB = New-Mon 'tie2' 'Panel H' 8576 0 2560 1440
$ZeroW = New-Mon 'zerow' 'Panel I' 11136 0 0 1080           # zero width, 1080 tall: no shape
$ZeroH = New-Mon 'zeroh' 'Panel J' 11136 1200 1920 0        # 1920 wide, zero height: no shape

# The repo's v3 scenes.json is the input (the owner's shape). If the working file has moved on, the v3 text is read at the base commit.
$v3Base = '5de673d'
$v3Text = [IO.File]::ReadAllText((Join-Path $root 'scenes.json'), $utf8)
if ((ConvertFrom-Json $v3Text).version -ne 3) { $v3Text = (& git -C $root show "${v3Base}:scenes.json") -join "`n" }

# A config with the v3 -> v4 migration applied. Update-TileConfig returns its input unchanged when nothing migrates.
$saved = @{ USERPROFILE = $env:USERPROFILE; APPDATA = $env:APPDATA; TILE_HOME = $env:TILE_HOME }
$env:USERPROFILE = Join-Path $runDir 'profile'; $env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'
$env:TILE_HOME = Join-Path $runDir 'home'
try {
  . (Join-Path $root 'config.ps1')
  $v4Text = Update-TileConfig $v3Text

  # A v4 deep layout: a scene's layouts with pins that hang windows behind (behind is nested three levels down).
  $deepText = @'
{"version":4,"categories":[["code","Code"]],"cats":{},"appNames":{},"monitors":{},"setups":{},
"scenes":[{"id":"deep","name":"Deep","grids":{"wide":{"c":2,"r":1}},
"layouts":{"k-deep":{"grids":{"laptop":{"c":1,"r":1}},
"pins":[{"app":"chrome","match":"","mon":"laptop","slots":[0],"behind":[{"app":"outlook","match":"- Outlook"},{"app":"ms-teams","match":""}]}],
"zones":[],"fill":{"mon":"laptop","held":[]},"bay":{}}}}]}
'@

  # ---- Green controls: the v3 input is read, and the current code accepts it ----
  Case 'input: the v3 scenes are version 3 with scenes' {
    $v3 = ConvertFrom-Json $v3Text
    Check 'input: the v3 scenes are version 3, with scenes' ($v3.version -eq 3 -and @($v3.scenes).Count -ge 1) "version $($v3.version)"
  }
  Case 'input: Test-TileConfig accepts the v3 scenes' {
    $err = $null; try { Test-TileConfig $v3Text } catch { $err = $_.Exception.Message }
    Check 'input: Test-TileConfig accepts the v3 scenes' ($null -eq $err) "$err"
  }

  # ---- v3 -> v4 migration ----
  Case 'migration: the version becomes 4' {
    $v4 = ConvertFrom-Json $v4Text
    Check 'migration: the version is 4' ($v4.version -eq 4) "version is $($v4.version)"
  }
  Case 'migration: an empty monitors object is added' {
    $v4 = ConvertFrom-Json $v4Text
    Check 'migration: monitors is an empty object' ([bool]$v4.PSObject.Properties['monitors'] -and (Count-Props $v4.monitors) -eq 0) 'monitors is absent or has entries'
  }
  Case 'migration: an empty setups object is added' {
    $v4 = ConvertFrom-Json $v4Text
    Check 'migration: setups is an empty object' ([bool]$v4.PSObject.Properties['setups'] -and (Count-Props $v4.setups) -eq 0) 'setups is absent or has entries'
  }
  Case 'migration: each scene gets an empty layouts object' {
    $v4 = ConvertFrom-Json $v4Text; $scenes = @($v4.scenes)
    Check 'migration: scope, the v4 config has scenes' ($scenes.Count -ge 1) 'no scenes read'
    $bad = @($scenes | Where-Object { -not $_.PSObject.Properties['layouts'] -or (Count-Props $_.layouts) -ne 0 } | ForEach-Object { [string]$_.id })
    Check 'migration: every scene has an empty layouts object' ($bad.Count -eq 0) "scenes without one: $($bad -join ', ')"
  }
  Case 'migration: every existing value is kept' {
    # The version moves 3 -> 4 on purpose; every other v3 value must stay as it was.
    $lost = Find-Lost (ConvertFrom-Json $v3Text) (ConvertFrom-Json $v4Text) -Skip '$.version'
    Check 'migration: every v3 value is still there, unchanged' ($null -eq $lost) "first lost: $lost"
  }
  Case 'migration: a second update gives the same JSON' {
    $again = Update-TileConfig $v4Text
    Check 'migration: the second update gives the same JSON' ((Canon (ConvertFrom-Json $again)) -ceq (Canon (ConvertFrom-Json $v4Text))) 'a second update changed the v4 config'
  }
  Case 'migration: the v4 config passes Test-TileConfig' {
    $err = $null; try { Test-TileConfig $v4Text } catch { $err = $_.Exception.Message }
    Check 'migration: Test-TileConfig accepts the v4 config' ($null -eq $err) "$err"
  }
  Case 'migration: updates on a v3 file never seed monitor, setup or layout entries' {
    $v = ConvertFrom-Json (Update-TileConfig (Update-TileConfig $v3Text))
    $n = (Count-Props $v.monitors) + (Count-Props $v.setups)
    Check 'never seeds: no monitor or setup entries after two updates' ($n -eq 0) "monitor and setup entries: $n"
    $layoutN = @(@($v.scenes) | ForEach-Object { Count-Props $_.layouts } | Where-Object { $_ -ne 0 })
    Check 'never seeds: no layout entries after two updates' ($layoutN.Count -eq 0) "scenes with layout entries: $($layoutN.Count)"
  }
  # The "second update" case above returns early (version 4 is not below the starters' version), so it proves nothing about the
  # migration body. These two rewind the version to 3, the version the input had, so the body runs again on migrated data.
  Case 'migration again: the body runs on the empty v4 result and changes nothing' {
    $e = ConvertFrom-Json $v4Text
    $ok = IsV4 $e
    Check 'migration again empty: scope, the v4 result has the monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $before = ConvertFrom-Json $v4Text
    $e | Add-Member -Force -NotePropertyName version -NotePropertyValue 3
    $re = ConvertFrom-Json (Update-TileConfig (ConvertTo-Json -Depth 10 $e))
    Check 'migration again empty: the body ran, so the version is 4 again' ($re.version -eq 4) "version: $($re.version)"
    Check 'migration again empty: the config comes back with the same JSON' ((Canon $re) -ceq (Canon $before)) "first changed: $(Find-Lost $before $re)"
  }
  Case 'migration again: the body runs on a config with a setup, a layout and a pin with behind, and changes nothing' {
    $f = ConvertFrom-Json $v4Text
    $ok = IsV4 $f
    Check 'migration again full: scope, the v4 result has the monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $f 'default'
    Check 'migration again full: scope, the default scene is read' ($null -ne $sc) 'no default scene'
    if ($null -eq $sc) { return }
    $k = Register-TileSetup $f @($Laptop, $Ultra)
    $lay = New-Layout @{ laptop = (New-Grid 2 2); ultra = (New-Grid 4 1) }
    $lay.pins = @([pscustomobject]@{ app = 'chrome'; match = ''; mon = 'laptop'; slots = @(0); behind = @([pscustomobject]@{ app = 'outlook'; match = '- Outlook' }) })
    Set-Layout $sc $k $lay
    Set-Used $f $k '2026-11-15T10:00:00'
    $before = ConvertFrom-Json (ConvertTo-Json -Depth 10 $f)
    $f | Add-Member -Force -NotePropertyName version -NotePropertyValue 3
    $re = ConvertFrom-Json (Update-TileConfig (ConvertTo-Json -Depth 10 $f))
    Check 'migration again full: the body ran, so the version is 4 again' ($re.version -eq 4) "version: $($re.version)"
    Check 'migration again full: the setup, layout and pin come back unchanged' ((Canon $re) -ceq (Canon $before)) "first changed: $(Find-Lost $before $re)"
  }

  # ---- Deep layouts through the config path ----
  Case 'deep: a layout with pins that have behind survives ConvertTo-Json -Depth 10 and the config read back' {
    $o = ConvertFrom-Json $deepText
    $sc = SceneOf $o 'deep'
    Check 'deep: scope, the deep scene and its layout are read' ($null -ne $sc -and $null -ne $sc.layouts) 'no deep scene with layouts'
    if ($null -eq $sc -or $null -eq $sc.layouts) { return }
    $orig = $sc.layouts
    $null = Save-TileConfigText (ConvertTo-Json -Depth 10 $o)
    $back = SceneOf (ConvertFrom-Json (Get-TileConfigText)) 'deep'
    Check 'deep: the deep scene reads back' ($null -ne $back -and $null -ne $back.layouts) 'the scene or its layouts did not come back'
    if ($null -eq $back -or $null -eq $back.layouts) { return }
    $lost = Find-Lost $orig $back.layouts
    Check 'deep: every layout value comes back, behind pins included' ($null -eq $lost -and (Canon $back.layouts) -ceq (Canon $orig)) "first lost: $lost"
  }
  Case 'deep: a v3 pin with behind keeps it through the update' {
    $v = ConvertFrom-Json $v3Text
    $sc0 = @($v.scenes | Where-Object { $_.id -eq 'default' })[0]
    $pin = @($sc0.pins)[0]
    Check 'deep: scope, the default scene has a first pin' ($null -ne $pin) 'no pin to hang windows on'
    if ($null -eq $pin) { return }
    $pin | Add-Member -NotePropertyName behind -NotePropertyValue @([pscustomobject]@{ app = 'outlook'; match = '- Outlook' }) -Force
    $orig = $pin.behind
    $up = ConvertFrom-Json (Update-TileConfig (ConvertTo-Json -Depth 10 $v))
    $after = @(@($up.scenes | Where-Object { $_.id -eq 'default' })[0].pins)[0].behind
    Check 'deep: the pin keeps its behind windows through the update' ((Canon $after) -ceq (Canon $orig)) "after: $(Canon $after)"
  }

  # ---- Setup key: sorted ids, ignoring order, position and scale ----
  Case 'setup key: the order of the monitors does not change it' {
    $a = [string](Get-TileSetupKey @($Laptop, $Ultra, $Port)); $b = [string](Get-TileSetupKey @($Port, $Laptop, $Ultra))
    Check 'setup key: the key is not empty' ($a -ne '') 'the key is empty'
    Check 'setup key: the same screens in another order give the same key' ($a -ceq $b) "$a | $b"
  }
  Case 'setup key: position and scale do not change it' {
    $base = [string](Get-TileSetupKey @($Laptop, $Ultra))
    $moved = New-Mon 'laptop' 'Panel A' 2400 -300 1920 1200 $true
    $scaled = New-Mon 'laptop' 'Panel A' 0 1200 1280 800 $true -bw 1920 -bh 1200
    Check 'setup key: moving a screen keeps the key' ([string](Get-TileSetupKey @($moved, $Ultra)) -ceq $base) 'the key changed when a screen moved'
    Check 'setup key: a new scale keeps the key' ([string](Get-TileSetupKey @($scaled, $Ultra)) -ceq $base) 'the key changed when a scale changed'
  }
  Case 'setup key: a different set of screens gives a different key' {
    $two = [string](Get-TileSetupKey @($Laptop, $Ultra))
    $three = [string](Get-TileSetupKey @($Laptop, $Ultra, $Port))
    $swap = [string](Get-TileSetupKey @($Laptop, $Port))
    Check 'setup key: adding a screen changes the key' ($two -cne $three) "$two | $three"
    Check 'setup key: replacing a screen changes the key' ($two -cne $swap) "$two | $swap"
  }
  Case 'setup key: the ids in the key are sorted' {
    $k = [string](Get-TileSetupKey @($Ultra, $Port, $Laptop))
    $at = @('laptop', 'port', 'ultra') | ForEach-Object { $k.IndexOf($_) }
    Check 'setup key: the ids appear in sorted order' ($at[0] -ge 0 -and $at[0] -lt $at[1] -and $at[1] -lt $at[2]) "key: $k"
  }

  # ---- Register-TileSetup: shape names, Desk, no duplicates ----
  Case 'register: unknown screens are named by shape' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'register names: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $null = Register-TileSetup $cfg @($Laptop, $Ultra, $Port)
    Check 'register: the built-in screen is named Laptop' ([string]$cfg.monitors.laptop.name -like 'Laptop*') "name: $([string]$cfg.monitors.laptop.name)"
    Check 'register: a screen wider than 2:1 is named Ultrawide' ([string]$cfg.monitors.ultra.name -like 'Ultrawide*') "name: $([string]$cfg.monitors.ultra.name)"
    Check 'register: a screen taller than wide is named Portrait' ([string]$cfg.monitors.port.name -like 'Portrait*') "name: $([string]$cfg.monitors.port.name)"
  }
  Case 'register: a screen already in the config keeps its name' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'register keeps names: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $null = Register-TileSetup $cfg @($Ultra)
    $cfg.monitors.ultra | Add-Member -NotePropertyName name -NotePropertyValue 'Desk wide' -Force
    $null = Register-TileSetup $cfg @($Ultra, $Laptop)
    Check 'register: a known screen keeps the name it was given' ([string]$cfg.monitors.ultra.name -ceq 'Desk wide') "name: $([string]$cfg.monitors.ultra.name)"
  }
  Case 'register: the first setup is named Desk' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'register first setup: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $k = Register-TileSetup $cfg @($Laptop, $Ultra)
    $count = Count-Props $cfg.setups
    Check 'register: the first registration adds exactly one setup' ($count -eq 1) "setups: $count"
    Check 'register: that setup is named Desk' ([string]$cfg.setups.$k.name -ceq 'Desk') "name: $([string]$cfg.setups.$k.name)"
  }
  Case 'register: a second call with the same screens adds nothing' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'register repeat: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $k1 = Register-TileSetup $cfg @($Laptop, $Ultra)
    $s1 =Count-Props $cfg.setups; $m1 = Count-Props $cfg.monitors
    $k2 = Register-TileSetup $cfg @($Ultra, $Laptop)
    Check 'register: no setup is added by the second call' ((Count-Props $cfg.setups) -eq $s1) "setups: $(Count-Props $cfg.setups), was $s1"
    Check 'register: no screen is added by the second call' ((Count-Props $cfg.monitors) -eq $m1) "monitors: $(Count-Props $cfg.monitors), was $m1"
    Check 'register: the second call returns the same key' ([string]$k2 -ceq [string]$k1) "$k1 | $k2"
  }
  Case 'register: returns the setup key of the screens' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'register key: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $k = [string](Register-TileSetup $cfg @($Laptop, $Ultra))
    Check 'register: the returned key is not empty' ($k -ne '') 'no key returned'
    Check 'register: the returned key is the key of those screens' ($k -ceq [string](Get-TileSetupKey @($Laptop, $Ultra))) "returned: $k"
  }

  # ---- Resolve-TileLayout: own layout, closest setup, tie to last used, seed by shape, no grid for a missing screen ----
  Case 'resolve: a setup with its own layout gets its own, over a closer setup' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve own: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve own: the default scene is read' ($null -ne $sc) 'no default scene'
    $own = Register-TileSetup $cfg @($Laptop, $Ultra)
    $other = Register-TileSetup $cfg @($Laptop, $Ultra, $Port)
    Set-Layout $sc $own (New-Layout @{ laptop = (New-Grid 2 2); ultra = (New-Grid 4 1) })
    Set-Layout $sc $other (New-Layout @{ laptop = (New-Grid 1 1); ultra = (New-Grid 5 2); port = (New-Grid 1 2) })
    # The other setup shares as many screens and was used last, so a Resolve that ignores the own layout takes its layout instead.
    Set-Used $cfg $own '2026-11-01T10:00:00'
    Set-Used $cfg $other '2026-11-15T10:00:00'
    $r = Resolve-TileLayout $cfg $sc $own
    Check 'resolve own: laptop keeps the cell of its own layout' ((Cell $r.grids 'laptop') -ceq '2,2') "cell: $(Cell $r.grids 'laptop')"
    Check 'resolve own: ultra keeps the cell of its own layout' ((Cell $r.grids 'ultra') -ceq '4,1') "cell: $(Cell $r.grids 'ultra')"
  }
  Case 'resolve: with no layout of its own, the closest setup by shared screens supplies it' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve closest: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve closest: the default scene is read' ($null -ne $sc) 'no default scene'
    $k1 = Register-TileSetup $cfg @($Laptop, $Ultra, $Port)
    $k2 = Register-TileSetup $cfg @($Laptop, $Uhd)
    $k3 = Register-TileSetup $cfg @($Laptop, $Ultra)
    Set-Layout $sc $k1 (New-Layout @{ laptop = (New-Grid 1 1); ultra = (New-Grid 5 2); port = (New-Grid 1 2) })
    Set-Layout $sc $k2 (New-Layout @{ laptop = (New-Grid 2 1); uhd = (New-Grid 3 3) })
    $r = Resolve-TileLayout $cfg $sc $k3
    Check 'resolve closest: laptop takes the cell of the setup with the most screens shared' ((Cell $r.grids 'laptop') -ceq '1,1') "cell: $(Cell $r.grids 'laptop')"
    Check 'resolve closest: ultra takes the cell of the setup with the most screens shared' ((Cell $r.grids 'ultra') -ceq '5,2') "cell: $(Cell $r.grids 'ultra')"
  }
  Case 'resolve: a tie on shared screens goes to the setup used last' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve tie: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve tie: the default scene is read' ($null -ne $sc) 'no default scene'
    $k1 = Register-TileSetup $cfg @($Laptop, $Ultra, $Port)
    $k2 = Register-TileSetup $cfg @($Laptop, $Ultra, $Uhd)
    $k3 = Register-TileSetup $cfg @($Laptop, $Ultra)
    Set-Used $cfg $k1 '2026-11-01T10:00:00'
    Set-Used $cfg $k2 '2026-11-15T10:00:00'
    Set-Layout $sc $k1 (New-Layout @{ laptop = (New-Grid 1 1); ultra = (New-Grid 5 2) })
    Set-Layout $sc $k2 (New-Layout @{ laptop = (New-Grid 3 1); ultra = (New-Grid 4 4) })
    $r = Resolve-TileLayout $cfg $sc $k3
    Check 'resolve tie: laptop takes the cell of the setup used last' ((Cell $r.grids 'laptop') -ceq '3,1') "cell: $(Cell $r.grids 'laptop')"
    Check 'resolve tie: ultra takes the cell of the setup used last' ((Cell $r.grids 'ultra') -ceq '4,4') "cell: $(Cell $r.grids 'ultra')"
  }
  Case 'resolve: with nothing known, the layout is seeded from the role template by shape' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve seed: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    $roles = ((Cell $sc.grids 'wide') -ceq '5,2') -and ((Cell $sc.grids 'tall') -ceq '1,2') -and ((Cell $sc.grids 'laptop') -ceq '1,1')
    Check 'resolve seed: scope, the scene has its role grids (wide 5,2, tall 1,2, laptop 1,1)' $roles "wide $(Cell $sc.grids 'wide'), tall $(Cell $sc.grids 'tall'), laptop $(Cell $sc.grids 'laptop')"
    # Re-pointed to the pick (coordinator, 2026-11-17 13:26 CST): wide is the widest landscape screen, 16:9 included. Uhd (3840) takes it;
    # Ultra (3440, wider than 2:1 but narrower) is the second screen of that shape and gets no seeded grid.
    $k = Register-TileSetup $cfg @($Uhd, $Ultra, $Port, $Laptop)
    $r = Resolve-TileLayout $cfg $sc $k
    Check 'resolve seed: the widest landscape screen takes the wide cell, 16:9 included' ((Cell $r.grids 'uhd') -ceq '5,2') "uhd: $(Cell $r.grids 'uhd')"
    Check 'resolve seed: a second landscape screen gets no seeded grid' ((Cell $r.grids 'ultra') -ceq 'none') "ultra: $(Cell $r.grids 'ultra')"
    Check 'resolve seed: the portrait screen takes the tall cell' ((Cell $r.grids 'port') -ceq '1,2') "port: $(Cell $r.grids 'port')"
    Check 'resolve seed: the built-in screen takes the laptop cell' ((Cell $r.grids 'laptop') -ceq '1,1') "laptop: $(Cell $r.grids 'laptop')"
  }
  Case 'resolve: a screen the key does not have gets no grid' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve missing: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve missing: the default scene is read' ($null -ne $sc) 'no default scene'
    $k1 = Register-TileSetup $cfg @($Laptop, $Ultra)
    $k2 = Register-TileSetup $cfg @($Laptop)
    Set-Layout $sc $k1 (New-Layout @{ laptop = (New-Grid 1 1); ultra = (New-Grid 5 2) })
    $r = Resolve-TileLayout $cfg $sc $k2
    Check 'resolve missing: the screen the key has keeps its cell' ((Cell $r.grids 'laptop') -ceq '1,1') "cell: $(Cell $r.grids 'laptop')"
    Check 'resolve missing: the screen the key lacks has no grid in the result' ((Cell $r.grids 'ultra') -ceq 'none') "cell: $(Cell $r.grids 'ultra')"
  }

  Case 'resolve: a screen the key adds to the closest setup takes its shape grid from the role template' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve grow: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve grow: the default scene is read' ($null -ne $sc) 'no default scene'
    if ($null -eq $sc) { return }
    Check 'resolve grow: scope, the scene has a wide role grid to seed from' ((Cell $sc.grids 'wide') -cne 'none') "wide: $(Cell $sc.grids 'wide')"
    # The closest setup (laptop and portrait) has its own cells, different from the template's, so a seed from the template alone fails the controls.
    $k1 = Register-TileSetup $cfg @($Laptop, $Port)
    $lay1 = New-Layout @{ laptop = (New-Grid 2 1); port = (New-Grid 4 2) }
    Set-Layout $sc $k1 $lay1
    $k3 = Register-TileSetup $cfg @($Laptop, $Port, $Ultra)
    Check 'resolve grow: scope, the closest setup has no grid for the new wide screen' ((Cell $lay1.grids 'ultra') -ceq 'none') "cell: $(Cell $lay1.grids 'ultra')"
    $r = Resolve-TileLayout $cfg $sc $k3
    Check 'resolve grow: laptop keeps the cell of the closest setup' ((Cell $r.grids 'laptop') -ceq '2,1') "cell: $(Cell $r.grids 'laptop')"
    Check 'resolve grow: port keeps the cell of the closest setup' ((Cell $r.grids 'port') -ceq '4,2') "cell: $(Cell $r.grids 'port')"
    $want = Cell $sc.grids 'wide'
    Check 'resolve grow: the new wide screen takes the wide cell of the role template' ((Cell $r.grids 'ultra') -ceq $want) "ultra: $(Cell $r.grids 'ultra'), template wide: $want"
  }

  # ---- Seeding by the coordinator pick (2026-11-17 13:26 CST): the wide role goes to the widest landscape screen, 16:9 included ----
  Case 'resolve seed: an empty scene resolves to empty zones and pins, in the stored form' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve empty: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve empty: scope, the default scene is read' ($null -ne $sc) 'no default scene'
    if ($null -eq $sc) { return }
    $sc | Add-Member -Force -NotePropertyName pins -NotePropertyValue @()
    $sc | Add-Member -Force -NotePropertyName zones -NotePropertyValue @()
    $k = Register-TileSetup $cfg @($Lap15)
    Check 'resolve empty: scope, the setup has no layout of its own, so the role template is used' (-not $sc.layouts.PSObject.Properties[$k]) 'the setup already has a layout'
    $r = Resolve-TileLayout $cfg $sc $k
    $txt = ConvertTo-Json -InputObject $r -Depth 10 -Compress
    Check 'resolve empty: the stored pins are []' ($txt -cmatch '"pins":\[\]') ([regex]::Match($txt, '"pins":.{0,30}').Value)
    Check 'resolve empty: the stored zones are []' ($txt -cmatch '"zones":\[\]') ([regex]::Match($txt, '"zones":.{0,30}').Value)
  }
  Case 'resolve seed: a scene with one pin and one zone keeps both in the stored form' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve full: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve full: scope, the default scene is read' ($null -ne $sc) 'no default scene'
    if ($null -eq $sc) { return }
    $sc | Add-Member -Force -NotePropertyName pins -NotePropertyValue @([pscustomobject]@{ app = 'chrome'; match = 'Pull'; mon = 'wide'; slots = @(1) })
    $sc | Add-Member -Force -NotePropertyName zones -NotePropertyValue @([pscustomobject]@{ mon = 'wide'; slots = @(0, 1); app = 'claude' })
    $k = Register-TileSetup $cfg @($Lap15)
    $r = Resolve-TileLayout $cfg $sc $k
    $back = ConvertFrom-Json (ConvertTo-Json -Depth 10 -Compress -InputObject $r)
    Check 'resolve full: the one pin is kept' (@($back.pins).Count -eq 1 -and $back.pins[0].app -ceq 'chrome') "pins: $(Canon $back.pins)"
    Check 'resolve full: the one zone is kept' (@($back.zones).Count -eq 1 -and $back.zones[0].app -ceq 'claude') "zones: $(Canon $back.zones)"
  }
  Case 'resolve seed: a laptop with a 16:9 external: the external takes the wide cell, the laptop its own, and the name is Monitor N' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve 16:9: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve 16:9: scope, the scene has its role grids (wide 5,2, laptop 1,1)' ((Cell $sc.grids 'wide') -ceq '5,2' -and (Cell $sc.grids 'laptop') -ceq '1,1') "wide $(Cell $sc.grids 'wide'), laptop $(Cell $sc.grids 'laptop')"
    $k = Register-TileSetup $cfg @($Lap15, $Ext2)
    Check 'resolve 16:9: the built-in screen is named Laptop' ([string]$cfg.monitors.laptop.name -like 'Laptop*') "name: $([string]$cfg.monitors.laptop.name)"
    Check 'resolve 16:9: the 2560x1440 external is named Monitor N, not Ultrawide' ([string]$cfg.monitors.ext2.name -cmatch '^Monitor \d+$') "name: $([string]$cfg.monitors.ext2.name)"
    $r = Resolve-TileLayout $cfg $sc $k
    Check 'resolve 16:9: the external takes the wide cell of the role template' ((Cell $r.grids 'ext2') -ceq '5,2') "ext2: $(Cell $r.grids 'ext2')"
    Check 'resolve 16:9: the laptop keeps the laptop cell' ((Cell $r.grids 'laptop') -ceq '1,1') "laptop: $(Cell $r.grids 'laptop')"
  }
  Case 'resolve seed: a lone built-in laptop also holds the wide role' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve lone laptop: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve lone laptop: scope, the default scene is read' ($null -ne $sc) 'no default scene'
    if ($null -eq $sc) { return }
    Check 'resolve lone laptop: scope, the default scene has a wide cell (5,2) and a laptop cell (1,1)' ((Cell $sc.grids 'wide') -ceq '5,2' -and (Cell $sc.grids 'laptop') -ceq '1,1') "wide $(Cell $sc.grids 'wide'), laptop $(Cell $sc.grids 'laptop')"
    $k = Register-TileSetup $cfg @($Lap15)
    $r = Resolve-TileLayout $cfg $sc $k
    # A monitor that holds several roles seeds its grid in tile.ps1's Roles order: wide, then tall, then laptop (coordinator ruling 2026-11-17 18:07 CST).
    Check 'resolve lone laptop: the laptop takes the wide cell, which the wide role seeds first' ((Cell $r.grids 'laptop') -ceq (Cell $sc.grids 'wide')) "laptop: $(Cell $r.grids 'laptop'), scene wide: $(Cell $sc.grids 'wide')"
    Check 'resolve lone laptop: scope, the built-in is registered as a monitor' ($null -ne $cfg.monitors.PSObject.Properties['laptop']) 'no laptop monitor in the config'
    $wideRole = (Get-TileRoles $cfg.monitors @('laptop'))['wide']
    Check 'resolve lone laptop: the lone built-in holds the wide role too' ([string]$wideRole -ceq 'laptop') "wide role: '$([string]$wideRole)'"
  }
  Case 'resolve seed: a lone portrait takes the wide cell of the scene, not its tall cell' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve lone portrait: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve lone portrait: scope, the default scene has a wide cell (5,2) and a tall cell (1,2)' ((Cell $sc.grids 'wide') -ceq '5,2' -and (Cell $sc.grids 'tall') -ceq '1,2') "wide $(Cell $sc.grids 'wide'), tall $(Cell $sc.grids 'tall')"
    $k = Register-TileSetup $cfg @($Port)
    $portWide = [string]((Get-TileRoles $cfg.monitors @('port'))['wide'])
    Check 'resolve lone portrait: scope, the lone portrait holds the wide role' ($portWide -ceq 'port') "wide role: '$portWide'"
    $r = Resolve-TileLayout $cfg $sc $k
    Check 'resolve lone portrait: the portrait takes the wide cell of the scene' ((Cell $r.grids 'port') -ceq (Cell $sc.grids 'wide')) "port: $(Cell $r.grids 'port'), scene wide: $(Cell $sc.grids 'wide')"
  }
  # Control, green on the old code: a scene with no wide cell seeds the lone portrait's tall cell.
  Case 'control: a lone portrait in a scene with no wide cell takes its tall cell' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'control lone portrait: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    $sc.grids = [pscustomobject]@{ tall = $sc.grids.tall; laptop = $sc.grids.laptop }
    Check 'control lone portrait: scope, the scene has a tall cell (1,2) and no wide cell' ((Cell $sc.grids 'tall') -ceq '1,2' -and (Cell $sc.grids 'wide') -ceq 'none') "tall $(Cell $sc.grids 'tall'), wide $(Cell $sc.grids 'wide')"
    $k = Register-TileSetup $cfg @($Port)
    $r = Resolve-TileLayout $cfg $sc $k
    Check 'control lone portrait: the portrait takes the tall cell' ((Cell $r.grids 'port') -ceq '1,2') "port: $(Cell $r.grids 'port')"
  }
  # A lone plugged monitor holds laptop and wide, and tall when it is portrait (as on main's Pick). Get-TileRoles keys by role; the ids are the
  # monitors' own (Lap15, Ext2, Port are the fixtures above).
  Case 'seed: a lone plugged monitor holds the laptop and wide roles, and tall when it is portrait' {
    $alone = @(
      [pscustomobject]@{ name = 'built-in laptop'; mon = $Lap15; want = @{ laptop = 'laptop'; wide = 'laptop' } },
      [pscustomobject]@{ name = '16:9 external'; mon = $Ext2; want = @{ laptop = 'ext2'; wide = 'ext2' } },
      [pscustomobject]@{ name = 'portrait'; mon = $Port; want = @{ laptop = 'port'; wide = 'port'; tall = 'port' } })
    foreach ($a in $alone) {
      $m = New-Object PSObject
      $m | Add-Member -NotePropertyName ([string]$a.mon.id) -NotePropertyValue ([pscustomobject]@{ name = $a.mon.name; builtin = [bool]$a.mon.builtin; bw = $a.mon.bw; bh = $a.mon.bh })
      Check "seed, lone $($a.name): scope, one monitor is registered" (@($m.PSObject.Properties).Count -eq 1) "monitors: $(@($m.PSObject.Properties).Count)"
      $roles = Get-TileRoles $m @([string]$a.mon.id)
      foreach ($role in $a.want.Keys) {
        Check "seed, lone $($a.name): the $role role is held by it" ([string]$roles[$role] -ceq $a.want[$role]) "${role}: '$([string]$roles[$role])'"
      }
    }
  }
  # Controls, green on the old code: no monitor holds no role, and with two monitors item 14 stands (a built-in never takes wide).
  Case 'seed: with no monitor no role is held, and with a built-in and a portrait no monitor takes wide' {
    $none = Get-TileRoles (New-Object PSObject) @()
    Check 'seed, no monitor: no role is held (control)' (@($none.Keys).Count -eq 0) "roles: $(@($none.Keys) -join ',')"
    $two = New-Object PSObject
    foreach ($x in @($Lap15, $Port)) { $two | Add-Member -NotePropertyName ([string]$x.id) -NotePropertyValue ([pscustomobject]@{ name = $x.name; builtin = [bool]$x.builtin; bw = $x.bw; bh = $x.bh }) }
    Check 'seed, built-in and portrait: scope, two monitors are registered' (@($two.PSObject.Properties).Count -eq 2) "monitors: $(@($two.PSObject.Properties).Count)"
    $roles2 = Get-TileRoles $two @('laptop', 'port')
    Check 'seed, built-in and portrait: no monitor takes wide (control)' ([string]$roles2['wide'] -ceq '') "wide: '$([string]$roles2['wide'])'"
    Check 'seed, built-in and portrait: the portrait takes tall and the built-in takes laptop (control)' (([string]$roles2['tall'] -ceq 'port') -and ([string]$roles2['laptop'] -ceq 'laptop')) "tall: '$([string]$roles2['tall'])' laptop: '$([string]$roles2['laptop'])'"
  }
  Case 'resolve seed: of two 16:9 externals only the wider takes the wide cell' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve two 16:9: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve two 16:9: scope, the default scene is read' ($null -ne $sc) 'no default scene'
    if ($null -eq $sc) { return }
    $k = Register-TileSetup $cfg @($Ext1, $Ext2)
    $r = Resolve-TileLayout $cfg $sc $k
    Check 'resolve two 16:9: the wider external takes the wide cell' ((Cell $r.grids 'ext2') -ceq '5,2') "ext2: $(Cell $r.grids 'ext2')"
    Check 'resolve two 16:9: the narrower external gets no seeded grid' ((Cell $r.grids 'ext1') -ceq 'none') "ext1: $(Cell $r.grids 'ext1')"
  }
  Case 'resolve seed: of two equal-width 16:9 externals the lower id takes the wide cell' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve tie 16:9: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve tie 16:9: scope, the default scene is read' ($null -ne $sc) 'no default scene'
    if ($null -eq $sc) { return }
    $k = Register-TileSetup $cfg @($TieB, $TieA)
    $r = Resolve-TileLayout $cfg $sc $k
    Check 'resolve tie 16:9: the lower id takes the wide cell' ((Cell $r.grids 'tie1') -ceq '5,2') "tie1: $(Cell $r.grids 'tie1')"
    Check 'resolve tie 16:9: the higher id gets no seeded grid' ((Cell $r.grids 'tie2') -ceq 'none') "tie2: $(Cell $r.grids 'tie2')"
  }
  Case 'resolve seed: a zero-width screen has no shape: not named Portrait, no tall cell' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve zero width: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve zero width: scope, the default scene is read' ($null -ne $sc) 'no default scene'
    if ($null -eq $sc) { return }
    $k = Register-TileSetup $cfg @($Lap15, $ZeroW)
    Check 'resolve zero width: the zero-width screen is not named Portrait' ([string]$cfg.monitors.zerow.name -notlike 'Portrait*') "name: $([string]$cfg.monitors.zerow.name)"
    $r = Resolve-TileLayout $cfg $sc $k
    Check 'resolve zero width: the zero-width screen takes no tall cell' ((Cell $r.grids 'zerow') -ceq 'none') "zerow: $(Cell $r.grids 'zerow')"
  }
  Case 'resolve seed: a zero-height screen has no shape (control)' {
    $cfg = ConvertFrom-Json $v4Text
    $ok = IsV4 $cfg
    Check 'resolve zero height: scope, the config has the v4 monitors and setups objects' $ok 'no monitors or setups object: the v3 -> v4 shape is missing'
    if (-not $ok) { return }
    $sc = SceneOf $cfg 'default'
    Check 'resolve zero height: scope, the default scene is read' ($null -ne $sc) 'no default scene'
    if ($null -eq $sc) { return }
    $k = Register-TileSetup $cfg @($Lap15, $ZeroH)
    Check 'resolve zero height: the zero-height screen is not named Portrait or Ultrawide' ([string]$cfg.monitors.zeroh.name -notlike 'Portrait*' -and [string]$cfg.monitors.zeroh.name -notlike 'Ultrawide*') "name: $([string]$cfg.monitors.zeroh.name)"
    $r = Resolve-TileLayout $cfg $sc $k
    Check 'resolve zero height: the zero-height screen takes no grid' ((Cell $r.grids 'zeroh') -ceq 'none') "zeroh: $(Cell $r.grids 'zeroh')"
  }

  # ---- Get-TileLayoutEntry: one case per branch (no key, no layouts, no entry for the key, the entry) ----
  # Callers read the return as a property: its Name is the key and its Value is the layout (the engine reads $own.Value, the tray $own.Value.grids).
  Case 'layout entry: with no setup key there is no entry, though the scene has layouts' {
    $kA = [string](Get-TileSetupKey @($Laptop, $Ultra))
    $sc = [pscustomobject]@{ id = 'entry-nokey' }
    Set-Layout $sc $kA (New-Layout @{ laptop = (New-Grid 2 2) })
    foreach ($k in @('', $null)) {
      $got = Get-TileLayoutEntry $sc $k
      Check "layout entry: key '$k' gives no entry" ($null -eq $got) "got: $(if ($got) { $got.Name })"
    }
  }
  Case 'layout entry: a scene with no layouts object gives no entry for any key' {
    $kA = [string](Get-TileSetupKey @($Laptop, $Ultra))
    $sc = [pscustomobject]@{ id = 'entry-nolayouts'; grids = [pscustomobject]@{ laptop = (New-Grid 1 1) } }
    $got = Get-TileLayoutEntry $sc $kA
    Check 'layout entry: a scene with no layouts object gives no entry' ($null -eq $got) "got: $(if ($got) { $got.Name })"
  }
  Case 'layout entry: a key the scene has no entry for gives no entry, though other keys do' {
    $kA = [string](Get-TileSetupKey @($Laptop, $Ultra)); $kB = [string](Get-TileSetupKey @($Laptop, $Port)); $kC = [string](Get-TileSetupKey @($Laptop, $Uhd))
    $sc = [pscustomobject]@{ id = 'entry-miss' }
    Set-Layout $sc $kA (New-Layout @{ laptop = (New-Grid 2 2) })
    Set-Layout $sc $kB (New-Layout @{ laptop = (New-Grid 3 3) })
    $got = Get-TileLayoutEntry $sc $kC
    Check 'layout entry: a key with no entry in the scene gives no entry' ($null -eq $got) "got: $(if ($got) { $got.Name })"
  }
  Case 'layout entry: the key gives its own property, whose Value is that layout, whatever order the layouts were added in' {
    $kA = [string](Get-TileSetupKey @($Laptop, $Ultra)); $kB = [string](Get-TileSetupKey @($Laptop, $Port))
    foreach ($order in @(@($kA, $kB), @($kB, $kA))) {
      $sc = [pscustomobject]@{ id = 'entry-hit' }
      foreach ($k in $order) { $cell = if ($k -ceq $kA) { New-Grid 2 2 } else { New-Grid 5 5 }; Set-Layout $sc $k (New-Layout @{ laptop = $cell }) }
      $got = Get-TileLayoutEntry $sc $kB
      $label = (@($order | ForEach-Object { if ($_ -ceq $kA) { 'A' } else { 'B' } })) -join ','
      Check "layout entry: key B gives the property named B (added $label)" ($null -ne $got -and $got.Name -ceq $kB) "name: $(if ($got) { $got.Name })"
      Check "layout entry: its Value is B's layout, so its grids read B's cell (added $label)" ($null -ne $got -and (Cell $got.Value.grids 'laptop') -ceq '5,5') "cell: $(if ($got) { Cell $got.Value.grids 'laptop' })"
    }
  }

  # ---- Config lock: a wait that times out does not run the block unlocked ----
  # Use-TileLock waits 10 s for the lock. When another writer holds it that long, the block must not run, and the caller gets an error
  # to show. An abandoned lock (its holder died) is still taken and the block runs. The holder is a second powershell: the lock is a
  # mutex, and a mutex re-enters on the thread that owns it, so a hold from this thread would never time out. The holder takes the lock
  # through the product's own Use-TileLock. The two events are its signals: ready (it holds the lock) and release (let go).
  # The error's wording is the builder's choice: the case asserts a throw with a message, nothing more.
  # Get-LockName repeats the name Use-TileLock builds inline (as setup-plumbing.ps1 does for its lock case): a case that probes or keeps
  # a handle to the lock needs the name, and the product has no function that gives it. The scope checks below go red if the two drift.
  function Get-LockName([string]$dir) {
    $h12 = [BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($dir.ToLowerInvariant()))).Replace('-', '').Substring(0, 12)
    "Local\TileWindows-Write-$h12"
  }
  $holderScript = Join-Path $runDir 'lock-holder.ps1'
  [IO.File]::WriteAllText($holderScript, @'
param([string]$Config, [string]$ReadyName, [string]$ReleaseName)
$ErrorActionPreference = 'Stop'
. $Config
$ready = [Threading.EventWaitHandle]::OpenExisting($ReadyName)
$release = [Threading.EventWaitHandle]::OpenExisting($ReleaseName)
Use-TileLock { [void]$ready.Set(); [void]$release.WaitOne(120000) }
'@, $utf8)
  # Starts the holder with this process's environment (TILE_HOME is set), so it names the same lock. Its output is read only on failure.
  function Start-LockHolder([string]$readyName, [string]$releaseName) {
    $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass -File `"$holderScript`" -Config `"$(Join-Path $root 'config.ps1')`" -ReadyName `"$readyName`" -ReleaseName `"$releaseName`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    [Diagnostics.Process]::Start($psi)
  }
  # Lets the holder go and ends it if it overruns, so no later case starts with a held lock. The caps sit well above the 10 s wait.
  function Stop-LockHolder($proc, $releaseEvt) {
    if ($proc -and -not $proc.HasExited) { [void]$releaseEvt.Set(); if (-not $proc.WaitForExit(30000)) { $proc.Kill() } }
  }

  Case 'config lock held past the wait: the block does not run, and the caller gets an error' {
    $lockName = Get-LockName $TileHome; $tag = Split-Path $runDir -Leaf
    $readyEvt = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, "Local\tile-test-ready-$tag")
    $relEvt = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, "Local\tile-test-release-$tag")
    $holderProc = $null; $watch = $null
    try {
      $gotFree = Use-TileLock { 'ran' }
      Check 'config lock free: the block runs and its value comes back (control)' ($gotFree -ceq 'ran') "got: $gotFree"
      $holderProc = Start-LockHolder "Local\tile-test-ready-$tag" "Local\tile-test-release-$tag"
      $isHeld = $readyEvt.WaitOne(30000)
      Check 'config lock held: the holder has taken the lock (scope)' $isHeld "the holder never signalled ready; stderr: $(if ($holderProc.HasExited) { $holderProc.StandardError.ReadToEnd() } else { 'still running' })"
      if (-not $isHeld) { return }
      $watch = New-Object Threading.Mutex($false, $lockName)
      $took = $watch.WaitOne(0)
      if ($took) { $watch.ReleaseMutex() }
      Check 'config lock held: the lock reads as held from another process (scope)' (-not $took) 'the lock was free: the holder holds a different lock than Get-LockName'
      if ($took) { return }
      $probe = @{ ran = $false; held = $false }; $err = $null
      try { Use-TileLock { $probe.ran = $true; $probe.held = (-not $holderProc.HasExited) -and (-not $relEvt.WaitOne(0)) } } catch { $err = $_.Exception.Message }
      [void]$relEvt.Set(); [void]$holderProc.WaitForExit(30000)
      Check 'config lock held: the block does not run while the other writer still holds the lock' (-not $probe.held) 'the block ran unlocked while the other writer held the lock'
      Check 'config lock held: Use-TileLock throws instead of returning' ($null -ne $err) 'it returned with no error'
      if ($null -ne $err) { Check 'config lock held: the error has a message to show' (-not [string]::IsNullOrWhiteSpace($err)) 'the error message is blank' }
      $err2 = $null; $again = $null
      try { $again = Use-TileLock { 'again' } } catch { $err2 = $_.Exception.Message }
      Check 'config lock held: once the other writer lets go, the lock is taken and the block runs (control)' ($again -ceq 'again') "got: $again; error: $err2"
    } finally {
      Stop-LockHolder $holderProc $relEvt
      if ($holderProc) { $holderProc.Dispose() }
      if ($watch) { $watch.Dispose() }
      $readyEvt.Dispose(); $relEvt.Dispose()
    }
  }
  # The test opens a handle to the lock first and keeps it, so the lock still exists when the holder dies. With no other handle open,
  # the system would delete the lock with its last handle, and Use-TileLock would make a fresh one that is not abandoned.
  Case 'config lock abandoned by a writer that died: the lock is taken and the block runs' {
    $lockName = Get-LockName $TileHome; $tag = Split-Path $runDir -Leaf
    $readyEvt = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, "Local\tile-test-ready2-$tag")
    $relEvt = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, "Local\tile-test-release2-$tag")
    $keep = New-Object Threading.Mutex($false, $lockName)
    $holderProc = $null
    try {
      $holderProc = Start-LockHolder "Local\tile-test-ready2-$tag" "Local\tile-test-release2-$tag"
      $isHeld = $readyEvt.WaitOne(30000)
      Check 'config lock abandoned: the holder has taken the lock (scope)' $isHeld "the holder never signalled ready; stderr: $(if ($holderProc.HasExited) { $holderProc.StandardError.ReadToEnd() } else { 'still running' })"
      if (-not $isHeld) { return }
      $holderProc.Kill()
      $died = $holderProc.WaitForExit(30000)
      Check 'config lock abandoned: the holder died while it held the lock (scope)' $died 'the holder is still running after Kill'
      if (-not $died) { return }
      $probe = @{ ran = $false }; $err = $null; $got = $null
      try { $got = Use-TileLock { $probe.ran = $true; 'took' } } catch { $err = $_.Exception.Message }
      Check 'config lock abandoned: the block runs and its value comes back with no error (control)' ($probe.ran -and $got -ceq 'took' -and $null -eq $err) $(if ($null -ne $err) { "error: $err" } else { 'the block did not run' })
    } finally {
      Stop-LockHolder $holderProc $relEvt
      if ($holderProc) { $holderProc.Dispose() }
      $keep.Dispose(); $readyEvt.Dispose(); $relEvt.Dispose()
    }
  }

  # ---- Run folder sweep (a harness check, not a product claim) ----
  Case 'run folder: the sweep removes an old sibling run folder and keeps a new one' {
    $now = Get-Date
    $old = Join-Path $tempRoot ('1-{0}' -f [guid]::NewGuid().ToString('n'))
    $new = Join-Path $tempRoot ('2-{0}' -f [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $old | Out-Null; New-Item -ItemType Directory -Path $new | Out-Null
    (Get-Item -LiteralPath $old).LastWriteTime = $now.AddDays(-2)
    (Get-Item -LiteralPath $new).LastWriteTime = $now.AddHours(-1)
    try {
      Remove-OldRunFolders -Root $tempRoot -Own $runDir -Now $now
      Check 'sweep: a run folder over a day old is removed' (-not (Test-Path -LiteralPath $old)) 'the old sibling is still there'
      Check 'sweep: a newer run folder stays' (Test-Path -LiteralPath $new) 'the newer sibling was removed'
    } finally {
      Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $new -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  # The same caller with a locked old folder (a stray Edge holds CrashpadMetrics-active.pma): it must not throw, must keep that folder,
  # must remove the other old folder, keep the new one, and write one warning line naming the locked folder. The clock is fixed (P5).
  Case 'run folder: the sweep skips an old sibling run folder that another process holds open' {
    $lockNow = [datetime]::new(2001, 1, 1, 12, 0, 0)
    $lockRoot = Join-Path $runDir 'sweep-locked'; New-Item -ItemType Directory -Path $lockRoot | Out-Null
    $lockedRun = Join-Path $lockRoot ('4-{0}' -f [guid]::NewGuid().ToString('n'))
    $otherRun = Join-Path $lockRoot ('5-{0}' -f [guid]::NewGuid().ToString('n'))
    $freshRun = Join-Path $lockRoot ('6-{0}' -f [guid]::NewGuid().ToString('n'))
    foreach ($d in $lockedRun, $otherRun, $freshRun) { New-Item -ItemType Directory -Path $d | Out-Null }
    $lockHeld = $null
    try {
      $lockHeld = [IO.File]::Open((Join-Path $lockedRun 'CrashpadMetrics-active.pma'), [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
      [IO.File]::WriteAllText((Join-Path $otherRun 'a.txt'), 'x'); [IO.File]::WriteAllText((Join-Path $freshRun 'a.txt'), 'x')
      [IO.Directory]::SetLastWriteTime($lockedRun, $lockNow.AddDays(-3)); [IO.Directory]::SetLastWriteTime($otherRun, $lockNow.AddDays(-3))
      [IO.Directory]::SetLastWriteTime($freshRun, $lockNow.AddHours(-1))
      $refused = $false; try { [IO.File]::Delete((Join-Path $lockedRun 'CrashpadMetrics-active.pma')) } catch { $refused = $true }
      Check 'sweep, locked: a file held open refuses a delete (the fixture holds it)' $refused
      $threw = $null; $warn = @()
      try { $warn = @(Remove-OldRunFolders -Root $lockRoot -Own '' -Now $lockNow 3>&1 | Where-Object { $_ -is [Management.Automation.WarningRecord] }) } catch { $threw = $_.Exception.Message }
      Check 'sweep, locked: the sweep does not throw on a locked old run folder' ($null -eq $threw) "threw: $threw"
      Check 'sweep, locked: the locked old run folder stays' (Test-Path -LiteralPath $lockedRun) 'the locked folder was removed'
      Check 'sweep, locked: the other old run folder goes' (-not (Test-Path -LiteralPath $otherRun)) 'the other old folder is still there'
      Check 'sweep, locked: the new run folder stays' (Test-Path -LiteralPath $freshRun) 'the newer folder was removed'
      Check 'sweep, locked: one warning line names the skipped folder' ($warn.Count -eq 1 -and $warn[0].Message.Contains((Split-Path $lockedRun -Leaf))) "warnings: $($warn.Count)"
    } finally {
      if ($lockHeld) { $lockHeld.Dispose() }
      Remove-Item -LiteralPath $lockRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  # The caller's own run folder is kept even when it is over a day old: the sweep leaves $Own alone by path, not by age (P5: fixed clock).
  Case 'run folder: the sweep keeps its own run folder even when that folder is over a day old' {
    $ownNow = [datetime]::new(2001, 1, 1, 12, 0, 0)
    $ownRoot = Join-Path $runDir 'sweep-own'; New-Item -ItemType Directory -Path $ownRoot | Out-Null
    $ownOld = Join-Path $ownRoot ('7-{0}' -f [guid]::NewGuid().ToString('n'))
    $otherOld = Join-Path $ownRoot ('8-{0}' -f [guid]::NewGuid().ToString('n'))
    foreach ($d in $ownOld, $otherOld) { New-Item -ItemType Directory -Path $d | Out-Null }
    try {
      [IO.Directory]::SetLastWriteTime($ownOld, $ownNow.AddDays(-3)); [IO.Directory]::SetLastWriteTime($otherOld, $ownNow.AddDays(-3))
      Remove-OldRunFolders -Root $ownRoot -Own $ownOld -Now $ownNow
      Check 'sweep, own: the own run folder stays although it is over a day old' (Test-Path -LiteralPath $ownOld) 'the own folder was removed'
      Check 'sweep, own: another old run folder goes' (-not (Test-Path -LiteralPath $otherOld)) 'the other old folder is still there'
    } finally {
      Remove-Item -LiteralPath $ownRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
} finally {
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All setup-config checks passed.' }

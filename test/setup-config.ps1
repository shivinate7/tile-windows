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
function Remove-OldRunFolders([string]$Root, [string]$Own, [datetime]$Now) {
  foreach ($d in @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)) {
    if ($d.FullName -ne $Own -and $d.Name -match '^\d+-[0-9a-f]{32}$' -and ($Now - $d.LastWriteTime).TotalDays -gt 1) { Remove-Item -LiteralPath $d.FullName -Recurse -Force }
  }
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
$Uhd = New-Mon 'uhd' 'Panel D' 5360 0 3840 2160         # widest in pixels, but 16:9: no shape role

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
    $k = Register-TileSetup $cfg @($Uhd, $Ultra, $Port, $Laptop)
    $r = Resolve-TileLayout $cfg $sc $k
    Check 'resolve seed: the screen wider than 2:1 takes the wide cell, not the widest in pixels' ((Cell $r.grids 'ultra') -ceq '5,2') "ultra: $(Cell $r.grids 'ultra')"
    Check 'resolve seed: the portrait screen takes the tall cell' ((Cell $r.grids 'port') -ceq '1,2') "port: $(Cell $r.grids 'port')"
    Check 'resolve seed: the built-in screen takes the laptop cell' ((Cell $r.grids 'laptop') -ceq '1,1') "laptop: $(Cell $r.grids 'laptop')"
    Check 'resolve seed: the 16:9 screen, widest in pixels, takes no role cell' ((Cell $r.grids 'uhd') -ceq 'none') "uhd: $(Cell $r.grids 'uhd')"
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
} finally {
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All setup-config checks passed.' }

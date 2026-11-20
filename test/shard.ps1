# Shards for a test file whose cases run in one process (decision test-practices). The file dot-sources this, calls Shard-Init with its
# shard, the last case number of each shard but the last, and the file's gate total, and wraps each case in `if (Shard-Take) { ... }`.
# Shard-Take counts every call and returns true only for the shard's own range, so every shard counts the same cases, and test\run.ps1
# checks that the shards' runs add up to that count. Shard-Skip counts the gates still ahead as skipped, for a run that cannot reach the
# page (no Microsoft Edge). Shard-Report prints the count line. An `if` makes no scope, so a variable set in one case is still set in the
# next. With no shard arguments (-Of 1) every case runs in one process.
$script:shardNo = 1; $script:shardOf = 1; $script:shardLo = 1; $script:shardHi = [int]::MaxValue; $script:shardTotal = 0
$script:caseNo = 0; $script:caseRan = 0; $script:caseSkipped = 0; $script:skipWhy = ''
# $Ends: the last case number of each shard but the last, so there are $Of - 1 of them, in order. $Total: the file's gate count, pinned by
# the file. Shard-Report FAILs a run that reaches the end and counts another number, so a case added or dropped shows on the next full run.
function Shard-Init([int]$Shard, [int]$Of, [int[]]$Ends = @(), [int]$Total = 0) {
  if ($Of -lt 1 -or $Shard -lt 1 -or $Shard -gt $Of -or $Ends.Count -ne ($Of - 1)) { throw "shards: -Of is at least 1, -Shard is 1 to -Of, and there is one cut fewer than the shards (got $Shard of $Of, $($Ends.Count) cuts)" }
  if ($Total -lt 1) { throw "shards: -Total is the file's gate count, at least 1 (got $Total)" }
  $script:shardNo = $Shard; $script:shardOf = $Of; $script:shardTotal = $Total
  $script:shardLo = $(if ($Shard -eq 1) { 1 } else { $Ends[$Shard - 2] + 1 })
  $script:shardHi = $(if ($Shard -ge $Of) { [int]::MaxValue } else { $Ends[$Shard - 1] })
}
# One case: counts it, and returns true when this shard runs it.
function Shard-Take {
  $script:caseNo++
  if ($script:caseNo -lt $script:shardLo -or $script:caseNo -gt $script:shardHi) { return $false }
  $script:caseRan++
  $true
}
# The run cannot reach the gates still ahead (for example, no Microsoft Edge). Each one in this shard's range is counted as skipped, and
# the count runs to the pinned total, so the shards' ran and skipped counts still add up to the file's total.
function Shard-Skip([string]$why) {
  $from = [Math]::Max($script:shardLo, $script:caseNo + 1); $to = [Math]::Min($script:shardHi, $script:shardTotal)
  $script:caseSkipped += [Math]::Max(0, $to - $from + 1)
  $script:caseNo = $script:shardTotal; $script:skipWhy = $why
}
# The count line test\run.ps1 reads: ran R of T, skipped S. A count that is not the pinned total FAILs, and so does a shard that has cases
# but ran none and skipped none.
function Shard-Report([string]$file) {
  if ($script:caseNo -ne $script:shardTotal) { $script:fail++; "FAIL  $file counted $($script:caseNo) gates, but the file pins $($script:shardTotal): set the pin in $file to the count" }
  if ($script:caseNo -gt 0 -and ($script:caseRan + $script:caseSkipped) -eq 0) { $script:fail++; "FAIL  $file shard $($script:shardNo) of $($script:shardOf) ran no cases" }
  $why = if ($script:skipWhy) { ": $($script:skipWhy)" } else { '' }
  "cases shard $($script:shardNo) of $($script:shardOf) ran $($script:caseRan) of $($script:caseNo), skipped $($script:caseSkipped)$why"
}

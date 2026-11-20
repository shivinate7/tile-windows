# Shards for a test file whose cases run in one process (decision test-practices). The file dot-sources this, calls Shard-Init with its
# shard and the last case number of each shard but the last, and wraps each case in `if (Shard-Take) { ... }`. Shard-Take counts every
# call and returns true only for the shard's own range, so every shard counts the same cases, and test\run.ps1 checks that the shards'
# runs add up to that count. Shard-Report prints the count line. An `if` makes no scope, so a variable set in one case is still set in
# the next. With no shard arguments (-Of 1) every case runs in one process.
$script:shardNo = 1; $script:shardOf = 1; $script:shardLo = 1; $script:shardHi = [int]::MaxValue
$script:caseNo = 0; $script:caseRan = 0
# $Ends: the last case number of each shard but the last, so there are $Of - 1 of them, in order.
function Shard-Init([int]$Shard, [int]$Of, [int[]]$Ends = @()) {
  if ($Of -lt 1 -or $Shard -lt 1 -or $Shard -gt $Of -or $Ends.Count -ne ($Of - 1)) { throw "shards: -Of is at least 1, -Shard is 1 to -Of, and there is one cut fewer than the shards (got $Shard of $Of, $($Ends.Count) cuts)" }
  $script:shardNo = $Shard; $script:shardOf = $Of
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
# The count line test\run.ps1 reads. A shard that ran no case FAILs when the file has cases.
function Shard-Report([string]$file) {
  if ($script:caseNo -gt 0 -and $script:caseRan -eq 0) { $script:fail++; "FAIL  $file shard $($script:shardNo) of $($script:shardOf) ran no cases" }
  "cases shard $($script:shardNo) of $($script:shardOf) ran $($script:caseRan) of $($script:caseNo)"
}

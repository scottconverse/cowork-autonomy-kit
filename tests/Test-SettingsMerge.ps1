$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Import-ProductionFunctions.ps1')
$kit=Split-Path $PSScriptRoot -Parent
Import-ConfigurationFunctions $kit
$passed=0
$s=@'
{"custom":"keep","permissions":{"defaultMode":"default","deny":["Read(secret)"],"ask":["Bash(git push *)"],"allow":["Read"]},"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"powershell notify-turn-ended.ps1"},{"type":"command","command":"foreign-hook"}]},{"hooks":[{"type":"command","command":"duplicate-notify-turn-ended.ps1"}]}]}}
'@ | ConvertFrom-Json
$s=Merge-KitSettings -Settings $s -ClaudeRoot 'C:\dev\Test Profile'
$s=Merge-KitSettings -Settings $s -ClaudeRoot 'C:\dev\Test Profile'
$hooks=@($s.hooks.Stop | ForEach-Object { $_.hooks })
$notify=@($hooks | Where-Object { $_.command -like '*notify-turn-ended*' })
Assert-Kit ($notify.Count -eq 1) 'real dedupe leaves exactly one notify hook after two runs'
Assert-Kit ($notify[0].shell -eq 'powershell') 'legacy hook upgraded to explicit PowerShell'
Assert-Kit (@($s.hooks.Stop | Where-Object { $_.PSObject.Properties.Name -contains 'matcher' }).Count -eq 0) 'Stop notify has no matcher'
Assert-Kit (@($hooks | Where-Object command -eq 'foreign-hook').Count -eq 1) 'mixed foreign hook retained'
Assert-Kit ($s.custom -eq 'keep' -and $s.permissions.deny[0] -eq 'Read(secret)' -and $s.permissions.ask.Count -eq 1 -and $s.permissions.allow[0] -eq 'Read') 'unrelated settings and permission rules preserved'
Assert-Kit ($s.permissions.defaultMode -eq 'bypassPermissions') 'default remains bypass'
$skip=Merge-KitSettings -Settings ([pscustomobject]@{permissions=[pscustomobject]@{defaultMode='default'}}) -ClaudeRoot 'C:\dev' -SkipBypass
Assert-Kit ($skip.permissions.defaultMode -eq 'default') 'SkipBypass preserves mode'
$empty=Merge-KitSettings -Settings ([pscustomobject]@{}) -ClaudeRoot 'C:\dev' -SkipBypass
Assert-Kit (-not ($empty.permissions.PSObject.Properties.Name -contains 'defaultMode')) 'SkipBypass does not create default'
Assert-Kit ($empty.permissions.ask.Count -eq 0 -and $empty.permissions.deny.Count -eq 0) 'missing rule lists initialize empty'
Write-Host "SUMMARY: $passed PASS / 0 FAIL"

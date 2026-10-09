function Import-ProductionFunctions {
    param([string]$Path,[string[]]$Names)
    $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$null,[ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    foreach ($name in $Names) {
        $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}.GetNewClosure(),$true)
        if (-not $node) { throw "Missing production function: $name" }
        Set-Item -Path "function:script:$name" -Value ([scriptblock]::Create($node.Body.Extent.Text.Substring(1,$node.Body.Extent.Text.Length-2)))
    }
}
function Import-ConfigurationFunctions {
    param([string]$Kit)
    Import-ProductionFunctions (Join-Path $Kit 'Setup-Autonomy.ps1') @('Read-KitSettings','New-PreKitSnapshot','Install-LiveOrLeave','Merge-KitSettings','Install-KitConfiguration')
    Import-ProductionFunctions (Join-Path $Kit 'Uninstall-Autonomy.ps1') @('Remove-IfMatchesStage','Restore-PreKitFile','Remove-KitSettings','Uninstall-KitConfiguration')
}
function Assert-Kit {
    param($Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passed++
}
function Remove-TestRoot {
    param([string]$Path)
    $resolved=[IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test root' }
    if (Test-Path -LiteralPath $resolved) { [IO.Directory]::Delete($resolved,$true) }
}

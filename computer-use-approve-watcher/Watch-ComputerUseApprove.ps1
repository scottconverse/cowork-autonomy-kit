# Watch-ComputerUseApprove.ps1
# Background watcher that auto-clicks the Claude computer-use / browser / webfetch
# "Approve" dialog via Windows UI Automation. Part of claude-cowork-autonomy-kit.

param(
    [string]   $TargetLabel  = 'Approve',
    [string[]] $TargetProcs  = @('Claude','claude'),
    [int]      $PollMs       = 500,
    [int]      $DebounceMs   = 800
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$root       = [System.Windows.Automation.AutomationElement]::RootElement
$buttonCtrl = [System.Windows.Automation.ControlType]::Button
$nameProp   = [System.Windows.Automation.AutomationElement]::NameProperty
$ctrlProp   = [System.Windows.Automation.AutomationElement]::ControlTypeProperty
$invokePat  = [System.Windows.Automation.InvokePattern]::Pattern

Write-Host "Watching for '$TargetLabel' button (procs: $($TargetProcs -join ',')). Ctrl+C to stop."

# ponytail: 500ms tree-walk poll. Switch to UIA AddAutomationEventHandler (event-driven,
# no polling) if CPU becomes a concern under heavy Claude driving. The polling version
# is simpler and has measured-negligible idle cost; upgrade only when needed.
while ($true) {
    $cond = New-Object System.Windows.Automation.AndCondition `
        ((New-Object System.Windows.Automation.PropertyCondition $ctrlProp, $buttonCtrl), `
         (New-Object System.Windows.Automation.PropertyCondition $nameProp, $TargetLabel))
    try {
        $btns = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    } catch {
        Start-Sleep -Milliseconds $PollMs; continue
    }

    foreach ($btn in $btns) {
        try {
            if ($TargetProcs.Count -gt 0) {
                $procName = (Get-Process -Id $btn.Current.ProcessId -ErrorAction Stop).ProcessName
                if ($TargetProcs -notcontains $procName) { continue }
            }
            $btn.GetCurrentPattern($invokePat).Invoke()
            Write-Host ("[{0}] clicked '{1}' in PID {2}" -f (Get-Date -Format HH:mm:ss), $TargetLabel, $btn.Current.ProcessId)
            Start-Sleep -Milliseconds $DebounceMs
        } catch {
            # element vanished mid-click or process gone; ignore and re-scan
        }
    }
    Start-Sleep -Milliseconds $PollMs
}

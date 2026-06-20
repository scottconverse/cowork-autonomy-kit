# Optional desktop notification when a Claude Code turn ends.
# Parity with the Codex `notify ... turn-ended` hook. Wire it up via hooks.example.json.
param([string]$Message = "Claude Code: turn ended")

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $n = New-Object System.Windows.Forms.NotifyIcon
    $n.Icon = [System.Drawing.SystemIcons]::Information
    $n.BalloonTipTitle = "Claude Code"
    $n.BalloonTipText = $Message
    $n.Visible = $true
    $n.ShowBalloonTip(4000)
    Start-Sleep -Milliseconds 4500
    $n.Dispose()
} catch {
    # Fallback if the toast API is unavailable in this session.
    try { [console]::Beep(800, 200) } catch {}
}

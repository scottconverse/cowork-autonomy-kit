$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Windows-path self-test is not elevated.' }
@{ is_admin = $isAdmin; script_path = $PSCommandPath } | ConvertTo-Json -Compress

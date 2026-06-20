@echo off
setlocal
set "SCRIPT=%~dp0Install-ClaudeElevatedDevHelper.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoExit','-NoProfile','-ExecutionPolicy','Bypass','-File','%SCRIPT%')"
endlocal

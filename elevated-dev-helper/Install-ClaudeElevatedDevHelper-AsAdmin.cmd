@echo off
setlocal
set "SCRIPT=%~dp0Install-ClaudeElevatedDevHelper.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','\"%SCRIPT%\"'); exit $p.ExitCode"
set "INSTALL_EXIT=%ERRORLEVEL%"
endlocal & exit /b %INSTALL_EXIT%

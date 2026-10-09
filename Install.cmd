@echo off
REM Double-click entry point for the Claude Code Windows Autonomy Kit.
REM Forwards to Setup-Autonomy.ps1 with -ExecutionPolicy Bypass and pauses at end
REM so the console window stays open for the user to read the output.
REM
REM Triggers ONE Windows UAC prompt (for the elevated-dev-helper install in
REM helper phase). Everything else is user-scope, no admin.
REM
REM Pass through any args: e.g. double-click runs default, or from a terminal:
REM     Install.cmd -SkipBrowsers
REM     Install.cmd -SkipHelper

setlocal
set "PS1=%~dp0Setup-Autonomy.ps1"
if not exist "%PS1%" (
    echo ERROR: Setup-Autonomy.ps1 not found next to Install.cmd
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "EXIT=%ERRORLEVEL%"

echo.
echo ====================================================================
echo Setup finished with exit code %EXIT%.
echo Fully quit Claude (right-click the Claude icon in the system tray, Quit), then open it again. A new session alone does not load new PATH entries; the desktop app does not read PowerShell profiles.
echo ====================================================================
pause
endlocal & exit /b %EXIT%

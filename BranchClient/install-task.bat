@echo off
rem Creates the "Biometrics Sync" scheduled task. Options: see install-task.ps1 (e.g. -Time 02:30, -Daily, -Remove).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-task.ps1" %*
set RC=%ERRORLEVEL%
pause
exit /b %RC%

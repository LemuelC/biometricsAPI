@echo off
rem Sync this branch's employees to the central biometricsAPI.
rem   sync-employees.bat            send changed rows
rem   sync-employees.bat -Full      send every row
rem   sync-employees.bat -Test      check API URL + key
rem   sync-employees.bat -SaveKey   store the API key encrypted (run once, as the scheduled-task user)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync-employees.ps1" %*
exit /b %ERRORLEVEL%

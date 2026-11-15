@echo off
rem Kept for existing scheduled tasks: syncs only m_employee. Use sync.bat to sync every table.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync.ps1" -Table m_employee %*
exit /b %ERRORLEVEL%

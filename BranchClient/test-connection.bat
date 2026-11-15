@echo off
rem Checks the connection from this branch PC to the central biometricsAPI (read-only, sends no data).
rem   test-connection.bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-connection.ps1" %*
set RC=%ERRORLEVEL%
echo.
pause
exit /b %RC%

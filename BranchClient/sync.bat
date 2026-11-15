@echo off
rem Sync this branch's tables to the central biometricsAPI (tables listed in tables.ps1).
rem   sync.bat                        send changed rows of every table
rem   sync.bat -Table m_employee      only that table
rem   sync.bat -Full                  send every row
rem   sync.bat -Test                  check API URL + key
rem   sync.bat -SaveKey               store the API key encrypted (run once, as the scheduled-task user)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync.ps1" %*
exit /b %ERRORLEVEL%

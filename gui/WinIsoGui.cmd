@echo off
chcp 65001 >nul
setlocal
set "HERE=%~dp0"
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%WinIsoGui.ps1" %*
if errorlevel 1 pause
endlocal

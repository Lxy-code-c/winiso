@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
title winiso - Windows ISO Builder
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0winiso.ps1" %*
set RC=%errorlevel%
if not "%RC%"=="0" (
  echo.
  echo [winiso] exit code %RC%
  pause
)
endlocal

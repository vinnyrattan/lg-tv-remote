@echo off
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required. Install it with:
  echo winget install --id Microsoft.PowerShell --source winget
  pause
  exit /b 1
)
pwsh.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0LG-TV-Remote.ps1"
if errorlevel 1 pause

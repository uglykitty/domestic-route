@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%domestic-route.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process PowerShell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%PS_SCRIPT%""'"

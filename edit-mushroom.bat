@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0toolsun.ps1" -Game mushroom -Mode edit
if errorlevel 1 pause

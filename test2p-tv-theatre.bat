@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0toolsun.ps1" -Game tv-theatre -Mode test2p
if errorlevel 1 pause

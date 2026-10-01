@echo off
cd /d "%~dp0"
title vibes-game
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\launcher.ps1" %*
if errorlevel 1 (
  echo.
  echo Something went wrong. The message above says what.
  pause
)

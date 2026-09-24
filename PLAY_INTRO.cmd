@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\powershell\START_LOCAL_GAME.ps1" -Intro
if errorlevel 1 pause

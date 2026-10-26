@echo off
cd /d "%~dp0release"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Start-SonyClient.ps1" -Engine V2 -Model "WH-CH520" -Daemon

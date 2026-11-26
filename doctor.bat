@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\gb.ps1" doctor > "%~dp0doctor-result.txt" 2>&1
type "%~dp0doctor-result.txt"
echo.
echo Saved: doctor-result.txt
pause

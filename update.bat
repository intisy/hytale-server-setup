@echo off
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0start.ps1' -ForceServerUpdate"
PAUSE
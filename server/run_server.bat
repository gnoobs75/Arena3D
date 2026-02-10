@echo off
echo === Arena Relay Server ===
echo Starting relay server on port 8765...
echo.

REM Try common Godot locations
if exist "C:\Godot\Godot_v4.5.1-stable_mono_win64_console.exe" (
    "C:\Godot\Godot_v4.5.1-stable_mono_win64_console.exe" --headless --path "%~dp0.." "res://server/relay_server.tscn"
    goto :eof
)

if exist "C:\Godot\Godot_v4.5-stable_win64_console.exe" (
    "C:\Godot\Godot_v4.5-stable_win64_console.exe" --headless --path "%~dp0.." "res://server/relay_server.tscn"
    goto :eof
)

REM Try godot in PATH
where godot >nul 2>nul
if %ERRORLEVEL% equ 0 (
    godot --headless --path "%~dp0.." "res://server/relay_server.tscn"
    goto :eof
)

echo ERROR: Godot not found. Please set the path in this script.
echo Expected locations:
echo   C:\Godot\Godot_v4.5.1-stable_mono_win64_console.exe
echo   godot (in PATH)
pause

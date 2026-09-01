@echo off
REM SPLAT TRAILER LAB — Godot native (not HTML)

set GODOT=C:\Users\cleve\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe
set PROJECT=%~dp0..

if not exist "%GODOT%" (
    echo ERROR: Godot not found at %GODOT%
    pause
    exit /b 1
)

echo.
echo  SPLAT TRAILER LAB  [Godot]
echo  ─────────────────────────
echo  Type words  -  SPLAT  -  BOOM
echo  SIZE / COUNT sliders
echo  Shapes: DOT DIAMOND SQUARE STREAK CROSS RING
echo  Entrances: SWEEP EXPLODE RAIN SCAN SPIRAL IMPLODE
echo  Keys: Enter=SPLAT  Space=blast  Shift+Space=BOOM
echo         1-6 shapes  Left/Right looks  X=PNG  ESC=quit
echo.

"%GODOT%" --path "%PROJECT%" res://scenes/splat_viewer.tscn

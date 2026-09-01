@echo off
REM Silicon Arena — tell me what's wrong before I launch.
cd /d "%~dp0\.."
set GODOT=
if defined GODOT_BIN if exist "%GODOT_BIN%" set GODOT=%GODOT_BIN%
if not defined GODOT for %%G in (godot.exe Godot_v4.6-stable_win64.exe) do (
  if not defined GODOT for /f "delims=" %%P in ('where %%G 2^>nul') do set GODOT=%%P
)
if not defined GODOT if exist "%USERPROFILE%\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe" set GODOT=%USERPROFILE%\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe
if not defined GODOT (
  echo Godot not found. Set GODOT_BIN or put godot on PATH.
  exit /b 2
)
"%GODOT%" --headless --path . --script tools/doctor.gd

@echo off
setlocal enabledelayedexpansion
REM Silicon Arena — one verification command.
REM
REM   tools\verify.cmd
REM
REM Exits 0 when everything deterministic passes, non-zero otherwise.
REM Does NOT require LM Studio: everything here is deterministic and offline.

cd /d "%~dp0\.."
set FAILED=0
set GODOT=

echo.
echo === SILICON ARENA VERIFY ===
echo.

REM ---- locate Godot -------------------------------------------------------
if defined GODOT_BIN if exist "%GODOT_BIN%" set GODOT=%GODOT_BIN%
if not defined GODOT for %%G in (godot.exe Godot_v4.6-stable_win64.exe) do (
  if not defined GODOT for /f "delims=" %%P in ('where %%G 2^>nul') do set GODOT=%%P
)
if not defined GODOT (
  for %%P in (
    "%USERPROFILE%\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe"
    "%USERPROFILE%\Downloads\Godot_v4.6-stable_win64.exe"
  ) do if not defined GODOT if exist %%P set GODOT=%%~P
)
if not defined GODOT (
  echo [FAIL] Godot not found.
  echo        Set GODOT_BIN to your Godot 4.6 executable, or put it on PATH.
  exit /b 2
)
echo [PASS] godot found: %GODOT%

REM ---- import (builds the global class cache) ------------------------------
if not exist ".godot\global_script_class_cache.cfg" (
  echo [....] first run: importing project ^(builds the class registry^)
  "%GODOT%" --headless --editor --quit --path . >nul 2>&1
)
if exist ".godot\global_script_class_cache.cfg" (
  echo [PASS] project import
) else (
  echo [FAIL] project import - no global_script_class_cache.cfg
  set FAILED=1
)

REM ---- project parses ------------------------------------------------------
"%GODOT%" --headless --path . --quit >"%TEMP%\sa_parse.txt" 2>&1
findstr /C:"Parse Error" "%TEMP%\sa_parse.txt" >nul
if errorlevel 1 (
  echo [PASS] project parses
) else (
  echo [FAIL] project parses - Parse Error present:
  findstr /C:"Parse Error" "%TEMP%\sa_parse.txt"
  set FAILED=1
)

REM ---- deterministic self-tests -------------------------------------------
call :run_selftest entrypoint_parity_selftest "entrypoint parity"
call :run_selftest model_policy_selftest      "model policy"
call :run_selftest coherence_selftest         "coherence"
call :run_selftest cinematic_selftest         "cinematic bridge"
call :run_selftest scar_lattice_selftest      "scar lattice"

REM ---- JSON + preset legality ---------------------------------------------
"%GODOT%" --headless --path . --script tools/verify_configs.gd >"%TEMP%\sa_cfg.txt" 2>&1
findstr /C:"CONFIGS OK" "%TEMP%\sa_cfg.txt" >nul
if errorlevel 1 (
  echo [FAIL] config/preset validation
  findstr /C:"  " "%TEMP%\sa_cfg.txt"
  set FAILED=1
) else (
  echo [PASS] required files, configs and presets
)

echo.
if "%FAILED%"=="0" (
  echo VERIFY OK
  exit /b 0
) else (
  echo VERIFY FAILED
  exit /b 1
)

:run_selftest
"%GODOT%" --headless --path . --script scripts/arena/%~1.gd >"%TEMP%\sa_%~1.txt" 2>&1
findstr /R /C:"[1-9][0-9]* failure" "%TEMP%\sa_%~1.txt" >nul
if errorlevel 1 (
  findstr /C:"PARITY BROKEN" "%TEMP%\sa_%~1.txt" >nul
  if errorlevel 1 (
    echo [PASS] %~2
  ) else (
    echo [FAIL] %~2
    set FAILED=1
  )
) else (
  echo [FAIL] %~2
  findstr /R /C:"FAIL" "%TEMP%\sa_%~1.txt"
  set FAILED=1
)
exit /b 0

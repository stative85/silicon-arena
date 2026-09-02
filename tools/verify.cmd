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
REM Each check demands POSITIVE evidence: a success token the test only prints
REM when it actually ran. Passing on the mere ABSENCE of the word "failure"
REM would let a test that printed nothing at all report green.
REM   arg1 = script path, arg2 = label, arg3 = required success token
call :check "scripts/arena/entrypoint_parity_selftest.gd" "entrypoint parity"   "PARITY OK"
call :check "scripts/arena/model_policy_selftest.gd"      "model policy"        "0 failure"
call :check "scripts/arena/coherence_selftest.gd"         "coherence"           "RESULT: SEPARATED"
call :check "scripts/arena/cinematic_selftest.gd"         "cinematic bridge"    "0 failure"
call :check "scripts/arena/scar_lattice_selftest.gd"      "scar lattice"        "0 failure"
call :check "scripts/arena/compat_selftest.gd"            "system-role compat"  "0 failure"
call :check "scripts/arena/turn_order_selftest.gd"        "turn order / swaps"  "TURN ORDER OK"
call :check "scripts/arena/vram_selftest.gd"              "vram estimate"       "VRAM OK"
call :check "scripts/arena/speech_clean_selftest.gd"      "speech cleaning"     "SPEECH CLEAN OK"
call :check "scripts/arena/targeting_selftest.gd"         "claim provenance"    "TARGETING OK"
call :check "scripts/arena/dispute_selftest.gd"           "dispute episode"     "DISPUTE OK"
call :check "scripts/arena/contention_selftest.gd"        "contention bounds"   "CONTENTION OK"
call :check "scripts/arena/presentation_selftest.gd"      "presentation rhythm" "PRESENTATION OK"
call :check "tools/adversarial.gd"                        "adversarial pass"    "ADVERSARIAL OK"
call :check "tools/offline_selftest.gd"                   "offline behaviour"   "OFFLINE OK"

REM ---- documentation and workflow linting ---------------------------------
call :pycheck "tools/lint_docs.py"       "documentation lint"
call :pycheck "tools/lint_workflows.py"  "workflow lint"
call :pycheck "tools/lint_private_paths.py" "private path lint"
call :pycheck "tools/lint_templates.py"     "template coverage"
call :pycheck "tools/lint_exits.py"       "silent failure exits"

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

:check
REM %~1 script  %~2 label  %~3 required success token
set "OUT=%TEMP%\sa_check.txt"
"%GODOT%" --headless --path . --script %~1 >"%OUT%" 2>&1
findstr /C:"%~3" "%OUT%" >nul
if errorlevel 1 (
  echo [FAIL] %~2 - did not print "%~3"
  findstr /R /C:"FAIL" "%OUT%"
  set FAILED=1
  exit /b 0
)
findstr /R /C:"[1-9][0-9]* failure" "%OUT%" >nul
if not errorlevel 1 (
  echo [FAIL] %~2 - reported failures
  findstr /R /C:"FAIL" "%OUT%"
  set FAILED=1
  exit /b 0
)
echo [PASS] %~2
exit /b 0

:pycheck
REM %~1 python script  %~2 label
where python >nul 2>&1
if errorlevel 1 (
  echo [SKIP] %~2 - python not on PATH
  exit /b 0
)
python %~1 >"%TEMP%\sa_py.txt" 2>&1
if errorlevel 1 (
  echo [FAIL] %~2
  findstr /C:"FAIL" "%TEMP%\sa_py.txt"
  set FAILED=1
) else (
  echo [PASS] %~2
)
exit /b 0

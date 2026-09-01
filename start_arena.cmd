@echo off
setlocal

:: Get current directory (the silicon_arena folder)
set "PROJECT_DIR=%~dp0"
:: Trim trailing backslash
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

:: ── Find Godot 4.6 ──────────────────────────────────────
set "GODOT_EXE="

:: 1. Check if godot is on PATH
where godot >nul 2>&1
if %ERRORLEVEL%==0 (
  for /f "delims=" %%i in ('where godot') do set "GODOT_EXE=%%i"
  goto :found_godot
)

:: 2. Check project directory for Godot exe
for %%f in ("%PROJECT_DIR%\Godot_v4*.exe") do (
  if exist "%%f" (
    set "GODOT_EXE=%%f"
    goto :found_godot
  )
)

:: 3. Check Downloads folder
for /d %%d in ("%USERPROFILE%\Downloads\Godot_v4*") do (
  for %%f in ("%%d\Godot_v4*.exe") do (
    if exist "%%f" (
      set "GODOT_EXE=%%f"
      goto :found_godot
    )
  )
)

:: 4. Check common install locations
for %%p in (
  "%ProgramFiles%\Godot\Godot_v4*.exe"
  "%ProgramFiles(x86)%\Godot\Godot_v4*.exe"
  "%LOCALAPPDATA%\Godot\Godot_v4*.exe"
) do (
  for %%f in (%%p) do (
    if exist "%%f" (
      set "GODOT_EXE=%%f"
      goto :found_godot
    )
  )
)

:: Not found
echo.
echo  ERROR: Godot 4.6 executable not found.
echo.
echo  Silicon Arena needs Godot 4.6 to run. Options:
echo    1. Download from: https://godotengine.org/download/
echo    2. Place the Godot exe in this folder: %PROJECT_DIR%
echo    3. Add Godot to your system PATH
echo.
pause
exit /b 1

:found_godot
echo [Silicon Arena] Found Godot: %GODOT_EXE%

:: ── Check LM Studio API ─────────────────────────────────
:: Honour the same override every other tool uses, so the launcher cannot
:: report a different server than the arena actually talks to.
set "LM_URL=%SILICON_ARENA_LM_URL%"
if not defined LM_URL set "LM_URL=%LM_STUDIO_URL%"
if not defined LM_URL set "LM_URL=http://127.0.0.1:1234/v1"
echo [Silicon Arena] Checking LM Studio API (%LM_URL%)...
powershell -NoProfile -Command "$u='%LM_URL%'; if ($u -notmatch '^http') { $u = 'http://' + $u }; $u = $u.TrimEnd('/'); if ($u -notmatch '/v1$') { $u = $u + '/v1' }; try { $null = Invoke-RestMethod -Uri ($u + '/models') -Method Get -TimeoutSec 3; Write-Host '  LM Studio API OK' } catch { Write-Host ('  WARNING: LM Studio API not reachable at ' + $u); Write-Host '  Start LM Studio and load a model before launching.' }"

:: ── Launch ───────────────────────────────────────────────
echo.
echo [Silicon Arena] Launching...
"%GODOT_EXE%" --path "%PROJECT_DIR%"

echo.
echo Silicon Arena exited.
pause

endlocal

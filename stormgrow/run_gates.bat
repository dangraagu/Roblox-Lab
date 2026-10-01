@echo off
rem StormGrow: run every gate and keep the window open. Double-click, or run from a terminal.
rem Needs the luau CLI: set LUAU to its full path first, or have luau.exe on PATH.
rem Reads nothing secret and writes only robloxemu\build\stormgrow.luau (the headless bundle).
setlocal
if "%LUAU%"=="" set LUAU=luau
set GAME=%~dp0
set EMU=%~dp0..\robloxemu

echo == bundling the game for the headless checks
pushd "%EMU%"
py -3 wrap.py --game ..\stormgrow --out build\stormgrow.luau || goto :fail
popd

echo.
echo == unit specs (tests\*.spec.luau) and the walk
pushd "%GAME%"
for %%f in (tests\*.spec.luau tests\walk.luau) do (
  echo -- %%f
  "%LUAU%" %%f 2>&1 | findstr /R /C:"passed, [0-9]* failed" /C:"FAIL" /C:"error"
)
echo -- tests\project_check.py
py -3 tests\project_check.py
popd

echo.
echo == headless checks (robloxemu\check_stormgrow*.luau)
pushd "%EMU%"
for %%f in (check_stormgrow.luau check_stormgrow_compile.luau check_stormgrow_env.luau check_stormgrow_hazards.luau check_stormgrow_rest.luau check_stormgrow_hud.luau check_stormgrow_save.luau check_stormgrow_wire.luau check_stormgrow_board.luau check_stormgrow_firstmin.luau check_stormgrow_aim.luau check_stormgrow_slots.luau check_stormgrow_stream.luau) do (
  echo -- %%f
  "%LUAU%" %%f 2>&1 | findstr /R /C:"passed, [0-9]* failed" /C:"^PASS" /C:"^FAIL" /C:"error"
)
popd

echo.
echo Done. Every line above should end in ", 0 failed" or read "PASS".
pause
exit /b 0

:fail
echo Bundling failed.
pause
exit /b 1

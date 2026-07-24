@echo off
setlocal
REM ===================================================================
REM  Publiser Labyrint til det LIVE Roblox-spillet via Roblox Open Cloud.
REM  Dobbeltklikk denne (etter at endringene er "deploy-check green").
REM
REM  Engangs-oppsett (se DEPLOY.md):
REM   1) Fyll inn UNIVERSE_ID og PLACE_ID under (fra Creator Dashboard).
REM   2) Lag en Open Cloud API-nokkel med skrive-/publiser-tilgang til
REM      spillet, og lim den inn i  roblox_api_key.txt  (samme mappe).
REM      Den fila er git-ignorert og skal ALDRI committes.
REM ===================================================================

set "UNIVERSE_ID=SETT_INN_UNIVERSE_ID"
set "PLACE_ID=SETT_INN_PLACE_ID"

cd /d "%~dp0"
if not exist roblox_api_key.txt (
  echo [FEIL] Mangler roblox_api_key.txt i denne mappa. Se DEPLOY.md.
  pause & exit /b 1
)
set /p API_KEY=<roblox_api_key.txt

echo Bygger place-fil (rojo)...
rojo build -o Labyrint.rbxl
if errorlevel 1 ( echo [FEIL] rojo-bygg feilet. & pause & exit /b 1 )

echo Publiserer til Roblox (Open Cloud)...
curl -sS -X POST ^
 "https://apis.roblox.com/universes/v1/%UNIVERSE_ID%/places/%PLACE_ID%/versions?versionType=Published" ^
 -H "x-api-key: %API_KEY%" ^
 -H "Content-Type: application/octet-stream" ^
 --data-binary "@Labyrint.rbxl"
echo.
echo Ferdig. Ser du "versionNumber" i svaret over, er en ny versjon publisert LIVE.
echo (Spillere maa forlate og bli med paa nytt for aa faa den nye serveren.)
endlocal
pause

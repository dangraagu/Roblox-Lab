@echo off
setlocal
REM ===================================================================
REM  ENKEL publisering til det LIVE spillet — UTEN API-nokkel.
REM  Bruker Roblox-innloggingen din (rojo finner den fra maskinen).
REM  Krav: du er logget inn i Roblox Studio paa denne PCen.
REM
REM  Engangs-oppsett: sett PLACE_ID under = tallet i spillets URL
REM    roblox.com/games/<PLACE_ID>/...   (ikke hemmelig).
REM
REM  (Vil du ha den mer robuste maaten senere: se deploy_to_roblox.bat
REM   + DEPLOY.md for Open Cloud API-nokkel.)
REM ===================================================================

set "PLACE_ID=121268951050692"

cd /d "%~dp0"
if "%PLACE_ID%"=="SETT_INN_PLACE_ID" (
  echo [FEIL] Fyll inn PLACE_ID overst i denne .bat-fila forst.
  pause & exit /b 1
)

echo Bygger og publiserer Labyrint til place %PLACE_ID% ...
rojo upload --asset_id %PLACE_ID%
if errorlevel 1 (
  echo.
  echo [FEIL] Publisering feilet.
  echo  - Sjekk at du er logget inn i Roblox Studio, og at PLACE_ID stemmer.
  echo  - Feiler innlogging fortsatt: bruk Studio ^(File -^> Publish^) eller
  echo    deploy_to_roblox.bat med API-nokkel ^(se DEPLOY.md^).
  pause & exit /b 1
)
echo.
echo Ferdig! Ny versjon er publisert LIVE.
echo Spillere maa forlate og bli med paa nytt for aa faa den.
endlocal
pause

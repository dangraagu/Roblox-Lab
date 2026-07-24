# Slik oppdaterer du det LIVE spillet

**Viktig:** å pushe til GitHub oppdaterer **IKKE** det live Roblox-spillet. Roblox
kjører alltid den siste **publiserte** versjonen. Du må publisere når du vil at
endringer skal bli synlige for spillere.

Du har to måter:

## A) Raskt / manuelt (Roblox Studio)
1. Åpne `Labyrint.rbxlx` i Studio (eller `rojo serve` + koble til).
2. **File → Publish to Roblox** (ikke "As" — velg det eksisterende spillet så du
   overskriver den live plassen).
3. Spillere må forlate og bli med på nytt for å havne på den nye serveren.

## B) Ett klikk (anbefalt for jevnlige oppdateringer) — `deploy_to_roblox.bat`
Bygger og publiserer via Roblox **Open Cloud**. Kjør den når endringene er
"deploy-check green".

**Engangs-oppsett:**
1. Finn IDene: create.roblox.com → velg spillet.
   - **Universe ID**: på spillets side (Creator Dashboard) / URL.
   - **Place ID**: åpne "start place" → tallet i URL-en.
   - Skriv dem inn i `deploy_to_roblox.bat` (`UNIVERSE_ID`, `PLACE_ID`).
2. Lag en **Open Cloud API-nøkkel**: create.roblox.com → **Open Cloud → API Keys
   → Create API Key**. Gi den tilgang til å **publisere place** for spillet ditt
   (Place Management / "write"/"publish" for din experience). Kopier nøkkelen.
3. Lim nøkkelen inn i en fil `roblox_api_key.txt` i denne mappa (kun nøkkelen,
   én linje). **Denne fila er git-ignorert — ALDRI commit en API-nøkkel.**
4. Dobbeltklikk `deploy_to_roblox.bat`. Ser du `versionNumber` i svaret, er det
   publisert live.

Krever `rojo` (allerede installert via cargo) og `curl` (følger med Windows 10/11).

## Full-automatisk "publiser når grønt"
Kjeden er: gjør endring → `deploy-check` → hvis GRØNT → kjør `deploy_to_roblox.bat`.
Vil du ha det helt uten museklikk (f.eks. GitHub Actions som bygger + publiserer),
kan det settes opp senere — da må API-nøkkelen ligge som en hemmelig
repo-variabel, ikke i koden.

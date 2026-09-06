-- Pinner lys-presetene. Kjør: luau tests/lightingpresets.spec.luau
--
-- Poenget med fila: MAZE er ikke et designvalg, det er tilstanden den LIVE serveren har brukt
-- siden lobbyen ble sluppet. Da verdiene ble håndkopiert inn i to filer, drev kopien med én
-- gang — labyrinten fikk en Ambient live-spillet aldri hadde, og ble lysere. Disse testene er
-- der for at neste endring skal måtte være bevisst.
local P = require("../src/shared/LightingPresets")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function rgb(c, r, g, b, msg)
	eq(c[1], r, msg .. " (r)")
	eq(c[2], g, msg .. " (g)")
	eq(c[3], b, msg .. " (b)")
end

-- ── MAZE: nøyaktig det serveren satte før lyset ble flyttet til klienten ──────
-- Kilde: MazeGame.server.luau @4270c07, START-blokka under `if CONFIG.UseLobby then`:
--   Lighting.FogEnd = INSTANCE_FOG            -- 45
--   Lighting.ClockTime = 0
--   Lighting.Brightness = 1
--   Lighting.OutdoorAmbient = Color3.fromRGB(20, 20, 28)
--   Lighting.FogColor = Color3.fromRGB(8, 8, 12)
--   Lighting.FogStart = 0
-- Ambient ble ALDRI satt, så den sto på Roblox-standarden (0,0,0).
eq(P.MAZE.ClockTime, 0, "MAZE ClockTime er midnatt")
eq(P.MAZE.Brightness, 1, "MAZE Brightness er 1")
rgb(P.MAZE.Ambient, 0, 0, 0, "MAZE Ambient er svart som i live-spillet")
rgb(P.MAZE.OutdoorAmbient, 20, 20, 28, "MAZE OutdoorAmbient")
rgb(P.MAZE.FogColor, 8, 8, 12, "MAZE FogColor")
eq(P.MAZE.FogStart, 0, "MAZE FogStart er 0")
eq(P.MAZE.FogEnd, 45, "MAZE FogEnd er INSTANCE_FOG")

-- Atmosfæren kommer fra Fx.Presets.Maze og skal ikke tynnes ut i labyrinten.
eq(P.MAZE.AtmosphereDensity, 0.35, "MAZE beholder Fx-tettheten")
eq(P.MAZE.AtmosphereHaze, 1.4, "MAZE beholder Fx-disen")

-- ── Lobbyen skal faktisk være lys ────────────────────────────────────────────
-- Regresjonen som startet alt: huben kjørte labyrintens mørke, og en spiller beskrev spillet
-- som "a black part that is scaled in the shape of a square".
truthy(P.LOBBY.Brightness > P.MAZE.Brightness, "lobbyen er lysere enn labyrinten")
truthy(P.LOBBY.FogEnd > P.MAZE.FogEnd * 4, "lobbyen ser langt nok til å se huben")
truthy(P.LOBBY.FogStart > 0, "lobbyen har ikke tåke som starter i ansiktet")
truthy(P.LOBBY.ClockTime > 6 and P.LOBBY.ClockTime < 18, "lobbyen står på dagtid")
truthy(P.LOBBY.Ambient[1] > 50, "lobbyen har ekte fyllys")
truthy(P.LOBBY.AtmosphereDensity < P.MAZE.AtmosphereDensity, "lobbyen er mindre disig")

-- ── Begge presetene må dekke NØYAKTIG samme felter ───────────────────────────
-- Et felt som bare finnes i det ene blir hengende igjen fra forrige tilstand: går du fra en
-- lobby med Ambient (96,100,118) inn i et MAZE-preset uten Ambient, tar du fyllyset med deg
-- inn i labyrinten. Det var akkurat den klassen feil som slapp gjennom første gang.
for key in P.LOBBY do
	truthy(P.MAZE[key] ~= nil, "MAZE mangler feltet " .. key)
end
for key in P.MAZE do
	truthy(P.LOBBY[key] ~= nil, "LOBBY mangler feltet " .. key)
end

-- ── Darkness=false skal gi et spillbart, opplyst spill ───────────────────────
-- Serveren deler ikke ut fakler når flagget er av, så klienten må ikke svarte ut verden.
truthy(P.LIT.Brightness > P.MAZE.Brightness, "LIT er lysere enn labyrinten")
truthy(P.LIT.FogEnd > P.MAZE.FogEnd, "LIT ser lenger enn labyrinten")

print(string.format("lightingpresets: %d passed, %d failed", passed, failed))
if failed > 0 then error("lightingpresets tests failed") end

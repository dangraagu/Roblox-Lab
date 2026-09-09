-- Rene tester for MazeRef. Kjør: luau tests/mazeref.spec.luau
--
-- Bakgrunnen: tema-butikken og minikartet var DØDE i live-spillet. Begge lette etter
-- `workspace.MazeGame`, men live-byggeren (`buildInstance`) navngir mappa `Maze_<id>` — bare den
-- ubrukte `buildLevel` lager noen gang en `MazeGame`. Resultat: 17 vegg-temaer til 500-2000
-- mynter og en minikart-perk til 800 mynter gjorde ingenting.
--
-- Navnet kan ikke bare byttes ut. Med per-spiller-instanser står det MANGE `Maze_<id>`-mapper i
-- workspace samtidig, én pr aktiv spiller, så en klient som tar den første ville farget om — eller
-- tegnet kart over — en ANNEN spillers labyrint. Derfor merker serveren spilleren med sin egen
-- mappe, og disse testene låser oppslaget.
local MazeRef = require("../src/shared/MazeRef")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL:", msg) end end

-- Minimale stand-inn for Roblox-objekter. MazeRef rører ingen Roblox-API selv — den tar
-- workspace og spilleren inn som argumenter, nettopp for at den skal kunne testes her.
local function fakeFolder(name)
	local f = { Name = name, children = {} }
	function f.IsDescendantOf(self, other)
		local p = self.Parent
		while p do
			if p == other then return true end
			p = p.Parent
		end
		return false
	end
	return f
end

local function fakeWorkspace(folders)
	local ws = { children = folders }
	function ws.FindFirstChild(self, name)
		for _, f in self.children do
			if f.Name == name then return f end
		end
		return nil
	end
	return ws
end

local function fakePlayer(attr)
	local p = { attrs = attr or {} }
	function p.GetAttribute(self, key) return self.attrs[key] end
	function p.SetAttribute(self, key, value) self.attrs[key] = value end
	return p
end

-- ── navnet på attributtet er en kontrakt mellom server og klient ─────────────
-- Serveren setter det, tre klientskript leser det. Endres strengen ett sted uten de andre,
-- er temaene døde igjen — og det er nøyaktig feilen dette skal hindre.
eq(MazeRef.ATTRIBUTE, "MazeFolder", "attributtnavnet er MazeFolder")
eq(MazeRef.LEGACY_NAME, "MazeGame", "det gamle, delte navnet er MazeGame")

-- ── vanlig tilfelle: spilleren står i sin egen instans ───────────────────────
do
	local mine, theirs = fakeFolder("Maze_7"), fakeFolder("Maze_9")
	local ws = fakeWorkspace({ theirs, mine })
	local plr = fakePlayer({ MazeFolder = "Maze_7" })
	eq(MazeRef.folder(ws, plr), mine, "finner MIN mappe, ikke den første i workspace")
	truthy(MazeRef.matchesName(plr, "Maze_7"), "mitt eget mappenavn er mitt")
	falsy(MazeRef.matchesName(plr, "Maze_9"), "en annen spillers mappe er IKKE min")
end

-- ── flere instanser samtidig: ingen skal kunne treffe feil ──────────────────
do
	local a, b, c = fakeFolder("Maze_1"), fakeFolder("Maze_2"), fakeFolder("Maze_3")
	local ws = fakeWorkspace({ a, b, c })
	eq(MazeRef.folder(ws, fakePlayer({ MazeFolder = "Maze_1" })), a, "spiller 1 får Maze_1")
	eq(MazeRef.folder(ws, fakePlayer({ MazeFolder = "Maze_2" })), b, "spiller 2 får Maze_2")
	eq(MazeRef.folder(ws, fakePlayer({ MazeFolder = "Maze_3" })), c, "spiller 3 får Maze_3")
end

-- ── i lobbyen: ingen instans, ingenting å farge ─────────────────────────────
do
	local ws = fakeWorkspace({ fakeFolder("Maze_4") })
	eq(MazeRef.folder(ws, fakePlayer({})), nil, "uten attributt og uten MazeGame er svaret nil")
end

-- ── rollback-stien (CONFIG.UseLobby = false) bygger ÉN delt MazeGame ─────────
-- Den har ingen instanser og setter derfor aldri attributtet. Faller den ikke tilbake hit,
-- ville rollback-spaken slå av temaer og minikart i stedet for å gjenopprette dem.
do
	local shared = fakeFolder("MazeGame")
	local ws = fakeWorkspace({ shared })
	eq(MazeRef.folder(ws, fakePlayer({})), shared, "uten attributt brukes den delte MazeGame")
	truthy(MazeRef.matchesName(fakePlayer({}), "MazeGame"), "MazeGame er min når jeg ikke har instans")
end

-- ── attributtet peker på en mappe som er revet ──────────────────────────────
-- Instansen rives når siste deltaker forlater den, og attributtet kan henge igjen et øyeblikk.
do
	local ws = fakeWorkspace({})
	eq(MazeRef.folder(ws, fakePlayer({ MazeFolder = "Maze_7" })), nil, "borte mappe gir nil, ikke feil")
	local shared = fakeFolder("MazeGame")
	eq(MazeRef.folder(fakeWorkspace({ shared }), fakePlayer({ MazeFolder = "Maze_7" })), shared,
		"borte instans faller tilbake til MazeGame hvis den finnes")
end

-- ── skitne verdier skal ikke velte klienten ─────────────────────────────────
do
	local ws = fakeWorkspace({ fakeFolder("MazeGame") })
	for _, bad in { "", 42, true, {} } do
		local plr = fakePlayer({ MazeFolder = bad })
		eq(MazeRef.folder(ws, plr).Name, "MazeGame", "ugyldig attributt (" .. typeof(bad) .. ") faller tilbake")
		falsy(MazeRef.matchesName(plr, "Maze_1"), "ugyldig attributt eier ingen instans-mappe")
	end
end

-- ── isMine: er denne delen inne i MIN labyrint? ─────────────────────────────
-- Brukes av DescendantAdded, som ellers ville malt deler i naboens labyrint.
do
	local mine, theirs = fakeFolder("Maze_7"), fakeFolder("Maze_9")
	local ws = fakeWorkspace({ mine, theirs })
	local plr = fakePlayer({ MazeFolder = "Maze_7" })
	local myWall = fakeFolder("Wall"); myWall.Parent = mine
	local theirWall = fakeFolder("Wall"); theirWall.Parent = theirs
	truthy(MazeRef.isMine(ws, plr, myWall), "vegg i min mappe er min")
	falsy(MazeRef.isMine(ws, plr, theirWall), "vegg i naboens mappe er IKKE min")
	falsy(MazeRef.isMine(ws, plr, fakeFolder("Loose")), "løs del uten forelder er ikke min")
end

-- ── ren modul: ingen require, ingen Roblox-globaler ─────────────────────────
truthy(type(MazeRef.folder) == "function", "folder er eksportert")
truthy(type(MazeRef.matchesName) == "function", "matchesName er eksportert")
truthy(type(MazeRef.isMine) == "function", "isMine er eksportert")

print(string.format("mazeref: %d passed, %d failed", passed, failed))
if failed > 0 then error("mazeref tests failed") end

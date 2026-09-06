-- Labyrinth Mariozo — headless check of the per-player lighting.
-- Run: luau check_lighting.luau   (regenerate the bundle first, see check_labyrint.luau)
--
-- This is the review's findings turned into assertions. The first version of LightingClient
-- passed every unit test in the repo and still: brightened the maze with an Ambient the live
-- game never had, faded INTO the maze so the first third of a second showed ~143 studs instead
-- of 45, ignored CONFIG.Darkness, and daylit the rollback path at load time. None of that is
-- visible in a pure module test, because none of it lives in a pure module.

local Harness = require("./emu/harness")

local h = Harness.new({
	bundle = require("./build/labyrint-spill"),
	name = "labyrint-spill",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end
end

local Lighting = h.Lighting
local function rgbOf(c)
	if c == nil then return "nil" end
	return string.format("%d,%d,%d", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

assert(h:tryRun("server/MazeGame.server"))

-- ── the server's own starting state is the lobby, not the maze ────────────────
-- The original bug: the hub ran the maze's darkness and a player called the game
-- "a black part that is scaled in the shape of a square".
eq(Lighting.FogEnd, 520, "server boots the hub with hub-sized fog")
eq(Lighting.ClockTime, 14.2, "server boots the hub in daylight")
truthy(Lighting.Brightness > 1, "server boots the hub brighter than the maze")

local plr = h:join("Tester", 4242)
h:advance(1)

-- ── nothing is applied before the first payload ───────────────────────────────
-- Stand in for the CONFIG.UseLobby = false rollback boot, where applyDarkness() runs and the
-- player spawns straight into the maze with no lobby at all. If the client applies a preset at
-- load time, it daylights that maze and the documented rollback lever stops working. Setting
-- the dark values here first is what makes this assertion able to fail: comparing against the
-- lobby values the server just set would pass no matter what the client did.
Lighting.FogEnd = 45
Lighting.ClockTime = 0
Lighting.Brightness = 1
assert(h:tryRun("client/LightingClient.client"))
h:advance(1)
eq(Lighting.FogEnd, 45, "the client applies no preset before its first payload (fog)")
eq(Lighting.ClockTime, 0, "the client applies no preset before its first payload (ClockTime)")
eq(Lighting.Brightness, 1, "the client applies no preset before its first payload (brightness)")

local levelInfo = h.ReplicatedStorage:WaitForChild("HudRemotes"):WaitForChild("LevelInfo")
local function send(payload)
	levelInfo:FireClient(plr, payload)
	h:advance(0.05)
end

-- ── entering the maze SNAPS ───────────────────────────────────────────────────
-- 0.05 s is well inside the old 0.55 s tween: under the previous code this assertion would see
-- roughly 130 studs of fog, which is the free sight the review found could be farmed by walking
-- in and out of the return door.
send({ level = 3, inLobby = false, fog = 45, darkness = true })
eq(Lighting.FogEnd, 45, "the maze fog is right immediately, not after a fade")
eq(Lighting.ClockTime, 0, "the maze is at midnight")
eq(Lighting.Brightness, 1, "the maze brightness is the live value")
eq(rgbOf(Lighting.Ambient), "0,0,0", "the maze Ambient is black, as the live game has always had")
eq(rgbOf(Lighting.OutdoorAmbient), "20,20,28", "the maze OutdoorAmbient is the live value")
eq(rgbOf(Lighting.FogColor), "8,8,12", "the maze FogColor is the live value")
eq(Lighting.FogStart, 0, "the maze fog starts at the player")

-- ── the per-level fog on the shared-maze path is honoured ─────────────────────
send({ level = 40, inLobby = false, fog = 28, darkness = true })
eq(Lighting.FogEnd, 28, "a tighter per-level sight is applied")

-- ── CONFIG.Darkness = false must give a LIT, playable game ────────────────────
-- The server hands out no torches when the flag is off, so blacking the world out here would
-- leave a maze nobody can see in at all.
send({ level = 3, inLobby = false, fog = 45, darkness = false })
truthy(Lighting.FogEnd > 45, "darkness off does not black out the maze")
truthy(Lighting.Brightness > 1, "darkness off leaves the maze lit")

-- ── a payload with no darkness field means darkness is on ─────────────────────
send({ level = 3, inLobby = false, fog = 45 })
eq(Lighting.FogEnd, 45, "a missing darkness flag defaults to a dark maze")

-- ── every field the lobby raises is put back by the maze ──────────────────────
-- The failure this guards: a preset that raises Ambient in the lobby but does not set it in the
-- maze carries the fill light into the maze with it.
send({ level = 0, inLobby = true, darkness = true })
h:advance(2) -- let the one transition that is allowed to fade finish
send({ level = 3, inLobby = false, fog = 45, darkness = true })
eq(rgbOf(Lighting.Ambient), "0,0,0", "Ambient does not leak out of the lobby into the maze")
eq(Lighting.FogEnd, 45, "FogEnd does not leak out of the lobby into the maze")

print("")
if #h:errors() > 0 then
	for _, e in h:errors() do
		print("scheduler error: " .. e)
		failed += 1
	end
end
print(string.format("lighting: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("lighting check failed", 0)
end

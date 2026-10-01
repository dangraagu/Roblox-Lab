-- Grow a Crystal — the whole player path in ONE run: join -> spawn -> plant -> harvest -> spend -> leave -> rejoin.
-- Run: luau check_growacrystal_walk.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- docs/complete-game-standard.md §1: "The core loop is reachable from join. Walk the real player path headless:
-- spawn, first objective, one full loop, earn, spend, rejoin. Green unit tests are not a working game." Every
-- other check here starts from a seeded profile or one step of the loop; the reviewer of 2026-09-30 found no gate
-- that walks it end to end, and walked it by hand in 62 s of REAL time, because growth is measured with os.time().
--
-- This run replaces os.time() with the emulator's virtual clock (T0 + seconds advanced), BEFORE the game is loaded,
-- so the game's own `os.time()` calls see time pass as h:advance moves it. The game is not changed for this; a
-- real minute of growth is h:advance(60). Everything else is the real server and the real HUD: the character is
-- spawned by the emulator's engine order, sockets and crystals are clicked through their ClickDetectors, the seed
-- is bought with the HUD's own button, and the rejoin loads what the leave saved.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/grow-a-crystal"), name = "grow-a-crystal", viewport = { 1280, 720 }, touch = false })

-- the virtual wall clock (see the header). os.time(t) with a date table still goes to the real one.
local realOs = os
local T0 = realOs.time()
os = setmetatable({
	time = function(t)
		if t ~= nil then return realOs.time(t) end
		return T0 + math.floor(h.scheduler:now())
	end,
}, { __index = realOs })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local R = RS:FindFirstChild("CrystalRemotes")
local State, Toast = R:FindFirstChild("State"), R:FindFirstChild("Toast")
local store = h.services.DataStoreService:GetDataStore(Config.Save.Store)
local UID = 7001

local function lastState(plr)
	local s = State:sentTo(plr)
	return s[#s] and s[#s].args[1]
end
local function socket(id) return h.workspace:FindFirstChild("Socket_" .. UID .. "_" .. id, true) end
local function click(part, plr)
	local cd = part and part:FindFirstChildOfClass("ClickDetector")
	if cd then cd.MouseClick:Fire(plr) end
	return cd ~= nil
end
local function lastToast(plr)
	local t = Toast:sentTo(plr)
	return t[#t] and tostring(t[#t].args[1]) or nil
end

--=========================================================================== 1. join and spawn

eq(store:GetAsync("u_" .. UID), nil, "a brand-new player: nothing saved")
h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Walker", UID)
assert(h:tryRun("client/Hud.client"))
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char and char:FindFirstChild("HumanoidRootPart")
truthy(hrp ~= nil, "the character spawned")
local s1 = socket(1)
truthy(s1 ~= nil, "socket 1 of the new player's cavern is in the world")
if hrp and s1 then
	local pad = h.workspace:FindFirstChild("Spawn_" .. UID, true)
	truthy(pad ~= nil and (hrp.Position - (pad.Position + Vector3.new(0, 4, 0))).Magnitude < 0.1,
		"the player stands on their own spawn pad")
	local toSock = s1.Position - hrp.Position
	truthy(toSock.Magnitude <= s1:FindFirstChildOfClass("ClickDetector").MaxActivationDistance,
		string.format("socket 1 is in click range from the spawn (%.1f studs)", toSock.Magnitude))
	local look = hrp.CFrame.LookVector
	truthy(look.Z > 0.9, string.format("facing into the cavern, toward the sockets (look z %.2f)", look.Z))
end
local st = lastState(plr)
truthy(st ~= nil, "the join push arrived")
eq(st and st.dust, Config.Economy.StartDust, "the new player starts with the starting dust")
eq(st and st.seeds and st.seeds[1], 3, "and three free Shard seeds: the first action needs no purchase")

--=========================================================================== 2. first objective: plant (within 5 s of joining)

local tJoin = h.scheduler:now()
truthy(click(s1, plr), "socket 1 has a ClickDetector")
h:advance(0.2)
truthy(h.scheduler:now() - tJoin < 5, "planted within 5 s of spawning")
truthy(s1 and s1:FindFirstChild("Crystal") ~= nil, "a crystal stands on socket 1")
st = lastState(plr)
eq(st and st.seeds and st.seeds[1], 2, "one seed used")
truthy(st and st.plants and st.plants["1"] ~= nil, "the State push shows the plant")

--=========================================================================== 3. one full loop: grow, harvest, earn

local grow = Config.Growth.SecondsPerStage[1] * Config.Growth.StageCount
h:advance(grow - 5)
local crystal = s1 and s1:FindFirstChild("Crystal")
local dustBefore = (lastState(plr) or {}).dust
click(crystal, plr)
h:advance(0.2)
truthy(string.find(lastToast(plr) or "", "growing", 1, true) ~= nil, "clicked early: told it is still growing (" .. tostring(lastToast(plr)) .. ")")
eq((lastState(plr) or {}).dust, dustBefore, "and nothing paid")
h:advance(6)
click(crystal, plr)
h:advance(0.2)
st = lastState(plr)
local earned = (st and st.dust or 0) - dustBefore
truthy(earned >= Config.Economy.DustValue[1], "a grown crystal harvests for Gem Dust (+" .. earned .. ")")
truthy(st and st.lastHarvest and st.lastHarvest.n == 1, "the harvest is announced to the client (burst, refraction tier)")
truthy(st and (st.codexCount or 0) >= 1, "and enters the Gem Codex")
eq(s1 and s1:FindFirstChild("Crystal"), nil, "the socket is empty again")

--=========================================================================== 4. spend, with the HUD's own button

local buyBtn = nil
for _, d in plr.PlayerGui:GetDescendants() do
	if d:IsA("TextButton") and d.Text == "Buy 💎" .. Config.Economy.SeedCost[1] then buyBtn = d end
end
truthy(buyBtn ~= nil, "the HUD shows the Shard seed's price on its buy button")
-- scalars, copied now: the emulator records a payload by reference, so `seeds` is the server's live table
local before = lastState(plr)
local dust0, seeds0 = before.dust, before.seeds[1]
if buyBtn then buyBtn.Activated:Fire() end
h:advance(0.3)
st = lastState(plr)
eq(st and st.dust, dust0 - Config.Economy.SeedCost[1], "buying a Shard seed spends its price")
eq(st and st.seeds and st.seeds[1], seeds0 + 1, "and adds the seed")

-- plant two more, so something is growing when the player leaves
click(socket(2), plr)
click(socket(3), plr)
h:advance(0.3)
st = lastState(plr)
local leaving = { dust = st.dust, seeds1 = st.seeds[1], codex = st.codexCount, planted = 0 }
for _ in st.plants do leaving.planted += 1 end
eq(leaving.planted, 2, "two crystals growing as the player leaves")

--=========================================================================== 5. leave, time passes, rejoin

h:leave(plr)
h:advance(1)
local saved = store:GetAsync("u_" .. UID)
truthy(saved and saved.data, "the leave saved the profile")
eq(saved and saved.lockUntil, 0, "and released the session lock")
h:advance(grow + 5) -- offline: the two crystals finish growing while the player is away

local back = h:join("Walker", UID)
h:advance(1)
st = lastState(back)
truthy(st ~= nil, "the rejoin push arrived")
eq(st and st.dust, leaving.dust, "rejoin: the dust is kept")
eq(st and st.seeds and st.seeds[1], leaving.seeds1, "the seeds are kept")
eq(st and st.codexCount, leaving.codex, "the codex is kept")
local plants = 0
for _ in (st and st.plants or {}) do plants += 1 end
eq(plants, 2, "both plants are kept (integer socket keys survive the JSON round trip)")
local s2 = socket(2)
truthy(s2 and s2:FindFirstChild("Crystal") ~= nil, "and stand on their sockets again")
local d0 = st and st.dust or 0
click(s2 and s2:FindFirstChild("Crystal"), back)
h:advance(0.2)
truthy(((lastState(back) or {}).dust or 0) > d0, "they grew while the player was away: harvested right after the rejoin")
truthy(#h:errors() == 0, "no errors in the whole walk" .. (if #h:errors() > 0 then " (" .. tostring(h:errors()[1]) .. ")" else ""))

print(string.format("growacrystal walk: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal walk failed", 0) end

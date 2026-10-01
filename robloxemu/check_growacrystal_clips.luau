-- Grow a Crystal — every clip in MARKETING.md can be staged the way it says, in the session the night shift films in.
-- Run: luau check_growacrystal_clips.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- The clip list (MARKETING.md, standard §4) is filmed in Studio with API access OFF (EYECANDY.md §9 step 2), so the
-- server has no DataStore. Clips 4-7 were staged with the public codes ("off camera: codes, then buy chamber 2")
-- and clip 5 with the weekly Geode. Measured on 2026-10-01 before the fix: in a session with no DataStore every
-- code came back "retry" (WELCOME, CRYSTAL and MYTHIC all refused, dust stayed 30) and so did the Geode, because
-- both refuse a grant they cannot persist. Clips 4-7 could not be staged at all.
--
-- A session that can NEVER save (no DataStore on the server, or Studio without API access) has nothing to
-- duplicate: nothing from it persists, a code's reward included. It grants the public codes and the Geode for the
-- session and tells the player at join that progress here won't save. A session that could save but cannot right
-- now (locked, failed load, lost lock) still refuses (check_growacrystal_rejoin, check_growacrystal_lock).
--
-- This run is that Studio session: Config.Save.Enabled = false (what tryStore returns when GetDataStore raises),
-- the real server, the real HUD (desktop, 1280x720) and the real cavern client. Every step a clip's "Staging" column
-- names is done through the HUD's own buttons or the socket's ClickDetector, and every number MARKETING.md states
-- is checked against the game. os.time is the emulator's virtual clock, set inside a Legendary Geode week.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function has(s, w) return type(s) == "string" and string.find(string.lower(s), string.lower(w), 1, true) ~= nil end

local h = Harness.new({ bundle = require("./build/grow-a-crystal"), name = "grow-a-crystal", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local function mod(name) return h:_require(RS:FindFirstChild(name)) end
local Config = mod("Config")
local Geode = mod("Geode")

-- 2026-10-12 12:00 UTC: MARKETING.md says 2026-10-12..18 is a Legendary week and 2026-10-19..25 a Mythic one
local realOs = os
local T_LEG = Config.Geode.Epoch + 5 * Config.Geode.WeekSeconds + 12 * 3600 -- Epoch is Monday 2026-09-07 00:00 UTC
eq(Geode.exclusiveFor(T_LEG, Config.Geode), 5, "the week of 2026-10-12 cracks a Legendary Geode (MARKETING clip 5)")
eq(Geode.exclusiveFor(T_LEG + 6 * 86400, Config.Geode), 5, "... through 2026-10-18")
eq(Geode.exclusiveFor(T_LEG + 7 * 86400, Config.Geode), 6, "and the week of 2026-10-19 a Mythic one")
eq(Geode.exclusiveFor(T_LEG + 14 * 86400, Config.Geode), 5, "then Legendary again (the rotation is Prism, Legendary, Mythic, Legendary)")
eq(Geode.exclusiveFor(T_LEG + 21 * 86400, Config.Geode), 4, "and then Prism")
eq(Geode.exclusiveFor(Config.Geode.Epoch + 3 * Config.Geode.WeekSeconds + 4 * 86400, Config.Geode), 5,
	"and 2026-09-28..10-04 (the week of this pass, 2026-10-01) is a Legendary week too")
os = setmetatable({
	time = function(t)
		if t ~= nil then return realOs.time(t) end
		return T_LEG + math.floor(h.scheduler:now())
	end,
}, { __index = realOs })

Config.Save.Enabled = false -- Studio, API access off: tryStore returns nil (GetDataStore raises in Roblox)
assert(h:tryRun("server/Main.server"))
local R = RS:FindFirstChild("CrystalRemotes")
local State, Toast = R:FindFirstChild("State"), R:FindFirstChild("Toast")

h.game:GetService("RunService"):setIsServer(false)
local plr = h:join("Filmer", 4040)
h:advance(0.5)
local char = h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local hrp = char:FindFirstChild("HumanoidRootPart")
local hum = char:FindFirstChildOfClass("Humanoid")
hum.FloorMaterial = Enum.Material.Slate
hum.MoveDirection = Vector3.new(0, 0, 0)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Grotto.client"))
local function lastState()
	local s = State:sentTo(plr)
	return s[#s] and s[#s].args[1]
end
do -- the join push went out before the clients connected; hand it over like the next push would
	local rec = State:sentTo(plr)[#State:sentTo(plr)]
	State.OnClientEvent:Fire(table.unpack(rec.args, 1, rec.args.n))
end
local RunService = h.game:GetService("RunService")
local hudRoot = plr.PlayerGui.CrystalHud.Root
local grotto = plr.PlayerGui.CrystalGrotto.Root
local card, chip, relaxBtn = grotto.BandCard, grotto.BandChip, grotto.RelaxButton
local folder = h.workspace:FindFirstChild("CrystalLocalGrotto")
local cards = {}
local function frames(seconds)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
		if card.Visible and cards[#cards] ~= card.Text then table.insert(cards, card.Text) end
	end
end
-- The button tools/film_game.py's laby_click_gui(shot, pattern, gui) clicks: the FIRST TextButton under that ScreenGui,
-- in GetDescendants order, whose Text:find(pattern) matches (a Lua pattern). MARKETING.md names these patterns.
local function button(pattern: string, gui: string?): TextButton?
	local g = plr.PlayerGui:FindFirstChild(gui or "CrystalHud")
	for _, d in (g and g:GetDescendants() or {}) do
		if d.ClassName == "TextButton" and string.find(d.Text, pattern) then return d end
	end
	return nil
end
local function socket(id) return h.workspace:FindFirstChild("Socket_4040_" .. id, true) end
local function click(part)
	local cd = part and part:FindFirstChildOfClass("ClickDetector")
	if cd then cd.MouseClick:Fire(plr) end
	return cd ~= nil
end

--=========================================================================== the session

local st = lastState()
eq(st.dust, 30, "every take is a new player with 30 Gem Dust")
eq(st.seeds[1], 3, "and 3 free Shard seeds")
local jt = Toast:sentTo(plr)
truthy(#jt == 1 and has(tostring(jt[1].args[1]), "won't save"), "the session says at join that progress here won't save ("
	.. tostring(jt[1] and jt[1].args[1]) .. ")")

--=========================================================================== clips 1-3: grow_cycle (plant, grow, harvest)

for _, id in { 2, 3, 4 } do truthy(click(socket(id)), "clip 1: socket " .. id .. " can be clicked") end
h:advance(0.3)
for _, id in { 2, 3, 4 } do truthy(socket(id):FindFirstChild("Crystal") ~= nil, "clip 1: a crystal sprouts on socket " .. id) end
eq(lastState().seeds[1], 0, "clip 1: 'Shard (3)' counts down to 0")
eq(lastState().dust, 30, "clip 1: the free seeds cost no dust")
h:advance(64) -- clip 2: 68 s of real time at 6.5x covers the 60-s Shard
local d0 = lastState().dust
for _, id in { 2, 3, 4 } do click(socket(id):FindFirstChild("Crystal")); frames(0.2) end
local lh = lastState().lastHarvest
eq(lh and lh.n, 3, "clip 3: three real harvests")
truthy(lastState().dust >= d0 + 3, "clip 3: the dust counter climbs (" .. d0 .. " -> " .. lastState().dust .. ")")
local shards = 0
for _, d in folder:GetChildren() do if d.Name == "Shard" then shards += 1 end end
truthy(shards > 0, "clip 3: harvest bursts fly (" .. shards .. " shards)")
frames(2)

--=========================================================================== the codes (clips 4-7 stage with them)

local codeBox, codeBtn = nil, nil
for _, d in hudRoot:GetDescendants() do
	if d.ClassName == "TextBox" then codeBox = d end
	if d.ClassName == "TextButton" and d.Text == "Redeem" then codeBtn = d end
end
truthy(codeBox ~= nil and codeBtn ~= nil, "the HUD's code box and Redeem button")
local dustBeforeCodes = lastState().dust
for _, code in { "WELCOME", "CRYSTAL", "MYTHIC" } do
	codeBox.Text = code
	codeBtn.Activated:Fire()
	h:advance(0.2)
	local shown = codeBtn.Text
	local result = codeBtn.Parent:FindFirstChild("CodeResult")
	if result and result.Visible then shown = result.Text end
	truthy(has(shown, "redeemed"), string.format("code %s redeems in a session with no DataStore (%q)", code, shown))
	h:advance(2.2)
end
eq(lastState().dust - dustBeforeCodes, 5600, "the codes give 5 600 dust (with the starting 30: 5 630)")
codeBox.Text = "WELCOME"
codeBtn.Activated:Fire()
h:advance(0.2)
local again = codeBtn.Text
local againR = codeBtn.Parent:FindFirstChild("CodeResult")
if againR and againR.Visible then again = againR.Text end
truthy(has(again, "already"), string.format("a code still works once per session (%q)", again))
h:advance(2.2)
eq(Config.Economy.ChamberBaseCost, 500, "chamber 2 costs 500")
eq(math.floor(Config.Economy.ChamberBaseCost * Config.Economy.ChamberGrowth + 0.5), 1100, "chamber 3 costs 1 100")

--=========================================================================== clip 4: glowworm_glide

local chamberBtn = button("Buy Chamber")
truthy(chamberBtn ~= nil, "the HUD has a Buy Chamber button")
chamberBtn.Activated:Fire() -- off camera: chamber 2
h:advance(0.3)
eq(lastState().chambers, 2, "clip 4 staging: chamber 2 bought with the HUD")
frames(6)
local cardsBefore = #cards
chamberBtn = button("Buy Chamber")
local path = chamberBtn and chamberBtn:GetFullName()
print("  clip 4 clicks: " .. tostring(path))
truthy(path ~= nil and has(path, "CrystalHud.Root"), "\"Buy Chamber\" in CrystalHud finds the chamber button (" .. tostring(path) .. ")")
chamberBtn.Activated:Fire() -- the recorded click
h:advance(0.1)
eq(lastState().chambers, 3, "clip 4: one tap buys chamber 3")
frames(5)
local named = false
for i = cardsBefore + 1, #cards do if has(cards[i], "Glow-worm Hollow") then named = true end end
truthy(named, "clip 4: the title card names Glow-worm Hollow (" .. table.concat(cards, " / ") .. ")")
truthy(has(chip.Text, "Glow-worm Hollow"), "clips 4 and 7: the cavern is in its second band (" .. chip.Text .. ")")
local worms = 0
for _, d in folder:GetDescendants() do if string.sub(d.Name, 1, 5) == "Worm_" and d.Parent ~= nil then worms += 1 end end
truthy(worms > 0, "clip 4: the glow-worms are up (" .. worms .. " parts)")

--=========================================================================== clip 5: legendary_beam

local geodeBtn = button("Crack Geode")
truthy(geodeBtn ~= nil and has(geodeBtn.Text, "Legendary"), "clip 5: the Geode button names this week's tier (" .. tostring(geodeBtn and geodeBtn.Text) .. ")")
local legBefore = lastState().seeds[5] or 0
geodeBtn.Activated:Fire()
h:advance(0.3)
eq((lastState().seeds[5] or 0) - legBefore, 1, "clip 5: the Geode cracks in a session with no DataStore and gives a Legendary seed")
-- anchored: the Geode button says "Legendary" too, and Roblox does not promise GetDescendants order
local legBtn = button("^Legendary")
truthy(legBtn ~= nil and string.sub(legBtn.Text, 1, 10) == "Legendary ", "clip 5: ^Legendary finds the seed row (" .. tostring(legBtn and legBtn.Text) .. ")")
legBtn.Activated:Fire()
h:advance(0.2)
local s9 = socket(9)
truthy(click(s9), "clip 5: socket 9 (chamber 2's terrace) is in the world")
h:advance(0.3)
local planted = lastState().plants["9"]
eq(planted and planted.tier, 5, "clip 5: a Legendary grows on socket 9")
local grow = Config.Growth.SecondsPerStage[5] * Config.Growth.StageCount
eq(grow, 20 * 60, "clip 5: a Legendary takes 20 min (a Mythic " .. (Config.Growth.SecondsPerStage[6] * Config.Growth.StageCount / 60) .. ")")
eq(Config.Growth.SecondsPerStage[6] * Config.Growth.StageCount, 40 * 60, "clip 5: a Mythic seed takes 40 min")
local spawnAt = hrp.Position
local d9 = if s9 then (s9.Position - spawnAt).Magnitude else math.huge
truthy(s9 ~= nil and d9 <= s9:FindFirstChildOfClass("ClickDetector").MaxActivationDistance,
	string.format("clip 5: socket 9 is in click range from the spawn (%.1f studs)", d9))
h:advance(grow + 1)
frames(0.5)
local cardsB = #cards
click(s9 and s9:FindFirstChild("Crystal"))
frames(0.3)
local lh5 = lastState().lastHarvest
truthy(lh5 and lh5.socket == 9 and lh5.tier >= 5, "clip 5: the harvest refracts to Legendary or Mythic (tier " .. tostring(lh5 and lh5.tier) .. ")")
local core = folder:FindFirstChild("BeamCore")
truthy(core ~= nil and core.Parent ~= nil, "clip 5: the beam of light fires")
local beamCard = false
for i = cardsB + 1, #cards do if has(cards[i], "LEGENDARY") or has(cards[i], "MYTHIC") then beamCard = true end end
truthy(beamCard, "clip 5: the card names it (" .. table.concat(cards, " / ") .. ")")
frames(3)

--=========================================================================== clip 6: relax_pool

-- the avatar walks to the front of the pool ring at about (-4, 21, 106), flush with the top terrace
local floorAt = nil
for _, d in h.workspace:FindFirstChild("Plots"):GetDescendants() do
	if d:IsA("BasePart") and d.CanCollide then
		local lp = d.CFrame:PointToObjectSpace(Vector3.new(-4, 21, 106))
		local half = d.Size / 2
		if math.abs(lp.X) <= half.X and math.abs(lp.Z) <= half.Z and math.abs(lp.Y - half.Y) <= 0.6 then floorAt = d end
	end
end
truthy(floorAt ~= nil, "clip 6: (-4, 21, 106) is on a floor (" .. tostring(floorAt and floorAt.Name) .. ")")
hrp.CFrame = CFrame.new(Vector3.new(-4, 24, 106), Vector3.new(-4, 24, 125))
frames(0.5)
eq(button("Relax", "CrystalGrotto"), relaxBtn, "clip 6: \"Relax\" in CrystalGrotto finds the Relax button")
relaxBtn.Activated:Fire()
frames(0.5)
eq(hum.Sit, true, "clip 6: Relax sits the avatar down at the pool")
truthy(has(chip.Text, "Relaxing") and has(chip.Text, "keep growing"), "clip 6: the chip says so (" .. chip.Text .. ")")
relaxBtn.Activated:Fire()
frames(0.3)

--=========================================================================== clip 8 (held): the board in Studio

local board = h.workspace:FindFirstChild("Leaderboard", true)
local note = board and board:FindFirstChild("BoardGui") and board.BoardGui:FindFirstChild("Note")
eq(note and note.Text, Config.Board.Text.Offline, "clip 8 is held: in Studio the board has no rows, it says it is offline")

for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("growacrystal clips: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal clips check failed", 0) end

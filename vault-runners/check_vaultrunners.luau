-- Vault Runners — the headless gate. Boots the REAL server script in robloxemu and plays a run.
--
-- Run (from this directory):
--   cd ../robloxemu && py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--   cd ../vault-runners && luau check_vaultrunners.luau
--
-- Why this file exists, and what the unit tests cannot see:
--
--   * `require("./X")` compiles clean, passes every spec, and makes a server fail to load in
--     Roblox. Only booting the real script catches it.
--   * An UNPARENTED Instance raises nothing, warns nothing, and is invisible to every unit test.
--     Grow a Crystal shipped `makeSocket` without `part.Parent =` and its entire core loop was
--     unreachable in a published game while 166 tests stayed green. So this file ASKS THE
--     WORKSPACE how many parts arrived, and then walks into them.
--   * The rule the game is built on — gems bank ONLY if you are out before the seal — is
--     asserted in tests/RunState.spec.luau against a pure table. Here it is asserted against the
--     player's actual leaderstats, after the actual server ran the actual countdown.

local Harness = require("../robloxemu/emu/harness")
-- The game's own Config, read the way a spec reads it — so a tick length that moves cannot leave
-- this file advancing a stale number of seconds and quietly measuring nothing.
local Config = require("./src/shared/Config")
local Trace = require("./src/shared/Trace")

local h = Harness.new({
	bundle = require("../robloxemu/build/vault-runners"),
	name = "vault-runners",
	viewport = { 1280, 720 },
	touch = false,
})

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local ME = 4242

-- Written the way loadProfile actually READS it: under "u_<uid>", with the profile inside
-- `.data`. A check that writes a shape the server does not read is really testing
-- defaultProfile() and says so about nothing.
-- 1500 banked opens Bronze and Silver and leaves GOLD LOCKED, which is what makes the refusal
-- below a real test. 2000 gems in the wallet pays for a pet.
-- `floors` is written with INTEGER keys on purpose: it goes through the emulator's JSON
-- round-trip, so loadProfile's numKeys normalisation is exercised rather than assumed.
local store = h.services.DataStoreService:GetDataStore("VaultRunners_v1")
store:SetAsync("u_" .. ME, {
	data = {
		gems = 2000, totalBanked = 1500,
		pets = {}, equipped = nil,
		floors = { [1] = 1, [2] = 1, [3] = 1 },
		escapes = 0, wipes = 0,
	},
})

assert(h:tryRun("server/Main.server"))
h:advance(1)

local me = h:join("Runner", ME)
h:advance(1)
h.Players:simulateSpawn(me, h.workspace)
h:advance(1)

--============================================================================ the hub is real

local hub = h.workspace:FindFirstChild("Hub")
truthy(hub ~= nil, "workspace.Hub exists (control: the builder ran at all)")

local function countIn(node, pred)
	local n = 0
	for _, d in node:GetDescendants() do
		if pred(d) then n += 1 end
	end
	return n
end

if hub ~= nil then
	local portals, pedestals = 0, 0
	for _, d in hub:GetDescendants() do
		if string.match(tostring(d.Name), "^Portal_") then portals += 1 end
		if string.match(tostring(d.Name), "^Pet_") then pedestals += 1 end
	end
	eq(portals, 3, "all three vault portals are parented into the world")
	eq(pedestals, 8, "all eight Vault-Keeper pedestals are parented into the world")
	truthy(hub:FindFirstChild("HubPad") ~= nil, "the hub pad itself landed")
	truthy(hub:FindFirstChild("HubSpawn") ~= nil, "and so did the spawn")

	local lights = countIn(hub, function(d) return d.ClassName == "PointLight" end)
	truthy(lights >= 4, "the hub is lit (" .. lights .. " PointLights) — the preset has no sun")
end

local ls = me:FindFirstChild("leaderstats")
truthy(ls ~= nil, "the player has leaderstats")
local gemsValue = ls and ls:FindFirstChild("Gems")
local bankedValue = ls and ls:FindFirstChild("Banked")
truthy(gemsValue ~= nil, "with a Gems readout")
eq(gemsValue and gemsValue.Value, 2000, "loaded from the DataStore, not reset to default")
eq(bankedValue and bankedValue.Value, 1500, "and the banked total came back too")

--============================================================================ a locked vault refuses

local remotes = h.services.ReplicatedStorage:FindFirstChild("VaultRemotes")
truthy(remotes ~= nil, "the remotes folder exists")
local Enter = remotes:FindFirstChild("Enter")
local RunRemote = remotes:FindFirstChild("Run")
local Toast = remotes:FindFirstChild("Toast")
local vaults = h.workspace:FindFirstChild("Vaults")
truthy(vaults ~= nil, "workspace.Vaults exists")

Enter:simulateFireServer(me, 3)   -- Gold, and 1500 banked is nowhere near 6000
h:advance(1)
eq(#vaults:GetChildren(), 0, "entering a LOCKED vault builds nothing")
local toasts = Toast:getSent()
truthy(#toasts > 0 and string.find(tostring(toasts[#toasts].args[1]), "6000") ~= nil,
	"and the player is told exactly what is missing, rather than nothing happening")

--============================================================================ run 1: BANK IT

local function lastRunEvent(kind)
	local sent = RunRemote:getSent()
	for i = #sent, 1, -1 do
		if sent[i].args[1] == kind then return sent[i].args[2] end
	end
	return nil
end

Enter:simulateFireServer(me, 1)   -- Bronze, floor 1
h:advance(0.5)

eq(#vaults:GetChildren(), 1, "entering an unlocked vault builds exactly one vault folder")
local vault = vaults:GetChildren()[1]
truthy(vault ~= nil, "and it is reachable from the workspace")

local startInfo = lastRunEvent("start")
truthy(startInfo ~= nil, "the HUD was told the run started")
eq(startInfo and startInfo.floor, 1, "on floor 1")
eq(startInfo and startInfo.storeys, 3, "of a three-storey Bronze vault")
eq(startInfo and startInfo.gems, 12, "holding twelve gems")

-- THE COUNTDOWN IS DERIVED FROM THE MAZE THAT WAS JUST GENERATED, not read off the tier. The
-- three typed numbers this replaced (70 / 80 / 90) made Silver and Gold unwinnable on floor 1,
-- because the plane's speed was height/countdown and a taller vault therefore swept its LOWER
-- storeys faster. tests/Collapse.spec.luau proves the resulting run is survivable; this proves
-- the SERVER is the thing doing it.
local bronzeCountdown = startInfo and startInfo.collapseSeconds
truthy(type(bronzeCountdown) == "number" and bronzeCountdown > 0,
	"the server sent the client a real countdown (" .. tostring(bronzeCountdown) .. "s)")

-- ...and WalkSpeed is WRITTEN, not assumed. Every countdown in the game is (route studs) /
-- Config.Movement.WalkSpeed, so a Humanoid left on Roblox's default 16 while Config says 24
-- makes every vault 50% harder than the spec that signed it off — and the spec would still be
-- green, because it reads Config too. The review's words: "nothing in the game sets WalkSpeed".
local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
truthy(hum ~= nil, "the runner has a Humanoid")
eq(hum and hum.WalkSpeed, 24, "and the server wrote Config.Movement.WalkSpeed onto it")

-- ASK THE WORKSPACE. Bronze floor 1 is 96 generated parts + 12 gems + 3 torches + 1 dust host.
local baseParts = countIn(vault, function(d) return d:IsA("BasePart") end)
local gemParts = countIn(vault, function(d) return string.match(tostring(d.Name), "^Gem_") ~= nil end)
local vaultLights = countIn(vault, function(d) return d.ClassName == "PointLight" end)
print(string.format("  Bronze floor 1: %d BaseParts, %d gems, %d PointLights",
	baseParts, gemParts, vaultLights))
eq(baseParts, 112, "the whole vault landed in the workspace: 96 parts + 12 gems + 3 torches + 1 dust host")
eq(gemParts, 12, "every gem is a real Part in the world, not a row in a Lua table")
eq(vaultLights, 6, "the vault is lit: 3 torches + exit + seal + collapse")

truthy(vault:FindFirstChild("ExitPad") ~= nil, "the exit pad exists")
truthy(vault:FindFirstChild("Collapse") ~= nil, "the collapse plane exists")
truthy(vault:FindFirstChild("Seal") ~= nil, "the seal exists")

local hrp = me.Character:FindFirstChild("HumanoidRootPart")
truthy(hrp ~= nil, "the runner has a root part")

-- WALK, DO NOT TELEPORT. Every earlier version of this file proved an escape by writing the root
-- part straight onto the ExitPad — which is also precisely the exploit the review found, so the
-- gate was demonstrating the cheat and calling it a pass. The server now keeps its own trusted
-- position (src/shared/Trace.luau) and every rule reads that, so a claim has to be one a runner
-- could have made. This helper moves the root part at the speeds a runner actually has,
-- horizontally at WalkSpeed and upward at the climb rate, advancing the clock as it goes.
local WALK_H, WALK_UP = Trace.speeds(Config)
WALK_H = WALK_H / Config.Run.TrustedSpeedFactor          -- the honest walk, not the tolerance
WALK_UP = WALK_UP / Config.Run.TrustedClimbFactor        -- the honest climb, not the tolerance
local STEP = Config.Run.TickSeconds

-- Returns the seconds spent walking, so an assertion can talk about how long the run took.
local function walkTo(target, stopWhen)
	local spent = 0
	for _ = 1, 4000 do
		if stopWhen ~= nil and stopWhen() then break end
		local cur = hrp.Position
		local dx, dz = target.X - cur.X, target.Z - cur.Z
		local dy = target.Y - cur.Y
		local flat = math.sqrt(dx * dx + dz * dz)
		if flat < 0.5 and math.abs(dy) < 0.5 then break end
		local moveH = math.min(flat, WALK_H * STEP)
		local nx = flat > 1e-6 and (cur.X + dx / flat * moveH) or cur.X
		local nz = flat > 1e-6 and (cur.Z + dz / flat * moveH) or cur.Z
		-- Up is the climb; down is a fall and costs nothing.
		local ny = cur.Y + (dy > 0 and math.min(dy, WALK_UP * STEP) or dy)
		hrp.CFrame = CFrame.new(nx, ny, nz)
		h:advance(STEP)
		spent += STEP
	end
	h:advance(STEP)
	return spent + STEP
end
local origin = vault:FindFirstChild("Floor_0").Position
truthy(math.abs(hrp.Position.X - origin.X) < 200,
	"the runner was actually moved into their vault, not left standing in the hub")

-- Walk onto three gems. The server polls positions on its run loop, so putting the root part on
-- a gem IS walking onto it. The list is captured ONCE: collecting a gem destroys it, so
-- re-enumerating and taking "the fourth one" each time silently walks onto the same gem twice.
local function gemList(folder)
	local out = {}
	for _, d in folder:GetDescendants() do
		if string.match(tostring(d.Name), "^Gem_") then out[#out + 1] = d end
	end
	return out
end

local allGems = gemList(vault)
eq(#allGems, 12, "twelve gems to choose from")
local collected = 0
for i = 1, 3 do
	local g = allGems[i * 3]
	if g ~= nil then
		walkTo(g.Position)
		collected += 1
	end
end
eq(collected, 3, "three gems were walked to")

-- A runner who WALKS to three gems collects the ones they pass on the way, which a runner who
-- teleported never did. So the assertion is the relationship, not a number typed in: gems gone
-- from the world, gems counted by the server and gems in hand all have to agree.
local gemsLeft = countIn(vault, function(d) return string.match(tostring(d.Name), "^Gem_") ~= nil end)
local gemEvent = lastRunEvent("gem")
truthy(gemEvent ~= nil and gemEvent.collected >= 3,
	"at least the three gems walked to were collected (" .. tostring(gemEvent and gemEvent.collected) .. ")")
eq(gemsLeft, 12 - (gemEvent and gemEvent.collected or 0),
	"every collected gem is GONE from the world, and no other one is")
eq(gemEvent and gemEvent.carried, (gemEvent and gemEvent.collected or 0) * 4,
	"the runner is carrying four gems' worth for each one collected")
eq(gemsValue.Value, 2000, "and NONE of it is banked yet — carrying is not owning")

-- ...and out through the exit, with time to spare.
local exitPad = vault:FindFirstChild("ExitPad")
walkTo(exitPad.Position, function() return #vaults:GetChildren() == 0 end)

local ended = lastRunEvent("end")
truthy(ended ~= nil and ended.ok, "escaping before the seal is a successful run")
eq(ended and ended.reason, "escaped", "and reads as an escape")
eq(ended and ended.banked, ended and ended.carried,
	"exactly what was carried was banked (no pet equipped, so 1.00x)")
eq(gemsValue.Value, 2000 + (ended and ended.banked or 0), "the wallet went up by exactly that")
eq(bankedValue.Value, 1500 + (ended and ended.banked or 0), "and so did the lifetime total")
eq(#vaults:GetChildren(), 0, "the vault was torn down with ONE Destroy, not leaked")

--============================================================================ run 2: SEALED IN

-- Same vault, same player, but this time stand still on the TOP storey until the countdown
-- expires. Below the top storey the collapse is lethal; on the top storey the SEAL ends the run.
-- Either way the answer to "do I keep the gems" is no, and that is the whole game.
Enter:simulateFireServer(me, 1)
h:advance(0.5)
vault = vaults:GetChildren()[1]
truthy(vault ~= nil, "back in for a second run")

local before = gemsValue.Value
local topGem, topY = nil, -math.huge
for _, d in vault:GetDescendants() do
	if string.match(tostring(d.Name), "^Gem_") and d.Position.Y > topY then
		topGem, topY = d, d.Position.Y
	end
end
truthy(topGem ~= nil, "there is a gem on the top storey to stand on")
walkTo(topGem.Position)
local carriedUpTop = lastRunEvent("gem").carried
truthy(carriedUpTop >= 4, "carrying at least the top-storey gem's worth (" .. carriedUpTop .. ")")

-- Now do nothing at all for longer than THIS VAULT'S countdown. Read off the run's own start
-- event, never typed: this file used to advance a flat 75 seconds against a hand-typed 70, and
-- once the countdown started being derived from the maze it cleared the seal by about one
-- second. A gate that passes by a second of luck is a gate that stops testing anything the next
-- time a number moves.
local run2Countdown = lastRunEvent("start").collapseSeconds
truthy(run2Countdown > 0, string.format("run 2's countdown is %.1fs", run2Countdown))
h:advance(run2Countdown + 5)

local sealed = lastRunEvent("end")
truthy(sealed ~= nil, "the run ended on its own — a player who stops moving is still resolved")
falsy(sealed and sealed.ok, "and it was NOT a success")
eq(sealed and sealed.reason, "sealed", "the vault sealed with the runner inside")
eq(sealed and sealed.banked, 0, "nothing was banked")
eq(sealed and sealed.carried, carriedUpTop, "and every gem being carried was lost with it")
eq(gemsValue.Value, before, "THE RULE: the wallet did not move")
eq(#vaults:GetChildren(), 0, "and the sealed vault was torn down")

--============================================================================ the pads CRUMBLE

-- The obby, on the live server. tests/Ascent.spec.luau proves the rule; this proves the server
-- is running it — that standing on a pad actually turns a Roblox Part's CanCollide off, and that
-- the part comes back. A shaft that never crumbles is v1's staircase with a spec attached, and a
-- shaft that never comes back is an unwinnable vault; nothing else in this file would notice
-- either, because the walk helper flies straight up the middle of the stairwell.
do
	Enter:simulateFireServer(me, 1)
	h:advance(0.5)
	vault = vaults:GetChildren()[1]
	local pad = vault:FindFirstChild("Step_0_3")
	truthy(pad ~= nil, "the climb shaft has a third pad")
	truthy(pad.CanCollide, "...and it is solid before anybody stands on it")
	local wasTransparency = pad.Transparency

	-- Stand ON it — the pad's top plus a runner's root height, which is what Ascent.padUnder
	-- measures against. Walked to, not warped to: the server reads the TRUSTED position.
	walkTo(Vector3.new(pad.Position.X, pad.Position.Y + 0.5 + Config.Run.RunnerRootHeight,
		pad.Position.Z))
	truthy(pad.CanCollide, "landing on a pad does not pull it out from under the foot that lands")
	h:advance(Config.Ascent.CrumbleSeconds + 2 * STEP)
	falsy(pad.CanCollide, "...and a beat later the pad is gone")
	falsy(pad.CanQuery, "a pad that is gone cannot be raycast at either")
	truthy(pad.Transparency > wasTransparency, "and it is drawn as gone, not just made walk-through")
	h:advance(Config.Ascent.RespawnSeconds + 2 * STEP)
	truthy(pad.CanCollide, "the pad comes BACK — a shaft that eats its own route is unwinnable")
	eq(pad.Transparency, wasTransparency, "...and is drawn solid again")

	-- Never touched, never crumbles. Otherwise "the pads crumble" could just be a timer that
	-- dissolves the whole shaft on a clock and the standing test proves nothing.
	-- Bronze floor 1 is three storeys, so the shafts are on storey 0 and storey 1; storey 2
	-- is the top and has none. Pad 5 of storey 1 is eighteen studs above anywhere the walk went.
	local untouched = vault:FindFirstChild("Step_1_5")
	truthy(untouched ~= nil and untouched.CanCollide,
		"a pad nobody has stood on is still there after the whole cycle")

	h:advance(lastRunEvent("start").collapseSeconds + 5)
end

--============================================================================ run 3: THE COLLAPSE

-- Storey 0, standing still. The plane sweeps that floor long before the countdown expires, so
-- this run has to end in death rather than in a seal.
Enter:simulateFireServer(me, 1)
h:advance(0.5)
vault = vaults:GetChildren()[1]
local groundGem, lowY = nil, math.huge
for _, d in vault:GetDescendants() do
	if string.match(tostring(d.Name), "^Gem_") and d.Position.Y < lowY then
		groundGem, lowY = d, d.Position.Y
	end
end
walkTo(groundGem.Position)
local carriedNow = lastRunEvent("gem").carried
local beforeCollapse = gemsValue.Value
local run3Countdown = lastRunEvent("start").collapseSeconds
h:advance(run3Countdown + 5)

local died = lastRunEvent("end")
eq(died and died.reason, "collapse", "standing on storey 0 gets you caught by the collapse")
eq(died and died.banked, 0, "which banks nothing")
eq(died and died.carried, carriedNow, "and loses what was in your hands")
eq(gemsValue.Value, beforeCollapse, "the wallet did not move")

--============================================================================ the collapse MOVED

-- The plane and the seal are the entire feel of the game. If the server never writes their
-- CFrame the run still resolves correctly on the countdown and the vault just sits there,
-- perfectly still, while a HUD ticks down. Nothing else in this file would notice.
Enter:simulateFireServer(me, 1)
h:advance(0.5)
vault = vaults:GetChildren()[1]
local plane = vault:FindFirstChild("Collapse")
local seal = vault:FindFirstChild("Seal")
local planeY0, sealY0 = plane.Position.Y, seal.Position.Y
-- Get up to the top storey first. Storey 0 is under the plane about fifteen seconds in — which
-- is itself worth knowing, and is exactly what run 3 above proved.
local highest, hiY = nil, -math.huge
for _, d in vault:GetDescendants() do
	if string.match(tostring(d.Name), "^Gem_") and d.Position.Y > hiY then
		highest, hiY = d, d.Position.Y
	end
end
walkTo(highest.Position)
h:advance(30)
truthy(plane.Position.Y > planeY0 + 10,
	string.format("the collapse plane actually rose (%.1f -> %.1f)", planeY0, plane.Position.Y))
truthy(seal.Position.Y < sealY0 - 3,
	string.format("and the seal actually descended (%.1f -> %.1f)", sealY0, seal.Position.Y))

-- CONTROL. A change nothing in this file may notice: the collapse plane's COLOUR. If painting it
-- ever breaks an assertion here, this file has started measuring the paint instead of the game.
local paintedBefore = gemsValue.Value
plane.Color = Color3.fromRGB(0, 255, 0)
seal.Transparency = 0.9
h:advance(1)
eq(gemsValue.Value, paintedBefore, "CONTROL: repainting the collapse changes nothing about the run")
truthy(vaults:GetChildren()[1] ~= nil, "CONTROL: and the run is still going")

walkTo(vault:FindFirstChild("ExitPad").Position, function() return #vaults:GetChildren() == 0 end)
truthy(lastRunEvent("end").ok, "CONTROL: a repainted vault still banks a successful escape")

--============================================================================ the stall

-- Clicking a pedestal must BUY, through the same handler the HUD's button uses. The first cut of
-- this server routed the pedestal click through `RemoteEvent:FireServer`, which is a CLIENT call
-- and does nothing on the server: every pedestal in the stall was inert.
local before2 = gemsValue.Value
local ped = nil
for _, d in hub:GetDescendants() do
	if tostring(d.Name) == "Pet_coppertail" then ped = d end
end
truthy(ped ~= nil, "the Coppertail pedestal is in the world")
local cd = ped and ped:FindFirstChildOfClass("ClickDetector")
truthy(cd ~= nil, "and it carries a ClickDetector")
if cd then
	cd.MouseClick:Fire(me)
	h:advance(0.5)
	eq(gemsValue.Value, before2 - 150, "clicking the pedestal charged exactly Coppertail's price")
end

local companions = h.workspace:FindFirstChild("Companions")
truthy(companions ~= nil and #companions:GetChildren() > 0,
	"buying a pet put a companion in the world that follows the player")

-- And the pet is worth something: escape again and the payout is multiplied.
Enter:simulateFireServer(me, 1)
h:advance(0.5)
vault = vaults:GetChildren()[1]
local grabbed = 0
for _, d in gemList(vault) do
	if grabbed < 5 then
		walkTo(d.Position)
		grabbed += 1
	end
end
eq(grabbed, 5, "five gems grabbed with the pet equipped")
walkTo(vault:FindFirstChild("ExitPad").Position, function() return #vaults:GetChildren() == 0 end)
local paid = lastRunEvent("end")
-- The carry is read off the END event, not off the last gem event: the walk to the exit passes
-- more gems, so a carry sampled before it is a number that has already moved.
eq(paid.banked, math.floor(paid.carried * 1.05),
	string.format("a 1.05x Coppertail turned %d carried into %d banked", paid.carried, paid.banked))
truthy(paid.carried > 0, "and there was something to multiply")

--============================================================================ leaving

-- A BRAND-NEW player: no DataStore entry at all. The first-run rule is that the core action must
-- be reachable within about five seconds with no hidden prerequisite — so a player who has never
-- played must be able to walk up to a portal and drop straight in, with an empty wallet.
local ghost = h:join("Passerby", 7777)
h:advance(1)
h.Players:simulateSpawn(ghost, h.workspace)
h:advance(1)
local ghostLs = ghost:FindFirstChild("leaderstats")
eq(ghostLs and ghostLs:FindFirstChild("Gems").Value, 0, "a brand-new player starts with nothing")
eq(ghostLs and ghostLs:FindFirstChild("Banked").Value, 0, "and has banked nothing")

local portal = nil
for _, d in hub:GetDescendants() do
	if tostring(d.Name) == "Portal_1" then portal = d end
end
truthy(portal ~= nil, "the Bronze portal is in the world")
local portalClick = portal and portal:FindFirstChildOfClass("ClickDetector")
truthy(portalClick ~= nil, "and it carries a ClickDetector")
portalClick.MouseClick:Fire(ghost)
h:advance(0.5)
eq(#vaults:GetChildren(), 1, "one click on the portal drops a first-time player straight in")
h:leave(ghost)
h:advance(1)
eq(#vaults:GetChildren(), 0, "and leaving mid-run destroys it — the slot cannot leak")

--============================================================================ REJECTED REMOTES DO NOT WRITE

-- Roblox throttles writes to a single key to roughly one every six seconds, with a queue about
-- thirty deep before it starts erroring, and flush() pcalls and warns — so the failure is silent
-- and what the player loses is their progress. Every rejected Buy and Equip used to fall through
-- its failure branch straight into flush(): tapping down the eight-pet list to compare
-- multipliers was one UpdateAsync per tap, and a client firing EquipEvent in a loop could take
-- its own save path down.
--
-- The counter is the emulator's own DataStore __calls, incremented per API call in
-- robloxemu/emu/services.luau — asking the store, not the server, so a server that "decided not
-- to write" but wrote anyway is caught.
do
	Enter:simulateFireServer(me, 1)   -- park the player in a vault first? no: buy/equip in the hub
	h:advance(0.2)
	if #vaults:GetChildren() > 0 then
		hrp.CFrame = CFrame.new(vaults:GetChildren()[1]:FindFirstChild("ExitPad").Position)
		h:advance(0.5)
	end
	h:advance(1)

	local Buy = remotes:FindFirstChild("Buy")
	local Equip = remotes:FindFirstChild("Equip")

	-- Drain first. Walking to the exit banked a run a moment ago, so a write is already pending;
	-- a flush tick landing inside one of the bursts below would be counted as if the burst caused
	-- it. This is also the assertion that the drain worked.
	h:advance(Config.Save.FlushTickSeconds * 2 + 1)
	local settled = store.__calls
	h:advance(Config.Save.FlushTickSeconds * 2 + 1)
	eq(store.__calls, settled, "the save queue is empty before the bursts are measured")

	-- Fire the burst, then let a WHOLE flush tick go by. Measuring only the burst would prove the
	-- coalescing and nothing else: the remote handlers do not write, they mark the profile
	-- pending, so a window shorter than a tick reads zero whether or not anything changed. It is
	-- the tick afterwards that asks the real question — did those requests leave anything to
	-- save? Deleting flush()'s fingerprint check survived this file until this line grew its
	-- `advance`.
	local function callsAround(n, fire)
		local before = store.__calls
		for _ = 1, n do fire() end
		h:advance(Config.Save.FlushTickSeconds * 2 + 1)
		return store.__calls - before
	end

	-- 1. equipping a pet the player does not own
	local a = callsAround(60, function() Equip:simulateFireServer(me, "crownwyrm") end)
	eq(a, 0, "60 REFUSED equips (pet not owned) wrote " .. a .. " times to the DataStore")

	-- 2. buying a pet the player cannot afford
	local b = callsAround(60, function() Buy:simulateFireServer(me, "crownwyrm") end)
	eq(b, 0, "60 REFUSED buys (12000 gems, wallet nowhere near) wrote " .. b .. " times")

	-- 3. an id that does not exist at all
	local c = callsAround(60, function() Equip:simulateFireServer(me, "not_a_pet") end)
	eq(c, 0, "60 equips of a pet that does not exist wrote " .. c .. " times")

	-- 4. ...and requests that DO change the profile every single time. A "did anything change"
	-- test alone would let a client fire EquipEvent in a loop between two pets it owns and drive
	-- the write rate itself, so the remote path is coalesced onto Config.Save.FlushTickSeconds.
	-- Buying Gearmoth first is a real change, and pays for the alternation below.
	Buy:simulateFireServer(me, "gearmoth")
	h:advance(Config.Save.FlushTickSeconds + 1)
	local f = callsAround(60, function()
		Equip:simulateFireServer(me, "coppertail")
		Equip:simulateFireServer(me, "gearmoth")
	end)
	-- CONTROL, and the same number: exactly ONE. More than one and a client sets the write rate;
	-- zero and the save path has simply stopped working, which would satisfy every assertion
	-- above just as well.
	eq(f, 1, "120 alternating REAL equips cost exactly one DataStore call, not 120 and not none")

	-- ...and a tick with nothing pending writes nothing at all. The 45-second autosave this
	-- replaced wrote every profile on every pass whether or not anything had moved.
	local idleBefore = store.__calls
	h:advance(Config.Save.FlushTickSeconds * 2 + 1)
	eq(store.__calls - idleBefore, 0, "an idle player costs the DataStore nothing")
end

--============================================================================ no body, no run

-- Players.RespawnTime is 5 seconds and Reset is how a stuck player gets unstuck, so
-- `plr.Character == nil` is a window every player passes through several times a session. A run
-- started in that window locks the player out for the whole countdown: the server builds a vault
-- they are not in, refuses every further tap with "You are already inside a vault", and finishes
-- by charging them a permanent wipe for a run they never took. The teleport INTO the vault was
-- guarded; the run, the build, the slot claim and the countdown were not.
--
-- This is exactly the respawn window: joined, never spawned.
do
	local bodyless = h:join("Respawning", 9191)
	h:advance(1)
	truthy(bodyless.Character == nil, "the test player genuinely has no character")

	local vaultsBefore = #vaults:GetChildren()
	local toastsBefore = #Toast:getSent()
	Enter:simulateFireServer(bodyless, 1)
	h:advance(1)

	eq(#vaults:GetChildren(), vaultsBefore, "a player with no body builds no vault")
	local told = Toast:getSent()
	truthy(#told > toastsBefore, "and is told why rather than being silently ignored")

	-- ...and the refusal must not have STARTED anything: no run event, and the player can enter
	-- normally the moment they respawn. A lockout that expires on its own is still a lockout.
	local started = false
	for _, e in ipairs(RunRemote:getSent()) do
		if e.player == bodyless and e.args[1] == "start" then started = true end
	end
	falsy(started, "the HUD was never told a run started")

	h.Players:simulateSpawn(bodyless, h.workspace)
	h:advance(1)
	Enter:simulateFireServer(bodyless, 1)
	h:advance(0.5)
	eq(#vaults:GetChildren(), vaultsBefore + 1, "and once they have a body they drop straight in")
	h:leave(bodyless)
	h:advance(1)
	eq(#vaults:GetChildren(), vaultsBefore, "...and leaving tears it down again")
end

--============================================================================ POSITION IS NOT PROOF

-- In Roblox the CLIENT owns its own character's physics, so `hrp.Position` on the server is
-- whatever the client says it is. The entire economy of this game is one number — gems banked —
-- and both the gem pickup and the escape were plain distance tests against that claim, with no
-- displacement sanity check anywhere in the run loop. Writing the root part straight onto the
-- ExitPad banked the full carry with no traversal at all, which is also what every earlier
-- assertion in this file did to prove an escape.
--
-- The server now keeps its OWN trusted position and every rule reads that instead. A claim the
-- runner could not physically have reached yet does not become true by being made.
do
	Enter:simulateFireServer(me, 1)
	h:advance(0.5)
	local v = vaults:GetChildren()[1]
	truthy(v ~= nil, "a fresh run to try to cheat in")
	local pad = v:FindFirstChild("ExitPad")
	local before = gemsValue.Value

	-- Claim to be standing on the exit, on the top storey, one tick after dropping in.
	hrp.CFrame = CFrame.new(pad.Position)
	h:advance(Config.Run.TickSeconds * 3)
	truthy(vaults:GetChildren()[1] ~= nil,
		"teleporting onto the exit pad does NOT end the run on the spot")
	eq(gemsValue.Value, before, "and banks nothing")

	-- ...and the same claim about a gem. Standing on it instantly must not collect it.
	local anyGem = gemList(v)[1]
	local gemsInWorld = countIn(v, function(d) return string.match(tostring(d.Name), "^Gem_") ~= nil end)
	hrp.CFrame = CFrame.new(anyGem.Position)
	h:advance(Config.Run.TickSeconds * 3)
	eq(countIn(v, function(d) return string.match(tostring(d.Name), "^Gem_") ~= nil end),
		gemsInWorld, "and a gem three storeys away is not picked up by claiming to be on it")

	-- CONTROL: the trusted position is a THROTTLE, not a wall. Left alone it walks to where the
	-- runner claims to be, at the speed a runner can walk, and then the rules apply normally. A
	-- guard that simply never lets anybody bank would pass both assertions above.
	hrp.CFrame = CFrame.new(pad.Position)
	h:advance(60)
	local ended = lastRunEvent("end")
	truthy(ended ~= nil and ended.ok,
		"CONTROL: given enough time to actually cover the distance, the escape still banks")
	eq(#vaults:GetChildren(), 0, "CONTROL: and the vault is torn down")
end

--============================================================================ the session lock

-- The soft session lock is what stops two servers writing one profile. It is also the single
-- easiest thing in this file to break silently: the release runs once, on PlayerRemoving, in a
-- transform nobody watches, and a player only ever experiences a failure as "the game would not
-- let me back in for two minutes after I left".
--
-- It had ZERO coverage. The reviewer reverted `old.jobId = if releaseLock then nil else
-- game.JobId` to the `releaseLock and nil or game.JobId` form it was fixed FROM — an and-or that
-- reads as a ternary and is not one, because nil is falsy, so it always evaluates to game.JobId
-- and the lock is never released — and the whole suite stayed green.
--
-- This asserts the STORED RECORD rather than a rejoin, on purpose. The two halves of the lock
-- (jobId and lockUntil) mask each other: loadProfile only refuses when the timestamp is in the
-- future AND the owner is somebody else, so a half-release leaves behind a booby trap that
-- behaves perfectly until the other half moves too. Only reading the record catches it.
do
	local LOCKED = 8484
	local lockMe = h:join("LockTester", LOCKED)
	h:advance(1)
	h.Players:simulateSpawn(lockMe, h.workspace)
	h:advance(1)

	local held = store:GetAsync("u_" .. LOCKED)
	truthy(held ~= nil, "joining wrote a session record")
	truthy(held ~= nil and held.jobId ~= nil, "and stamped this server as the owner")
	truthy(held ~= nil and (tonumber(held.lockUntil) or 0) > os.time(),
		"with a lock that is live while the player is here")

	h:leave(lockMe)
	h:advance(1)
	local released = store:GetAsync("u_" .. LOCKED)
	truthy(released ~= nil, "the record survives the player leaving")
	eq(released and released.jobId, nil, "LEAVING RELEASES THE OWNER STAMP")
	eq(released and tonumber(released.lockUntil), 0, "...and the expiry, both halves of the lock")

	-- ...and the lock is honoured when somebody else really does hold it. Without this the
	-- assertions above are equally satisfied by a lock that is never taken at all.
	store:SetAsync("u_" .. LOCKED, {
		jobId = "some-other-server", lockUntil = os.time() + 600,
		data = { gems = 999, totalBanked = 999, pets = {}, floors = { 1, 1, 1 },
			escapes = 0, wipes = 0 },
	})
	local warnsBefore = #h.warnings
	local blocked = h:join("LockTester", LOCKED)
	h:advance(1)
	h.Players:simulateSpawn(blocked, h.workspace)
	h:advance(1)
	local stillTheirs = store:GetAsync("u_" .. LOCKED)
	eq(stillTheirs and stillTheirs.jobId, "some-other-server",
		"a profile another server holds is NOT stolen")
	truthy(#h.warnings > warnsBefore,
		"and the server says so rather than pretending it saved")
	local blockedToast = nil
	for _, t in ipairs(Toast:getSent()) do
		if t.player == blocked then blockedToast = tostring(t.args[1]) end
	end
	truthy(blockedToast ~= nil and string.find(blockedToast, "saved") ~= nil,
		"the PLAYER is warned their progress will not be saved this session")

	-- ...and a locked-out session must not write on the way out either.
	local callsBefore = store.__calls
	h:leave(blocked)
	h:advance(Config.Save.FlushTickSeconds + 1)
	local after = store:GetAsync("u_" .. LOCKED)
	eq(after and after.jobId, "some-other-server", "leaving does not release a lock we never held")
	eq(after and tonumber(after.data.gems), 999, "nor overwrite the other server's data")
	local _ = callsBefore
end

--============================================================================ done

print("")
-- ONE warning is expected and is asserted for above: the session-lock block deliberately hands
-- the server a profile another server holds, and a server that did NOT warn there would be a
-- server quietly playing without saving. Everything else is a defect. The pattern is narrow on
-- purpose — "no warnings except the ones we caused" is only a gate if the exception is exact.
local EXPECTED_WARNING = "is locked by another server"
local unexpected = 0
for _, w in ipairs(h.warnings) do
	print("warn: " .. tostring(w))
	if string.find(tostring(w), EXPECTED_WARNING, 1, true) == nil then unexpected += 1 end
end
eq(unexpected, 0, "the server ran the whole session with no warning it did not owe the player")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("vault-runners headless: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("vault-runners headless check failed", 0)
end

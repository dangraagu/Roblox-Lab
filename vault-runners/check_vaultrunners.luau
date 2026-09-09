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
		hrp.CFrame = CFrame.new(g.Position)
		h:advance(0.5)
		collected += 1
	end
end
eq(collected, 3, "three gems were walked onto")

local gemsLeft = countIn(vault, function(d) return string.match(tostring(d.Name), "^Gem_") ~= nil end)
eq(gemsLeft, 9, "and those three gems are GONE from the world")
local gemEvent = lastRunEvent("gem")
eq(gemEvent and gemEvent.carried, 12, "the runner is carrying 12 gems' worth (3 x 4)")
eq(gemsValue.Value, 2000, "and NONE of it is banked yet — carrying is not owning")

-- ...and out through the exit, with time to spare.
local exitPad = vault:FindFirstChild("ExitPad")
hrp.CFrame = CFrame.new(exitPad.Position)
h:advance(0.5)

local ended = lastRunEvent("end")
truthy(ended ~= nil and ended.ok, "escaping before the seal is a successful run")
eq(ended and ended.reason, "escaped", "and reads as an escape")
eq(ended and ended.banked, 12, "12 gems banked (no pet equipped, so 1.00x)")
eq(gemsValue.Value, 2012, "the wallet went up by exactly that")
eq(bankedValue.Value, 1512, "and so did the lifetime total")
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
hrp.CFrame = CFrame.new(topGem.Position)
h:advance(0.5)
eq(lastRunEvent("gem").carried, 4, "carrying 4 gems' worth on the top storey")

-- Now do nothing at all for longer than the vault's 70-second countdown.
h:advance(75)

local sealed = lastRunEvent("end")
truthy(sealed ~= nil, "the run ended on its own — a player who stops moving is still resolved")
falsy(sealed and sealed.ok, "and it was NOT a success")
eq(sealed and sealed.reason, "sealed", "the vault sealed with the runner inside")
eq(sealed and sealed.banked, 0, "nothing was banked")
eq(sealed and sealed.carried, 4, "and the 4 gems being carried were lost with it")
eq(gemsValue.Value, before, "THE RULE: the wallet did not move")
eq(#vaults:GetChildren(), 0, "and the sealed vault was torn down")

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
hrp.CFrame = CFrame.new(groundGem.Position)
h:advance(0.5)
local carriedNow = lastRunEvent("gem").carried
local beforeCollapse = gemsValue.Value
h:advance(75)

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
hrp.CFrame = CFrame.new(highest.Position)
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

hrp.CFrame = CFrame.new(vault:FindFirstChild("ExitPad").Position)
h:advance(0.5)
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
		hrp.CFrame = CFrame.new(d.Position)
		h:advance(0.4)
		grabbed += 1
	end
end
eq(grabbed, 5, "five gems grabbed with the pet equipped")
local carried = lastRunEvent("gem").carried
hrp.CFrame = CFrame.new(vault:FindFirstChild("ExitPad").Position)
h:advance(0.5)
local paid = lastRunEvent("end")
eq(paid.banked, math.floor(carried * 1.05),
	string.format("a 1.05x Coppertail turned %d carried into %d banked", carried, paid.banked))

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

--============================================================================ done

print("")
for _, w in ipairs(h.warnings) do print("warn: " .. tostring(w)) end
eq(#h.warnings, 0, "the server ran the whole session without a single warning")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("vault-runners headless: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("vault-runners headless check failed", 0)
end

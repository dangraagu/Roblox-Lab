-- Scrapline Tycoon — which ProximityPrompt a player standing beside a broken machine actually GETS (REVIEW-1 B1).
-- Run:  py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
--       luau check_scraplinetycoon_prompts.luau 2>&1
--
-- robloxemu creates prompts but does not choose between them, and the other checks fire prompt.Triggered directly,
-- so they never saw this: ProximityPrompt.Exclusivity defaults to OnePerButton, and Roblox then shows ONLY THE
-- NEAREST prompt per input button (measured in Studio, fork-tower/STUDIO.md section 2). Each station's console sat
-- 4.51 studs from the spot a player fixes from, the machine 4.53-4.74: pressing E opened the line panel instead of
-- fixing, at 85 of 156 spots along the machines' inner faces (REVIEW-1 B1).
--
-- This file applies Roblox's rule to the prompts the REAL HUD creates on the player's own plot (a prompt's position
-- is its parent part's, as Roblox measures it; the root stands 3 studs over the floor):
--   * keyboard: Enabled prompts within MaxActivationDistance; AlwaysShow always shows; OnePerButton shows the
--     nearest per KeyboardKeyCode (default E); OneGlobally the nearest of those. PASS when the prompts shown on
--     the Fix prompt's key include this machine's Fix (or its broken twin's) and are ALL Fix prompts: the key fixes;
--   * gamepad: the same per GamepadKeyCode (default ButtonX);
--   * touch: Roblox does not document it, so the WORST case (EYECANDY needs-Studio): every OnePerButton prompt
--     competes for one button and only the nearest of them shows. PASS when this machine's Fix is shown (tappable).
-- Spots: within 3 studs along each broken machine's inner and outer face, 0.5 studs off it, every 0.5 studs.
-- Cases: every machine jammed at once, then each station alone with machine a jammed (every other console live).
--
-- One harness per process (robloxemu), so the cases are one player rejoining with a new record. A client's own
-- prompts vanish with it in Roblox; here they are removed by hand between cases, and the earlier HUD instances keep
-- listening (robloxemu fires every OnClientEvent connection): they can only add copies of the same Fix prompts,
-- which this rule treats exactly like the original.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/scrapline-tycoon"), name = "scrapline-tycoon", viewport = { 1280, 720 }, touch = false })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local IDS = { "shredder", "furnace", "press", "cutter", "assembler", "rocketbay" }
local NAMES = { "Shredder", "Furnace", "Press", "Cutter", "Assembler", "RocketBay" }
local UID = 9001
local store = h.services.DataStoreService:GetDataStore("ScraplineTycoon_v1")

assert(h:tryRun("server/Main.server"))
h:advance(1)
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local PlotGeom = h:_require(RS:FindFirstChild("PlotGeom"))
local RunService = h.game:GetService("RunService")
RunService:setIsServer(false)
local AlwaysShow = Enum.ProximityPromptExclusivity.AlwaysShow
local OneGlobally = Enum.ProximityPromptExclusivity.OneGlobally

-- a returning player: every station built and twinned, `jam[t]` machines jammed (0, 1 = machine a, 2 = both)
local function join(jam)
	local st = {}
	for t, id in IDS do st[id] = { n = 2, L = 10, j = jam[t] or 0 } end
	store:SetAsync("u_" .. UID, { data = { v = 1, cash = 10, stations = st, jamIn = 200, tier = 6, bolts = 0, boltsAt = 0, tutorial = 4 } })
	local plr = h:join("Fixer", UID)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.3)
	assert(h:tryRun("client/Hud.client"))
	for _ = 1, 10 do RunService.RenderStepped:Fire(0.1); h:advance(0.1) end
	return plr
end
local function leave(plr)
	local plot = plr.RespawnLocation.Parent
	h:leave(plr)
	h:advance(1)
	for _, d in plot:GetDescendants() do
		if d.ClassName == "ProximityPrompt" then d:Destroy() end
	end
end
local function promptsOn(plot)
	local out = {}
	for _, d in plot:GetDescendants() do
		if d.ClassName == "ProximityPrompt" then
			table.insert(out, { p = d, pos = d.Parent.Position, name = d.Name, owner = d.Parent.Parent.Name })
		end
	end
	return out
end

local function keyOf(p, mode)
	if mode == "keyboard" then return tostring(p.KeyboardKeyCode or Enum.KeyCode.E) end
	if mode == "gamepad" then return tostring(p.GamepadKeyCode or Enum.KeyCode.ButtonX) end
	return "touch"
end

-- the prompts Roblox shows at `pos` for one input mode
local function shownAt(prompts, pos, mode)
	local shown, best, bestGlobal = {}, {}, nil
	for _, e in prompts do
		local p = e.p
		if p.Enabled ~= false and p.Parent ~= nil then
			local d = (pos - e.pos).Magnitude
			if d <= (p.MaxActivationDistance or 10) then
				local ex = p.Exclusivity
				if ex == AlwaysShow then
					table.insert(shown, e)
				elseif ex == OneGlobally then
					if bestGlobal == nil or d < bestGlobal.d then bestGlobal = { e = e, d = d } end
				else
					local key = keyOf(p, mode)
					if best[key] == nil or d < best[key].d then best[key] = { e = e, d = d } end
				end
			end
		end
	end
	for _, b in best do table.insert(shown, b.e) end
	if bestGlobal then table.insert(shown, bestGlobal.e) end
	return shown
end

local function sweep(label, jam)
	local plr = join(jam)
	local plot = plr.RespawnLocation.Parent
	local k = tonumber(string.match(plot.Name, "%d+"))
	local prompts = promptsOn(plot)
	local function isFixOf(e, t, m)
		local want = "Machine_" .. NAMES[t] .. "_" .. (if m then (if m == 1 then "a" else "b") else "")
		return e.name == "FixPrompt" and string.sub(e.owner, 1, #want) == want
	end
	local rootY = Config.World.FloorTopY + 3
	local bad, spots, missing = 0, 0, 0
	local firstBad = nil
	for t = 1, 6 do
		for m = 1, 2 do
			if (jam[t] or 0) >= m then
				local fix = nil
				for _, e in prompts do if isFixOf(e, t, m) then fix = e end end
				if fix == nil then
					missing += 1
				else
					local mx, mz = PlotGeom.machinePos(Config, t, m)
					for _, faceX in { mx - 4.5, mx + 4.5 } do
						for dz = -3, 3, 0.5 do
							local wx, wz = PlotGeom.toWorld(Config, k, faceX, mz + dz)
							local pos = Vector3.new(wx, rootY, wz)
							for _, mode in { "keyboard", "gamepad", "touch" } do
								spots += 1
								local shown = shownAt(prompts, pos, mode)
								local ok, got
								if mode == "touch" then
									-- tappable: this machine's Fix (or its broken twin's) is on screen
									ok = false
									for _, e in shown do if isFixOf(e, t, nil) then ok = true end end
									got = shown
								else
									-- the Fix key does: everything shown on it, which must include this station's Fix and be only Fixes
									local fixKey = keyOf(fix.p, mode)
									local onKey = {}
									for _, e in shown do if keyOf(e.p, mode) == fixKey then table.insert(onKey, e) end end
									local mine = false
									ok = #onKey >= 1
									for _, e in onKey do
										if e.name ~= "FixPrompt" then ok = false end
										if isFixOf(e, t, nil) then mine = true end
									end
									ok = ok and mine
									got = onKey
								end
								if not ok then
									bad += 1
									if firstBad == nil then
										local names = {}
										for _, e in got do table.insert(names, e.name .. "@" .. e.owner) end
										firstBad = string.format("%s %s, %s, local (%.1f, %.1f): %s", NAMES[t], if m == 1 then "a" else "b", mode,
											faceX, mz + dz, if #names > 0 then table.concat(names, " + ") else "nothing")
									end
								end
							end
						end
					end
				end
			end
		end
	end
	print(string.format("  %s: %d prompts on the plot; %d of %d (spot, input) pairs fail%s",
		label, #prompts, bad, spots, if firstBad then " (first: " .. firstBad .. ")" else ""))
	eq(missing, 0, label .. ": every broken machine has its Fix prompt")
	truthy(spots > 0, label .. ": set-up: spots were checked")
	eq(bad, 0, label .. ": beside a broken machine its Fix is what the player's key, button or tap does")
	return plr, prompts
end

--============================================================================ 1. every machine jammed at once
do
	local plr, prompts = sweep("every machine jammed", { 2, 2, 2, 2, 2, 2 })
	-- Fix has its own key and button: it never competes with the consoles' or the board's
	local fixKeys, otherKeys = {}, {}
	for _, e in prompts do
		local t = if e.name == "FixPrompt" then fixKeys else otherKeys
		t["kb " .. tostring(e.p.KeyboardKeyCode or Enum.KeyCode.E)] = true
		t["pad " .. tostring(e.p.GamepadKeyCode or Enum.KeyCode.ButtonX)] = true
	end
	local clash = {}
	for kk in fixKeys do if otherKeys[kk] then table.insert(clash, kk) end end
	eq(#clash, 0, "Fix is on its own keyboard key and gamepad button, never the consoles' or the board's (" .. table.concat(clash, ", ") .. ")")
	leave(plr)
end

--============================================================================ 2. one broken machine, every other console live
for t = 1, 6 do
	local jam = { 0, 0, 0, 0, 0, 0 }
	jam[t] = 1
	local plr = sweep("only the " .. NAMES[t] .. " a jammed", jam)
	leave(plr)
end

--============================================================================ 3. the console of a station in trouble steps aside, and comes back
do
	local plr = join({ 0, 1, 0, 0, 0, 0 })
	local plot = plr.RespawnLocation.Parent
	local k = tonumber(string.match(plot.Name, "%d+"))
	local function consolePrompt(id)
		local c = plot:FindFirstChild("Console_" .. id)
		return c and c:FindFirstChildOfClass("ProximityPrompt")
	end
	truthy(consolePrompt("furnace") ~= nil and consolePrompt("press") ~= nil, "set-up: the HUD made the consoles' prompts")
	eq(consolePrompt("press") and consolePrompt("press").Enabled ~= false, true, "a station with nothing broken keeps its console")
	eq(consolePrompt("furnace") and consolePrompt("furnace").Enabled, false, "the console of a station with a broken machine steps aside (Fix is in reach)")
	-- walk to the furnace and hold the HUD's own Fix prompt
	local mx, mz = PlotGeom.machinePos(Config, 2, 1)
	local wx, wz = PlotGeom.toWorld(Config, k, mx + 4.5, mz)
	local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
	for _ = 1, 60 do
		local p = hrp.Position
		local d = math.sqrt((wx - p.X) ^ 2 + (wz - p.Z) ^ 2)
		if d > 0.5 then
			local step = math.min(d, 1.6)
			hrp.CFrame = CFrame.new(p.X + (wx - p.X) / d * step, Config.World.FloorTopY + 3, p.Z + (wz - p.Z) / d * step)
		end
		RunService.RenderStepped:Fire(0.1)
		h:advance(0.1)
	end
	local fix = nil
	for _, d in plot:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d.Name == "FixPrompt" then fix = d end
	end
	truthy(fix ~= nil, "set-up: the furnace's Fix prompt")
	if fix then
		h:advance(fix.HoldDuration)
		fix.Triggered:Fire(plr)
	end
	for _ = 1, 10 do RunService.RenderStepped:Fire(0.1); h:advance(0.1) end
	local sent = RS.ScraplineRemotes.State:sentTo(plr)
	eq(sent[#sent].args[1].stations[2].jamA, 0, "set-up: the furnace is fixed")
	eq(consolePrompt("furnace") and consolePrompt("furnace").Enabled ~= false, true, "once nothing at the station is broken, its console opens the line again")
	leave(plr)
end

print("")
for _, w in h.warnings do
	print("warning: " .. w)
	failed += 1
end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("scraplinetycoon prompts: %d passed, %d failed", passed, failed))
if failed > 0 then error("scraplinetycoon prompts check failed", 0) end

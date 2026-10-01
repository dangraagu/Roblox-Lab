-- Labyrinth Mariozo — HUD overlap rule 4b, asserted. Run: luau check_labyrintspill_overlap.luau 2>&1
-- Rebuild the bundle first: py -3 wrap.py --game ../labyrint-spill --out build/labyrint-spill.luau
--
-- docs/complete-game-standard.md §2: "the HUD overlap rule 4b asserted (overlap = true in the game's hudcheck), or a
-- written reason why not". emu/hudcheck's own rule 4b cannot be switched on for this game (check_labyrint.luau and
-- check_labyrintspill_hud.luau say why): it counts a ScreenGui with Enabled = false as shown, and it ignores a
-- panel's UISizeConstraint, so it reports the closed LobbyPicker and AssistPanel and a level panel 656 px wide that a
-- player sees 192 px wide. Measured 2026-10-01 with overlap = true: 13 reported overlaps, every one of them one of
-- those two artifacts. emu/ is not this game's to change, so the rule is asserted HERE, with both corrected:
--   * only ScreenGuis a player can see (Enabled ~= false), only panels that are shown (the gate's own `shown`);
--   * a panel's UISizeConstraint applied to its size, re-anchored on its AnchorPoint, as Roblox draws it;
--   * the same panels the gate compares (Frames/ScrollingFrames that are children of a scaling root), on the gate's
--     ten viewports, in every state the standing HUD has: the lobby, a run, a run with the minimap perk, and a run
--     with the minimap and the "Hjelp meg" offer up.
-- It found one real defect on its first run (2026-10-01): LeaderboardClient looked for the minimap's "Kart" frame
-- directly under its ScreenGui, where it has not been since the HUD got a scaling root, so on a tablet or a desktop
-- the records panel (DisplayOrder 9) was laid over a bought minimap (6): 120x120 screen px covered on 1024x768.
-- NOT asserted, on purpose, and measured below instead: the drawers a player opens. The theme shop and the upgrades
-- drawer are drawn OVER the HUD while open, like the LobbyPicker modal (HudClient keeps the level panel above them,
-- DisplayOrder 12 over 10 and 8): on a phone they span the width, so the level panel sits on the middle of their
-- title row; on a desktop the shop covers the records panel until it is closed. The records drawer on a phone opens
-- over the minimap, as LeaderboardClient's own comment says a drawer should. Whether any shop text reaches under the
-- level panel on a real phone is on EYECANDY §8's needs-Studio list (text width is not measurable here).

local Harness = require("./emu/harness")
local VIEWPORTS = require("./emu/hudcheck").VIEWPORTS
local Lib = require("./check_labyrintspill_lib")
local T = Lib.counter("labyrintspill overlap")
local truthy, eq = T.truthy, T.eq

local h = Harness.new({ bundle = require("./build/labyrint-spill"), name = "labyrint-spill", viewport = { 800, 360 }, touch = true })
local today = math.floor(os.time() / 86400)
h.services.DataStoreService:GetDataStore("LabyrintSpill_v1"):SetAsync("p_4242",
	{ coins = 5000, accepted = 30, level = 31, rewardDay = today, perks = { minimap = true } })
assert(h:tryRun("server/MazeGame.server"))
local plr = h:join("Probe", 4242)
h:advance(0.5)
h.Players:simulateSpawn(plr, h.workspace)
h.game:GetService("RunService"):setIsServer(false)
for _, c in Lib.ALL_CLIENTS do
	local ok, err = h:tryRun("client/" .. c .. ".client")
	truthy(ok, c .. " loads (" .. tostring(err) .. ")")
end
h:advance(1)
local RS = h.ReplicatedStorage

-- the panels a player sees, with the two corrections
local function panels(vw, vh)
	for _, gui in plr.PlayerGui:GetChildren() do h:settleLayouts(gui, vw, vh) end
	h:advance(0.05)
	local out = {}
	for _, gui in plr.PlayerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled ~= false then
			for _, r in h:guiRects(gui, vw, vh) do
				local area = r.sw * r.sh
				if r.shown and r.depth == 2 and (r.class == "Frame" or r.class == "ScrollingFrame") and area > 0 and area < vw * vh * 0.98 then
					local sx, sy, sw, sh = r.sx, r.sy, r.sw, r.sh
					local con = r.obj:FindFirstChildOfClass("UISizeConstraint")
					if con and r.w > 0 and r.h > 0 then
						local s = sw / r.w
						local w2 = math.clamp(r.w, con.MinSize.X, con.MaxSize.X)
						local h2 = math.clamp(r.h, con.MinSize.Y, con.MaxSize.Y)
						sx += r.obj.AnchorPoint.X * (sw - w2 * s)
						sy += r.obj.AnchorPoint.Y * (sh - h2 * s)
						sw, sh = w2 * s, h2 * s
					end
					table.insert(out, { name = gui.Name .. "." .. r.obj.Name, sx = sx, sy = sy, sw = sw, sh = sh })
				end
			end
		end
	end
	return out
end
local function overlapOf(a, b)
	local ox = math.min(a.sx + a.sw, b.sx + b.sw) - math.max(a.sx, b.sx)
	local oy = math.min(a.sy + a.sh, b.sy + b.sh) - math.max(a.sy, b.sy)
	if ox > 1 and oy > 1 then return ox, oy end -- a pixel of rounding where two panels are flush is not an overlap
	return nil, nil
end
-- the measurement is not vacuous: two panels that overlap are caught, two flush ones are not
truthy(overlapOf({ sx = 0, sy = 0, sw = 100, sh = 50 }, { sx = 60, sy = 20, sw = 100, sh = 50 }) ~= nil, "self-test: an overlap is detected")
truthy(overlapOf({ sx = 0, sy = 0, sw = 100, sh = 50 }, { sx = 100, sy = 0, sw = 100, sh = 50 }) == nil, "self-test: flush panels are not an overlap")

local function sweep(state, expectPanels)
	local found, measured, maxPanels = {}, 0, 0
	for _, v in VIEWPORTS do
		h:setTouch(v.touch)
		h:setViewport(v.w, v.h)
		h:advance(0.2)
		local ps = panels(v.w, v.h)
		measured += #ps
		maxPanels = math.max(maxPanels, #ps)
		for i = 1, #ps do
			for j = i + 1, #ps do
				local ox, oy = overlapOf(ps[i], ps[j])
				if ox then
					table.insert(found, string.format("%s: %s and %s overlap by %.0fx%.0f screen px", v.name, ps[i].name, ps[j].name, ox, oy))
				end
			end
		end
	end
	print(string.format("  %-34s %d panels measured over %d viewports (up to %d at once), %d overlaps", state, measured, #VIEWPORTS, maxPanels, #found))
	truthy(maxPanels >= expectPanels, string.format("%s: the panels this state shows were really measured (up to %d at once)", state, maxPanels))
	eq(#found, 0, state .. ": no two visible panels overlap on any viewport" .. (if #found > 0 then " -- " .. found[1] else ""))
	return found
end

local function press(name)
	for _, d in plr.PlayerGui:GetDescendants() do
		if d.Name == name and d:IsA("GuiButton") then
			d.Activated:Fire()
			return true
		end
	end
	return false
end

print("== rule 4b, corrected, on the standing HUD ==")
sweep("the lobby", 1)
RS.LobbyRemotes.StartRun:simulateFireServer(plr, 31, "solo")
h:advance(7) -- past the free-break sign and the biome card
sweep("a run (level 31)", 1)
-- the minimap perk: the server sends PerkData on spawn, before these clients connected; send it again as it does
RS.PerkRemotes.PerkData:FireClient(plr, { coins = 5000, perks = { minimap = true } })
h:advance(0.5)
sweep("a run, with the minimap perk", 1)
-- the "Hjelp meg" offer: three real deaths on this level (the server counts them), then back in
for _ = 1, 3 do
	RS.LobbyRemotes.StartRun:simulateFireServer(plr, 31, "solo")
	h:advance(0.5)
	h.Players:simulateSpawn(plr, h.workspace)
	h:advance(0.5)
end
RS.LobbyRemotes.StartRun:simulateFireServer(plr, 31, "solo")
h:advance(7)
local assistGui = plr.PlayerGui:FindFirstChild("AssistPanel")
truthy(assistGui ~= nil and assistGui.Enabled == true, "set-up: the Hjelp meg offer is up after three deaths")
RS.PerkRemotes.PerkData:FireClient(plr, { coins = 5000, perks = { minimap = true } })
h:advance(0.5)
sweep("a run, minimap + the Hjelp meg offer", 3)

print("== measured, not asserted: the player-opened drawers (drawn over the HUD while open) ==")
for _, t in { "RekordKnapp", "ButikkKnapp", "PerkKnapp" } do
	truthy(press(t), t .. " exists")
	h:advance(0.3)
	local worst, n = nil, 0
	for _, v in VIEWPORTS do
		h:setTouch(v.touch)
		h:setViewport(v.w, v.h)
		h:advance(0.2)
		local ps = panels(v.w, v.h)
		for i = 1, #ps do
			for j = i + 1, #ps do
				local ox, oy = overlapOf(ps[i], ps[j])
				if ox then
					n += 1
					worst = worst or string.format("%s: %s over %s, %.0fx%.0f", v.name, ps[j].name, ps[i].name, ox, oy)
				end
			end
		end
	end
	print(string.format("  %-12s open: %d overlaps over %d viewports%s", t, n, #VIEWPORTS, if worst then " (e.g. " .. worst .. ")" else ""))
	press(t)
	h:advance(0.3)
end

T.finish(h)

-- Grow a Crystal — the Grotto row (band chip + Relax button) and its title card never cover the HUD.
-- Run: luau check_growacrystal_row.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- emu/hudcheck.luau measures panel-versus-panel overlap for Frames only, so a label or a button that
-- lands on an open drawer passes it. The Grotto row is exactly a label and a button, placed under the
-- HUD's header in the column between the side panels. This measures every visible HUD element (panels,
-- the dust readout, the hint, the toast line, the drawer toggles) against the chip and the button at the
-- same ten viewports hudcheck uses, with each drawer open in turn on the compact ones, in screen px.

local Harness = require("./emu/harness")
local HudCheck = require("./emu/hudcheck")

local passed, failed = 0, 0
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({
	bundle = require("./build/grow-a-crystal"),
	name = "grow-a-crystal",
	viewport = { 800, 360 },
	touch = true,
})
assert(h:tryRun("server/Main.server"))
local player = h:join("RowTester", 5551313)
h:advance(1)
assert(h:tryRun("client/Hud.client"))
assert(h:tryRun("client/Grotto.client"))
local State = h.ReplicatedStorage:FindFirstChild("CrystalRemotes"):FindFirstChild("State")
local rec = State:sentTo(player)[#State:sentTo(player)]
State.OnClientEvent:Fire(table.unpack(rec.args, 1, rec.args.n))
-- a toast line with text, as a "not enough dust" message would put there
local hudRoot = player.PlayerGui.CrystalHud.Root
local RunService = h.game:GetService("RunService")
local function frames(n)
	for _ = 1, n do
		RunService.RenderStepped:Fire(1 / 30)
		h:advance(1 / 30)
	end
end
frames(5)

local function openOnly(key)
	local toggles = hudRoot:FindFirstChild("Toggles")
	local label = ({ seeds = "Seeds", code = "Code", board = "Top" })[key]
	for _, b in toggles:GetChildren() do
		if b.ClassName == "TextButton" and string.find(b.Text, label, 1, true) then
			if b.BackgroundColor3 ~= Color3.fromRGB(70, 150, 90) then b.Activated:Fire() end
		end
	end
	h:advance(0.1)
end
local function closeAll()
	local toggles = hudRoot:FindFirstChild("Toggles")
	for _, b in toggles:GetChildren() do
		if b.ClassName == "TextButton" and b.BackgroundColor3 == Color3.fromRGB(70, 150, 90) then b.Activated:Fire() end
	end
	h:advance(0.1)
end

local function overlap(a, b)
	local ox = math.min(a.sx + a.sw, b.sx + b.sw) - math.max(a.sx, b.sx)
	local oy = math.min(a.sy + a.sh, b.sy + b.sh) - math.max(a.sy, b.sy)
	return ox > 1 and oy > 1, ox, oy
end

local measured = 0
local function measure(label, vw, vh)
	for _, g in player.PlayerGui:GetChildren() do h:settleLayouts(g, vw, vh) end
	h:advance(0.05)
	local hud, mine = {}, {}
	for _, r in h:guiRects(player.PlayerGui.CrystalHud, vw, vh) do
		-- depth 2: the HUD's own furniture (panels, dust readout, hint, toast, toggle bar)
		if r.shown and r.depth == 2 and r.sw > 0 and r.sh > 0 then table.insert(hud, r) end
	end
	for _, r in h:guiRects(player.PlayerGui.CrystalGrotto, vw, vh) do
		if r.shown and r.depth == 2 and (r.name == "BandChip" or r.name == "RelaxButton") then table.insert(mine, r) end
	end
	truthy(#mine == 2, label .. ": the chip and the Relax button are both on screen")
	for _, m in mine do
		truthy(m.sx >= 0 and m.sy >= 0 and m.sx + m.sw <= vw + 1 and m.sy + m.sh <= vh + 1,
			string.format("%s: %s is on screen (x %.0f..%.0f, y %.0f..%.0f)", label, m.name, m.sx, m.sx + m.sw, m.sy, m.sy + m.sh))
		for _, o in hud do
			-- the hint and the toast are full-width lines of centred text; only their text box counts
			local hit, ox, oy = overlap(m, o)
			truthy(not hit, string.format("%s: %s does not cover the HUD's %s (%s) (overlap %.0fx%.0f)", label, m.name,
				o.name, o.class, hit and ox or 0, hit and oy or 0))
		end
		measured += 1
	end
	-- the two do not cover each other either
	local hit = overlap(mine[1], mine[2])
	truthy(not hit, label .. ": the chip and the button do not overlap")
end

for _, v in HudCheck.VIEWPORTS do
	h:setTouch(v.touch)
	h:setViewport(v.w, v.h)
	h:advance(0.1)
	closeAll()
	frames(2)
	measure(v.name, v.w, v.h)
	if v.w < 900 or v.h < 500 then
		for _, key in { "seeds", "code", "board" } do
			openOnly(key)
			frames(2)
			measure(v.name .. ", " .. key .. " open", v.w, v.h)
			closeAll()
		end
	end
end

print(string.format("  %d element placements measured against the HUD", measured))
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
truthy(#h.warnings == 0, "no warnings")
print(string.format("growacrystal row: %d passed, %d failed", passed, failed))
if failed > 0 then error("growacrystal row check failed", 0) end

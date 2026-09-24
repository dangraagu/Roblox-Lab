-- Grow a Crystal — HUD fit with the Grotto client's row (chip + Relax button + title card) on screen.
-- Run: luau check_growacrystal_hud.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../grow-a-crystal --out build/grow-a-crystal.luau
--
-- check_crystal.luau (not this session's file) runs the gate on Hud.client alone. This runs the SAME gate
-- with Grotto.client loaded too, panel overlap ON, over the standard viewports plus every phone viewport
-- again with each drawer open, so a new tap target (Relax) is held to the 44-px and control-band rules
-- and the HUD it sits next to is measured in every mode. The chip/button-versus-panel overlap, which this
-- gate does not measure for labels and buttons, is check_growacrystal_row.luau.

local HudCheck = require("./emu/hudcheck")

local function hudRoot(player)
	local gui = player.PlayerGui:FindFirstChild("CrystalHud")
	return gui and gui:FindFirstChild("Root")
end

local function drawer(key)
	local panelName = ({ seeds = "SeedPanel" })[key]
	return function(h, player)
		local root = hudRoot(player)
		local toggles = root and root:FindFirstChild("Toggles")
		assert(toggles ~= nil, "no toggle bar")
		local label = ({ seeds = "Seeds", code = "Code", board = "Top" })[key]
		local btn = nil
		for _, b in toggles:GetChildren() do
			if b.ClassName == "TextButton" and string.find(b.Text, label, 1, true) then btn = b end
		end
		assert(btn ~= nil, "no toggle for " .. key)
		-- open exactly this drawer: the HUD toggles, so fire only when it is not already the open one
		local open = btn.BackgroundColor3 == Color3.fromRGB(70, 150, 90)
		if not open then btn.Activated:Fire() end
		h:advance(0.1)
		if panelName then
			local p = root:FindFirstChild(panelName)
			assert(p ~= nil and p.Visible, key .. " drawer did not open")
		end
	end
end

local viewports = {}
for _, v in HudCheck.VIEWPORTS do
	table.insert(viewports, v)
end
for _, base in { { name = "phone landscape", w = 800, h = 360, touch = true }, { name = "small phone", w = 640, h = 300, touch = true },
	{ name = "phone portrait", w = 414, h = 800, touch = true }, { name = "small mouse window", w = 800, h = 600, touch = false } } do
	for _, key in { "seeds", "code", "board" } do
		table.insert(viewports, { name = base.name .. ", " .. key .. " open", w = base.w, h = base.h, touch = base.touch, before = drawer(key) })
	end
end

HudCheck.run({
	overlap = true,
	game = "grow-a-crystal",
	bundle = require("./build/grow-a-crystal"),
	server = "server/Main.server",
	clients = { "client/Hud.client", "client/Grotto.client" },
	viewports = viewports,
	-- the first State push reached nobody (it was sent before the clients loaded); re-send it so the HUD
	-- and the Grotto row show real text, and the first title card is on screen while it is measured
	warmup = function(h, player)
		local State = h.ReplicatedStorage:FindFirstChild("CrystalRemotes"):FindFirstChild("State")
		local sent = State:sentTo(player)
		local rec = sent[#sent]
		assert(rec ~= nil, "no State push was sent to the player")
		State.OnClientEvent:Fire(table.unpack(rec.args, 1, rec.args.n))
		local RunService = h.game:GetService("RunService")
		-- 1.5 s: the first card waits for the chamber count to hold still for a second (Grotto.client)
		for _ = 1, 45 do
			RunService.RenderStepped:Fire(1 / 30)
			h:advance(1 / 30)
		end
		local card = player.PlayerGui.CrystalGrotto.Root.BandCard
		assert(card.Visible, "the first title card should be up while the HUD is measured")
	end,
})

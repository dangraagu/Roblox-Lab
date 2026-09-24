-- Labyrinth Mariozo — where the eye-candy text sits on screen, measured with every label SHOWN.
-- Run: luau check_labyrintspill_layout.luau   (rebuild the bundle first, see check_labyrint.luau)
--
-- The stock gate (check_labyrintspill_hud.luau) cannot see a label that starts hidden, and all four of
-- these do: the biome card and its subtitle, the hazard banner, the rest toast. Here each is shown with
-- the LONGEST text it can carry, at every viewport emu/hudcheck knows, over the live HUD, and must be
-- fully on screen, clear of Roblox's touch controls, and clear of every button and the level panel.

local Lib = require("./check_labyrintspill_lib")
local HudCheck = require("./emu/hudcheck")
local T = Lib.counter("labyrintspill layout")
local truthy, eq = T.truthy, T.eq

local ctx = Lib.boot({ accepted = 400, clients = Lib.ALL_CLIENTS })
local h = ctx.h
eq(#ctx.loadErrors, 0, "all 13 clients load (" .. table.concat(ctx.loadErrors, "; ") .. ")")
local Biomes = h:_require(h.ReplicatedStorage:FindFirstChild("Biomes"))
ctx.startRun(380)
ctx.run(1)

local pg = ctx.plr.PlayerGui
local bio = pg.LabyrintBiome.Root
local rest = pg.LabyrintBreak.Root
local labels = { bio.BandCard, bio.BandCardSub, bio.HazardBanner, rest.RestToast }

-- the longest texts each label can carry
local longestTitle, longestSub, longestBanner = "", "", ""
for i, b in Biomes.Bands do
	local t = b.emoji .. " YOU REACHED THE " .. string.upper(b.name) .. "!"
	if #t > #longestTitle then longestTitle = t end
	local nb = Biomes.Bands[i + 1]
	local range = if nb then string.format("Levels %d-%d", math.max(1, b.from), nb.from - 1) else string.format("Level %d and beyond", b.from)
	if b.hazard then
		local s = range .. "  ·  " .. Biomes.hazardIntro(b.hazard) -- (review fix) the texts the client shows, not a copy
		if #s > #longestSub then longestSub = s end
		local bn = Biomes.hazardBanner(b.hazard)
		if #bn > #longestBanner then longestBanner = bn end
	end
end

local function overlaps(a, b)
	return a.sx < b.sx + b.sw - 1 and b.sx < a.sx + a.sw - 1 and a.sy < b.sy + b.sh - 1 and b.sy < a.sy + a.sh - 1
end

local checked = 0
for _, v in HudCheck.VIEWPORTS do
	h:setTouch(v.touch)
	h:setViewport(v.w, v.h)
	h:advance(0.3)
	-- show everything (the card and the banner never show together in the game; they share a slot)
	for _, pass in { "card", "banner", "toast" } do
		bio.BandCard.Visible = pass == "card"
		bio.BandCardSub.Visible = pass == "card"
		bio.HazardBanner.Visible = pass == "banner"
		rest.RestToast.Visible = pass == "toast"
		bio.BandCard.Text = longestTitle
		bio.BandCardSub.Text = longestSub
		bio.HazardBanner.Text = longestBanner
		-- everything else on screen, and ours
		local others, mine = {}, {}
		for _, g in pg:GetChildren() do
			if g.ClassName == "ScreenGui" and g.Enabled ~= false then
				for _, r in h:guiRects(g, v.w, v.h) do
					if r.shown and r.sw > 0 and r.sh > 0 then
						local isMine = false
						for _, l in labels do if r.obj == l then isMine = true end end
						if isMine then
							table.insert(mine, r)
						elseif r.class == "TextButton" or r.class == "ImageButton" or r.class == "TextBox" or r.name == "NivaaPanel" then
							table.insert(others, r)
						end
					end
				end
			end
		end
		for _, r in mine do
			checked += 1
			local tag = string.format("[%s %dx%d] %s", v.name, v.w, v.h, r.name)
			truthy(r.sx >= -0.5 and r.sy >= -0.5 and r.sx + r.sw <= v.w + 0.5 and r.sy + r.sh <= v.h + 0.5,
				tag .. string.format(" is fully on screen (x %.0f..%.0f y %.0f..%.0f)", r.sx, r.sx + r.sw, r.sy, r.sy + r.sh))
			truthy(r.sy + r.sh <= v.h * 0.6, tag .. " stays in the upper part of the screen, far from the touch controls")
			for _, o in others do
				truthy(not overlaps(r, o), string.format("%s does not cover %s (%s)", tag, o.name, o.class))
			end
			truthy(r.obj.Active == false, tag .. " never takes a touch")
		end
	end
end
truthy(checked >= #HudCheck.VIEWPORTS * 4, "every label measured at every viewport (" .. checked .. ")")
T.finish(h)

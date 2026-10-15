-- Scrapline Tycoon — can a player READ the Top Recyclers board, and do they always find their own row there?
-- (REVIEW-2 R1, R2.) Through the real server and the owner's real HUD, on a phone (800 x 360, touch).
-- Run:  py -3 wrap.py --game ../scrapline-tycoon --out build/scrapline-tycoon.luau
--       luau check_scraplinetycoon_boardview.luau 2>&1
--
--   1. R2: ten factories with 2-11 Gold Bolts and the viewer with 1. The server sends the top 10 plus the viewer's
--      own row; the board used to draw only the first 10 rows, so a viewer outside the top 10 never saw themselves.
--      The same in the friends view, which can send up to 201 rows.
--   2. R1: the size of one row, from the BUILT face and the rows the HUD actually laid out on it, projected the way a
--      phone camera sees it (a pinhole camera, vertical field of view 70 degrees, Roblox's default; 360 px tall).
--      Measured where a player reads it: standing 5 studs in front of it, inside its prompt, with Roblox's default
--      follow camera 12.5 studs behind the head (the reviewer's model); and in first person from the arrival pad. The
--      bar is the HUD's own hint text on the same phone. Geometry, not a render: EYECANDY.md's needs-Studio list has
--      the real look.

local Harness = require("./emu/harness")
local h = Harness.new({ bundle = require("./build/scrapline-tycoon"), name = "scrapline-tycoon", viewport = { 800, 360 }, touch = true })

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local S = 2e9
local function enc(b, t) return b * S + (S - t) end
local T = os.time()
local ME = 4242
local store = h.services.DataStoreService:GetDataStore("ScraplineTycoon_v1")
local board = h.services.DataStoreService:GetOrderedDataStore("ScraplineTycoon_Board_v1")
for i = 1, 10 do board:SetAsync("u_" .. (100 + i), enc(1 + i, T - 5000 + i)) end -- ten factories with 2..11 bolts
board:SetAsync("u_" .. ME, enc(1, T - 100))
store:SetAsync("u_" .. ME, { data = { v = 1, cash = 10, stations = { shredder = { n = 1, L = 3, j = 0 } }, jamIn = 200, tier = 1,
	bolts = 1, boltsAt = T - 100, tutorial = 4 } })

assert(h:tryRun("server/Main.server"))
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local BoardR = RS.ScraplineRemotes.Board
h.game:GetService("RunService"):setIsServer(false)
local me = h:join("Nova", ME)
h.Players:simulateSpawn(me, h.workspace)
h:advance(0.5)
assert(h:tryRun("client/Hud.client"))
h:advance(31) -- the first send went out at load, before this HUD listened; it re-sends every 30 s

local plot = me.RespawnLocation.Parent
local face = plot.Board.BoardFace
local function surface()
	local f = me.PlayerGui:FindFirstChild("BoardGuis")
	return f and f:FindFirstChild("TopRecyclers")
end
local function drawn()
	local sg = surface()
	local out = {}
	if sg == nil then return out end
	for _, r in sg.Background.Rows:GetChildren() do
		if r:IsA("TextLabel") and r.Visible ~= false then table.insert(out, r) end
	end
	table.sort(out, function(a, b) return a.Position.Y.Scale < b.Position.Y.Scale end)
	return out
end
local function lastPayload()
	local sent = BoardR:sentTo(me)
	return sent[#sent].args[1]
end

--============================================================================ 1. the viewer's own row is always drawn (R2)
do
	local p = lastPayload()
	local rows = drawn()
	local mine = nil
	for _, r in rows do if string.find(r.Text, "Nova", 1, true) then mine = r end end
	print(string.format("  public: the server sent %d rows; the board draws %d; the viewer's own row: %s", #p.rows, #rows, mine and mine.Text or "MISSING"))
	eq(#p.rows, 11, "set-up: the server sends the top 10 and the viewer's own row (rank 11)")
	truthy(mine ~= nil, "REVIEW-2 R2: a viewer outside the top 10 sees their own row on the public board")
	eq(#rows, 11, "...and all ten of the top 10 are still drawn with it")
	local top = rows[1] and rows[1].Text or ""
	truthy(string.find(top, "1. User_110", 1, true) ~= nil, "the first drawn row is the best factory: " .. top)
	local last = rows[#rows]
	truthy(last ~= nil and last == mine, "the viewer's row comes last, under the top 10")
	-- the friends view: twelve friends ahead of the viewer (the same 10 factories and two more)
	local ids = {}
	for i = 1, 12 do table.insert(ids, { Id = 100 + i }) end
	board:SetAsync("u_111", enc(12, T - 4000))
	board:SetAsync("u_112", enc(13, T - 3900))
	h.Players.GetFriendsAsync = function() return { IsFinished = true, GetCurrentPage = function() return ids end, AdvanceToNextPageAsync = function() end } end
	h:advance(Config.Board.FriendListRetrySeconds + 1)
	local prompt = face:FindFirstChildOfClass("ProximityPrompt")
	prompt.Triggered:Fire(me)
	h:advance(16) -- twelve reads at one a second
	local f = lastPayload()
	rows = drawn()
	mine = nil
	for _, r in rows do if string.find(r.Text, "Nova", 1, true) then mine = r end end
	print(string.format("  friends: the server sent %d rows (status '%s'); the board draws %d; the viewer's own row: %s",
		#f.rows, tostring(f.status), #rows, mine and mine.Text or "MISSING"))
	eq(f.mode, "friends", "set-up: the friends view")
	eq(#f.rows, 13, "set-up: twelve friends and the viewer")
	truthy(mine ~= nil, "REVIEW-2 R2: a viewer behind ten friends still sees their own row on the friends board")
	truthy(#rows <= 11, "...and the board never draws more rows than it has room for (" .. #rows .. ")")
	local outside = 0
	for _, r in rows do
		if r.Position.Y.Scale < -1e-9 or r.Position.Y.Scale + r.Size.Y.Scale > 1 + 1e-9 then outside += 1 end
	end
	eq(outside, 0, "every drawn row lies inside the rows frame, the viewer's own included")
end

--============================================================================ 2. one row is big enough to read on a phone (R1)
do
	local sg = surface()
	local rowsFrame = sg.Background.Rows
	local rows = drawn()
	local rowScale = rows[1].Size.Y.Scale
	local rowStuds = face.Size.Y * rowsFrame.Size.Y.Scale * rowScale
	local tanHalf = math.tan(math.rad(70 / 2))
	local function px(dist) return rowStuds / (2 * dist * tanHalf) * 360 end
	-- the face's normal (Front = LookVector) points at the arrival pad
	local pad = me.RespawnLocation
	local n = face.CFrame.LookVector
	local toPad = Vector3.new(pad.Position.X - face.Position.X, 0, pad.Position.Z - face.Position.Z)
	local dot = (n.X * toPad.X + n.Z * toPad.Z) / toPad.Magnitude
	truthy(dot > 0.99, string.format("the board's face looks at the arrival pad (%.3f)", dot))
	local headY = pad.Position.Y + pad.Size.Y / 2 + 2.5 + 1.5
	local flatN = Vector3.new(n.X, 0, n.Z).Unit
	-- reading it: 5 studs in front, default camera 12.5 studs behind the head
	local head = Vector3.new(face.Position.X, headY, face.Position.Z) + flatN * 5
	local cam = head + flatN * 12.5
	local dRead = (cam - face.Position).Magnitude
	-- first person on the arrival pad, and the default camera from the pad (it looks up the U, +Z of the plot)
	local headPad = Vector3.new(pad.Position.X, headY, pad.Position.Z)
	local dPad = (headPad - face.Position).Magnitude
	local back = -pad.CFrame.LookVector
	local camPad = headPad + Vector3.new(back.X, 0, back.Z).Unit * 12.5
	local dPadCam = (camPad - face.Position).Magnitude
	local prompt = face:FindFirstChildOfClass("ProximityPrompt")
	print(string.format("  the face is %.2f x %.2f studs; one row is %.3f studs (was 0.229)", face.Size.X, face.Size.Y, rowStuds))
	print(string.format("  one row on an 800 x 360 phone: %.1f px reading it (camera %.1f studs off), %.1f px first person from the pad (%.1f), %.1f px default camera from the pad (%.1f)",
		px(dRead), dRead, px(dPad), dPad, px(dPadCam), dPadCam))
	truthy((head - face.Position).Magnitude <= prompt.MaxActivationDistance, "the reading spot is inside the board's prompt")
	-- the bar: the HUD's own hint and toast text on this phone (MaxTextSize 16 design px x the UIScale), measured
	local hud = me.PlayerGui.ScraplineHud.Root
	local hintPx = hud.HintPanel.HintText:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize * hud:FindFirstChildOfClass("UIScale").Scale
	print(string.format("  the bar: the HUD's own hint text is %.1f px on this phone", hintPx))
	truthy(px(dRead) >= hintPx, string.format("REVIEW-2 R1: reading the board at the default camera, one row is as tall as the HUD's hint text (%.1f >= %.1f px)", px(dRead), hintPx))
	truthy(px(dPad) >= 1.5 * hintPx, string.format("REVIEW-2 R1: in first person from the arrival pad, half again as tall (%.1f >= %.1f px)", px(dPad), 1.5 * hintPx))
	-- the text fits its row: with TextScaled, Roblox shrinks a long line to the row's width, never past it
	for _, r in rows do
		truthy(r.TextScaled == true, "row text is scaled to its row: " .. r.Name)
	end
	-- the board must not hide the first job: the Shredder's machine stays clear of it
	local shredderSide = plot:FindFirstChild("ChuteBody")
	local fx, fz = face.Position.X - plot.Arrival.Position.X, face.Position.Z - plot.Arrival.Position.Z
	local cx, cz = shredderSide.Position.X - plot.Arrival.Position.X, shredderSide.Position.Z - plot.Arrival.Position.Z
	truthy(fx * cx + fz * cz < 0, "the board stands on the far side of the arrival from the chute and the Shredder")
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
print(string.format("scraplinetycoon boardview: %d passed, %d failed", passed, failed))
if failed > 0 then error("scraplinetycoon boardview check failed", 0) end

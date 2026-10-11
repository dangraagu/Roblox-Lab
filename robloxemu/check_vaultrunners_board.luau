-- Vault Runners — the highscore board, public + friends, through the REAL server and the real Board.client.
-- Run (from robloxemu): luau check_vaultrunners_board.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau
--
-- docs/complete-game-standard.md §3 (owner, 2026-09-16): rank on a server-measured metric a script cannot
-- inflate, ties to whoever reached it FIRST; OrderedDataStore key u_<userId>, value
-- metric * 2e9 + (2e9 - reachedAtUnix), written only when the metric improves; the public top 10 cached
-- ~60 s; friends via Players:GetFriendsAsync, capped at 200, fetched only on demand, cached, pcall'd and
-- throttle-safe; a physical board near spawn with a ProximityPrompt that toggles Public/Friends; names
-- resolved and cached, never stored; an empty friends board says something useful.
--
-- The metric is the DEEPEST VAULT ESCAPED, counting the escapes the server could trace (owner decision
-- 2026-10-11: VaultEnv.deepestCleared of the saved `traced`, which for an honest runner equals `floors`).
-- The escapes in §3 are real runs on the real server, WALKED: corridor by corridor and pad by pad. They used
-- to claim the exit and wait for the trusted position (Trace) to get there, which is exactly the noclip run
-- the flier gate now keeps off the board (check_vaultrunners_fliergate.luau holds that half).
-- The emulator has no Players:GetFriendsAsync, so this file supplies one (FriendPages-shaped) and counts
-- the calls. Shaped after robloxemu/check_plus1jump_board.luau, the template game's check.

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local h = Harness.new({ bundle = require("./build/vault-runners"), name = "vault-runners", viewport = { 1280, 720 }, touch = false })
local RS = h.ReplicatedStorage
local DSS = h.services.DataStoreService
local Players = h.Players

-- saved profiles, before the server starts
local profilesStore = DSS:GetDataStore("VaultRunners_v1")
local function seed(uid, floors, extra)
	local d = { gems = 0, totalBanked = 0, pets = {}, equipped = nil, floors = floors, escapes = 0, wipes = 0 }
	for k, v in extra or {} do d[k] = v end
	profilesStore:SetAsync("u_" .. uid, { data = d })
end
seed(501, { 13, 1, 1 }, { bestAt = 1780000000 })                        -- Ava: Bronze 12 cleared, depth 12
seed(502, { 13, 1, 1 }, { bestAt = 1770000000 })                        -- Bo: depth 12, reached EARLIER
seed(503, { 30, 1, 1 }, { bestAt = 1785000000, totalBanked = 3000 })     -- Cy: depth 29; Silver open, floor 1 next
seed(504, { 10, 1, 1 })                                                 -- Dee: depth 9, saved before bestAt existed
seed(507, { 3, 1, 1 }, { bestAt = 1760000000 })                          -- Eli: depth 2
seed(509, { 16, 1, 1 }, { bestAt = 1775000000 })                         -- Ned: profile depth 15; board holds 25

assert(h:tryRun("server/Main.server"))
local Config = h:_require(RS:FindFirstChild("Config"))
local Board = h:_require(RS:FindFirstChild("Board"))
local bc = Config.Board
truthy(type(bc) == "table" and type(Board) == "table", "Config.Board and the Board module exist")
if type(bc) ~= "table" or type(Board) ~= "table" then
	print(string.format("vaultrunners board: %d passed, %d failed", passed, failed))
	error("vaultrunners board check failed (no board at all)", 0)
end

local lb = DSS:GetOrderedDataStore(Config.Save.Board)
-- runners who are not in this server, already on the board
lb:SetAsync("u_505", Board.encode(50, 1760000000, bc))
lb:SetAsync("u_508", Board.encode(20, 1765000000, bc))
lb:SetAsync("u_509", Board.encode(25, 1750000000, bc)) -- Ned: a session whose profile write was lost

-- count what the server does to the board's store
local writes, sorted, reads = 0, 0, {}
do
	local oUpdate, oSet, oSorted, oGet = lb.UpdateAsync, lb.SetAsync, lb.GetSortedAsync, lb.GetAsync
	lb.UpdateAsync = function(self, ...) writes += 1; return oUpdate(self, ...) end
	lb.SetAsync = function(self, ...) writes += 1; return oSet(self, ...) end
	lb.GetSortedAsync = function(self, ...) sorted += 1; return oSorted(self, ...) end
	lb.GetAsync = function(self, key, ...) table.insert(reads, key); return oGet(self, key, ...) end
end

-- friends, per user id: a list of { Id, Username } (or "error")
local friendsOf = {
	[501] = { { 502, "Bo" }, { 505, "Eve" }, { 506, "Finn" }, { 508, "Gus" } },
	[510] = {},
	[511] = { { 506, "Finn" } },
	[512] = "error",
}
do
	local big = {}
	for i = 1, 450 do table.insert(big, { 20000 + i, "Pal" .. i }) end
	friendsOf[513] = big
end
local friendCalls, pagesAdvanced = {}, 0
-- every name the server looks up on the web, per user id (the standard: "resolve names with
-- GetNameFromUserIdAsync and cache them")
local nameCalls = {}
do
	-- (the emulator refuses to assign over a method, so the wrapper goes on the instance's own table,
	-- where it shadows the class method for this one Players service)
	local oName = Players.GetNameFromUserIdAsync
	rawset(Players, "GetNameFromUserIdAsync", function(self, userId)
		nameCalls[userId] = (nameCalls[userId] or 0) + 1
		return oName(self, userId)
	end)
end
Players.GetFriendsAsync = function(_self, userId)
	friendCalls[userId] = (friendCalls[userId] or 0) + 1
	local list = friendsOf[userId]
	if list == "error" then error("HTTP 500 (Internal Server Error)", 0) end
	list = list or {}
	local pageNo = 1
	local pages = { IsFinished = #list <= 50 }
	function pages:GetCurrentPage()
		local out = {}
		for i = (pageNo - 1) * 50 + 1, math.min(pageNo * 50, #list) do
			table.insert(out, { Id = list[i][1], Username = list[i][2], DisplayName = list[i][2], IsOnline = false })
		end
		return out
	end
	function pages:AdvanceToNextPageAsync()
		pagesAdvanced += 1
		pageNo += 1
		self.IsFinished = pageNo * 50 >= #list
	end
	return pages
end

--======================================================================= 1. the board in the world

local hub = h.workspace:FindFirstChild("Hub")
local board = hub and hub:FindFirstChild("DeepestBoard")
truthy(board ~= nil and board:IsA("BasePart"), "a physical board stands in the hub (workspace.Hub.DeepestBoard)")
local prompt = board and board:FindFirstChildWhichIsA("ProximityPrompt", true)
truthy(prompt ~= nil, "with a ProximityPrompt")
local spawnPad = hub and hub:FindFirstChild("HubSpawn")
if board and spawnPad then
	truthy(board.Anchored == true, "the board is anchored")
	local d = board.Position - spawnPad.Position
	local flat = math.sqrt(d.X * d.X + d.Z * d.Z)
	truthy(flat <= 20, string.format("near spawn (%.1f studs from the hub spawn)", flat))
	local look = board.CFrame.LookVector
	local toSpawn = Vector3.new(-d.X, 0, -d.Z)
	local cos = (look.X * toSpawn.X + look.Z * toSpawn.Z) / math.max(toSpawn.Magnitude, 1e-6)
	truthy(cos > 0.95, string.format("its front face (where the board is drawn) faces the spawn (cos %.3f)", cos))
	-- NOT IN THE WAY: its footprint, grown by 2 studs, touches none of the hub's own things. The board is
	-- turned, so its footprint is measured as the four corners of its rotated box.
	local corners = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local c = board.CFrame * CFrame.new(sx * board.Size.X / 2, 0, sz * board.Size.Z / 2)
			table.insert(corners, c.Position)
		end
	end
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, c in corners do
		minX, maxX = math.min(minX, c.X), math.max(maxX, c.X)
		minZ, maxZ = math.min(minZ, c.Z), math.max(maxZ, c.Z)
	end
	local clash = nil
	for _, part in hub:GetDescendants() do
		if part:IsA("BasePart") and part ~= board and part.Name ~= "HubPad" and part.Parent == hub then
			local px, pz = part.Size.X / 2 + 2, part.Size.Z / 2 + 2
			if part.Position.X + px > minX and part.Position.X - px < maxX
				and part.Position.Z + pz > minZ and part.Position.Z - pz < maxZ then
				clash = clash or tostring(part.Name)
			end
		end
	end
	truthy(clash == nil, "and it stands clear of every portal, the stall, its pedestals and the spawn" .. (if clash then " (" .. clash .. ")" else ""))
	-- the walk from the spawn to each portal never crosses it
	local blocked = nil
	for i = 1, #Config.Tiers do
		local portal = hub:FindFirstChild("Portal_" .. i)
		if portal then
			for k = 0, 40 do
				local x = portal.Position.X * k / 40
				local z = portal.Position.Z * k / 40
				if x > minX - 1.5 and x < maxX + 1.5 and z > minZ - 1.5 and z < maxZ + 1.5 then blocked = blocked or portal.Name end
			end
		end
	end
	truthy(blocked == nil, "the straight walk from the spawn to every portal passes clear of it" .. (if blocked then " (" .. blocked .. ")" else ""))
	local top = hub:FindFirstChild("HubPad")
	truthy(top ~= nil and math.abs((board.Position.Y - board.Size.Y / 2) - (top.Position.Y + top.Size.Y / 2)) < 0.05,
		"it stands ON the hub floor")
end
if prompt then
	eq(prompt.Enabled, true, "the prompt is enabled")
	eq(prompt.MaxActivationDistance, bc.PromptDistance, "its reach is Config.Board.PromptDistance")
	truthy(#prompt.ActionText > 0, "and it says what it does (" .. prompt.ActionText .. ")")
	eq(prompt.HoldDuration, 0, "a tap, not a hold")
	eq(prompt.RequiresLineOfSight, false, "and a runner beside the sign can always reach it")
	local at = prompt.Parent
	if at and at:IsA("Attachment") and spawnPad then
		-- (the emulator's Attachment has no WorldPosition, so it is composed here, as Roblox does)
		local wp = (at.Parent.CFrame * CFrame.new(at.Position)).Position
		-- the nearest point of the spawn pad's top to the prompt
		local nx = math.clamp(wp.X, spawnPad.Position.X - spawnPad.Size.X / 2, spawnPad.Position.X + spawnPad.Size.X / 2)
		local nz = math.clamp(wp.Z, spawnPad.Position.Z - spawnPad.Size.Z / 2, spawnPad.Position.Z + spawnPad.Size.Z / 2)
		local ny = spawnPad.Position.Y + spawnPad.Size.Y / 2 + 3
		local gap = (Vector3.new(nx, ny, nz) - wp).Magnitude
		truthy(gap > bc.PromptDistance, string.format(
			"standing anywhere on the spawn pad shows no prompt (nearest %.1f studs, reach %d): it pops up when you walk over", gap, bc.PromptDistance))
		local front = board.Position + board.CFrame.LookVector * 4
		truthy((front - wp).Magnitude <= bc.PromptDistance, "and a runner standing 4 studs in front of the sign can use it")
	else
		truthy(false, "the prompt hangs on an Attachment on the board")
	end
end

--======================================================================= 2. the stored value, and ties

h.game:GetService("RunService"):setIsServer(false)
local function joinAs(name, uid)
	local p = h:join(name, uid)
	h.Players:simulateSpawn(p, h.workspace)
	return p
end
local B = joinAs("Bo", 502)
local C = joinAs("Cy", 503)
local D = joinAs("Dee", 504)
local E = joinAs("Eli", 507)
local N = joinAs("Ned", 509)
local joinedAt = os.time()
local A = joinAs("Ava", 501) -- last: the client script below is Ava's
local okClient, errClient = h:tryRun("client/Board.client")
truthy(okClient, "Board.client loads (" .. tostring(errClient) .. ")")
h:advance(1)

local function stored(uid) return lb.__data["u_" .. uid] end
local function decode(v) if type(v) == "number" then return Board.decode(v) end return nil, nil end
eq(stored(501), Board.encode(12, 1780000000, bc), "Ava's saved best (depth 12, reached 1780000000) is on the board, encoded")
eq(stored(502), Board.encode(12, 1770000000, bc), "Bo's too (12, reached EARLIER)")
eq(stored(503), Board.encode(29, 1785000000, bc), "and Cy's (29: Bronze floor 29 is his deepest escape)")
eq(stored(507), Board.encode(2, 1760000000, bc), "and Eli's (2)")
eq(stored(509), Board.encode(25, 1750000000, bc), "Ned's 25 on the board is never lowered to his profile's 15")
do
	local m, t = decode(stored(504))
	eq(m, 9, "a save from before bestAt existed still gets on the board (Dee, 9)")
	truthy(t ~= nil and math.abs(t - joinedAt) <= 5, "stamped with the session it came back in (" .. tostring(t) .. " vs " .. joinedAt .. ")")
end

local remotes = RS:FindFirstChild("VaultRemotes")
local boardRemote = remotes and remotes:FindFirstChild("Board")
truthy(boardRemote ~= nil, "a Board remote exists (server -> client)")
local function lastView(plr)
	if not boardRemote then return nil end
	local sent = boardRemote:sentTo(plr)
	local rec = sent[#sent]
	return rec and rec.args[1]
end
local function order(view, withName)
	local out = {}
	for _, r in (view and view.rows or {}) do
		table.insert(out, tostring(r.userId) .. ":" .. tostring(r.depth) .. (if withName then ":" .. tostring(r.name) else "")
			.. (if r.you then "*" else ""))
	end
	return table.concat(out, " ")
end
h:advance(bc.PublicCacheSeconds + 1) -- the next public refresh sees the new values
local pub = lastView(A)
truthy(pub ~= nil and pub.mode == "public", "Ava's board starts on the PUBLIC view")
eq(order(pub, true), "505:50:User_505 503:29:Cy 509:25:Ned 508:20:User_508 502:12:Bo 501:12:Ava 504:9:Dee 507:2:Eli",
	"public view: deepest first, Bo above Ava on the same depth (he got there first), names resolved")

--======================================================================= 3. written only when it improves

local Enter = remotes:FindFirstChild("Enter")
local RunRemote = remotes:FindFirstChild("Run")
local function lastRunEvent(plr, kind)
	local sent = RunRemote:sentTo(plr)
	for i = #sent, 1, -1 do
		if sent[i].args[1] == kind then return sent[i].args[2], i end
	end
	return nil, 0
end
-- A real run, WALKED: enter, cross every storey along its corridor cell by cell at WalkSpeed, climb every
-- shaft pad by pad, and step onto the exit. Nothing is passed through, so the flier gate can follow it.
-- `early` is the board's write count a few ticks in, with the runner already heading for the exit.
local Progression = h:_require(RS:FindFirstChild("Progression"))
local VaultFloor = h:_require(RS:FindFirstChild("VaultFloor"))
local VaultPath = h:_require(RS:FindFirstChild("VaultPath"))
local MazeGen = h:_require(RS:FindFirstChild("MazeGen"))
local Rng = h:_require(RS:FindFirstChild("Rng"))
local function escape(plr, tier)
	local _, endsBefore = lastRunEvent(plr, "end")
	Enter:simulateFireServer(plr, tier)
	h:advance(0.5)
	local vaultsFolder = h.workspace:FindFirstChild("Vaults")
	local v = vaultsFolder:FindFirstChild("Vault_" .. plr.UserId)
	if not v then return nil end
	local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
	local spec = Progression.difficulty(Config, tier, v:GetAttribute("Floor"))
	spec.seed = Progression.seedFor(Config, tier, v:GetAttribute("Floor"))
	local model = VaultFloor.build(Config, spec, MazeGen, Rng)
	local origin = v:FindFirstChild("Floor_0").Position + Vector3.new(0, Config.Vault.FloorThickness / 2, 0)
	local S, HS, ROOT = model.cellSize, model.storeyHeight, Config.Run.RunnerRootHeight
	local DT = Config.Ascent.SampleSeconds
	local at = hrp.Position - origin
	local px, py, pz = at.X, ROOT, at.Z
	local early, steps = nil, 0
	local function moveTo(x, y, z)
		for _ = 1, 4000 do
			if vaultsFolder:FindFirstChild("Vault_" .. plr.UserId) == nil then return end
			local dx, dz, dy = x - px, z - pz, y - py
			local flat = math.sqrt(dx * dx + dz * dz)
			if flat < 1e-6 and math.abs(dy) < 1e-6 then return end
			local m = math.min(flat, Config.Movement.WalkSpeed * DT)
			if flat > 1e-6 then px += dx / flat * m; pz += dz / flat * m end
			py += if dy > 0 then math.min(dy, 6 * DT) else dy
			hrp.CFrame = CFrame.new(origin + Vector3.new(px, py, pz))
			h:advance(DT)
			steps += 1
			if steps == 12 then early = writes end
		end
	end
	local function centre(c) return (2 * c.cx + 1 - model.cells) * S, (2 * c.cy + 1 - model.cells) * S end
	for s = 0, model.storeys - 1 do
		local to = model.exitCells[s + 1]
		local dist = VaultPath.distances(model, s, model.entryCells[s + 1])
		local cells, cur = { to }, to
		local d = dist[to.cy * model.cells + to.cx]
		while d > 0 do
			for _, dd in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local nx, ny = cur.cx + dd[1], cur.cy + dd[2]
				if nx >= 0 and nx < model.cells and ny >= 0 and ny < model.cells
					and model.grids[s + 1][2 * cur.cy + 1 + dd[2]][2 * cur.cx + 1 + dd[1]] == false
					and dist[ny * model.cells + nx] == d - 1 then
					cur = { cx = nx, cy = ny }; d -= 1
					table.insert(cells, 1, cur)
					break
				end
			end
		end
		for _, c in cells do
			local x, z = centre(c)
			moveTo(x, s * HS + ROOT, z)
		end
		if s < model.storeys - 1 then
			for _, pad in model.shafts[s + 1].pads do moveTo(pad.x, pad.y + ROOT, pad.z) end
			local x, z = centre(to)
			moveTo(x, (s + 1) * HS + ROOT, z)
		end
	end
	for _ = 1, 20 do
		local e, i = lastRunEvent(plr, "end")
		if i > endsBefore then return e, early end
		h:advance(0.5)
	end
	return nil, early
end

do
	local writesBefore = writes
	h:advance(3 * Config.Save.FlushTickSeconds + 1)
	eq(writes, writesBefore, "three flush ticks with no new depth write nothing to the board")

	-- Eli escapes Bronze floor 3: depth 3, deeper than his 2
	local w0 = writes
	local ended, early = escape(E, 1)
	truthy(ended ~= nil and ended.ok, "set-up: Eli escapes Bronze floor 3 (" .. tostring(ended and ended.reason) .. ")")
	eq(early, w0, "heading for the exit wrote nothing to the board: only the escape does")
	local escapedAt = os.time()
	eq(writes, w0 + 1, "a deeper escape: exactly one write to the board")
	local m, t = decode(stored(507))
	eq(m, 3, "the board now holds depth 3 for Eli")
	truthy(t ~= nil and math.abs(t - escapedAt) <= 5, "stamped when he got there (" .. tostring(t) .. " vs " .. escapedAt .. ")")
	local prof = profilesStore:GetAsync("u_507")
	eq(prof and prof.data and tonumber(prof.data.bestAt), t, "and the profile saved the same reach time (a retry would reuse it)")
	h:advance(3 * Config.Save.FlushTickSeconds + 1)
	eq(writes, w0 + 1, "and nothing more after that")

	-- Cy escapes Silver floor 1: depth 26, SHALLOWER than his 29. A run that banks is not a new best.
	local w1 = writes
	local cyEnd = escape(C, 2)
	truthy(cyEnd ~= nil and cyEnd.ok, "set-up: Cy escapes Silver floor 1 (" .. tostring(cyEnd and cyEnd.reason) .. ")")
	local cyProf = profilesStore:GetAsync("u_503")
	eq(cyProf and cyProf.data and tonumber((cyProf.data.floors or {})["2"] or (cyProf.data.floors or {})[2]), 2,
		"set-up: his Silver floor advanced and was saved")
	eq(writes, w1, "an escape that is not his deepest writes nothing to the board")
	eq(stored(503), Board.encode(29, 1785000000, bc), "and his 29 keeps its first reach time")
	eq(cyProf and cyProf.data and tonumber(cyProf.data.bestAt), 1785000000,
		"and so does his profile: a shallower escape never re-stamps the reach time")
end

--======================================================================= 4. the public list is cached ~60 s

do
	local s0 = sorted
	h:advance(180)
	local n = sorted - s0
	print(string.format("  public top 10: %d GetSortedAsync calls in 180 s", n))
	truthy(n >= 2 and n <= 4, "public top 10: " .. n .. " GetSortedAsync calls in 180 s (one per " .. bc.PublicCacheSeconds .. " s)")
	local v = lastView(A)
	truthy(v and v.rows and #v.rows <= bc.PublicRows, "at most " .. bc.PublicRows .. " rows")
	local maxDepth = 0
	for _, r in (v and v.rows or {}) do maxDepth = math.max(maxDepth, r.depth or 0) end
	truthy(maxDepth > 0 and maxDepth < 1000, "rows carry decoded depths, never a raw stored value (max " .. maxDepth .. ")")
	truthy(string.find(order(v), "507:3", 1, true) ~= nil, "Eli's new depth reached the public board within a refresh (" .. order(v) .. ")")
	-- names are looked up once and kept: every refresh so far drew User_505 and User_508
	eq(nameCalls[505], 1, "User_505's name was looked up once over every refresh so far, then cached")
	eq(nameCalls[508], 1, "and User_508's")
	eq(nameCalls[503], nil, "Cy is in this server: his name comes from the server, never a web lookup")
end

--======================================================================= 5. the physical board, drawn by Ava's client

local function boardTexts()
	local gui = board and board:FindFirstChildWhichIsA("SurfaceGui", true)
	local texts = {}
	if gui then
		for _, d in gui:GetDescendants() do
			if d:IsA("TextLabel") and d.Visible ~= false and (d.Text or "") ~= "" then table.insert(texts, d.Text) end
		end
	end
	return texts, gui
end
local function has(texts, needle)
	for _, t in texts do if string.find(t, needle, 1, true) then return t end end
	return nil
end
do
	local texts, gui = boardTexts()
	truthy(gui ~= nil, "Ava's client draws a SurfaceGui on the board")
	truthy(gui == nil or gui.Face == Enum.NormalId.Front, "on its front face (the one turned to the spawn)")
	truthy(A.PlayerGui:FindFirstChildWhichIsA("SurfaceGui", true) == nil, "not in PlayerGui (the HUD fit check measures everything there as screen)")
	truthy(has(texts, bc.Text.Title) ~= nil, "the board has its title (" .. bc.Text.Title .. ")")
	truthy(has(texts, "PUBLIC") ~= nil, "the board says PUBLIC")
	local row1 = has(texts, "User_505")
	truthy(row1 ~= nil and string.find(row1, "50", 1, true) ~= nil, "row 1: User_505, depth 50 (" .. tostring(row1) .. ")")
	local mine = has(texts, "Ava")
	truthy(mine ~= nil and string.find(mine, "12", 1, true) ~= nil and string.find(mine, "(you)", 1, true) ~= nil,
		"Ava's own row shows 12 and is marked (" .. tostring(mine) .. ")")
	local frozen = has(texts, "Cy")
	truthy(frozen ~= nil and string.find(frozen, "❄", 1, true) ~= nil, "a depth in the Frozen Vault carries its stratum (" .. tostring(frozen) .. ")")
	local hint = has(texts, bc.Text.Prompt)
	truthy(hint ~= nil, "the board tells you how to switch it (" .. tostring(hint) .. ")")
end

--======================================================================= 6. friends: on demand, cached, per player

eq(friendCalls[501], nil, "no friends were fetched before anyone asked")
local readsBefore = #reads
if prompt then prompt.Triggered:Fire(A) end
h:advance(2)
eq(friendCalls[501], 1, "the prompt fetches Ava's friends once")
local fv = lastView(A)
truthy(fv ~= nil and fv.mode == "friends", "Ava's board is now FRIENDS")
eq(order(fv), "505:50 508:20 502:12 501:12*",
	"friends view: Eve 50, Gus 20, Bo 12 (got there first), Ava 12 (you); Finn never escaped")
eq(fv and fv.note, nil, "all four friends checked: no note")
do
	local newReads = {}
	for i = readsBefore + 1, #reads do table.insert(newReads, reads[i]) end
	table.sort(newReads)
	eq(table.concat(newReads, ","), "u_505,u_506,u_508", "the scores read are the three friends NOT in this server (Bo's comes from memory)")
end
do
	local texts = boardTexts()
	truthy(has(texts, "FRIENDS") ~= nil, "the board says FRIENDS")
	truthy(has(texts, "Eve") ~= nil, "and names Eve (from the friends list, not a stored name)")
end
eq(lastView(B).mode, "public", "Bo's board is still PUBLIC: the toggle is per player")
if prompt then prompt.Triggered:Fire(A) end
h:advance(1)
eq(lastView(A).mode, "public", "the prompt again: back to PUBLIC")
local readsMid = #reads
if prompt then prompt.Triggered:Fire(A) end
h:advance(1)
eq(lastView(A).mode, "friends", "and FRIENDS again")
eq(friendCalls[501], 1, "the friends list came from the cache (still 1 fetch)")
eq(#reads, readsMid, "and so did every score (no new reads)")

--======================================================================= 7. empty friends boards say something useful

local function friendsNoteFor(name, uid)
	local p = joinAs(name, uid)
	h:advance(1)
	if prompt then prompt.Triggered:Fire(p) end
	h:advance(3)
	local v = lastView(p)
	return v and v.note, v
end
do
	local noFriends = friendsNoteFor("Hal", 510)
	eq(noFriends, bc.Text.NoFriends, "no friends: says friends you add show up here")
	local noScores = friendsNoteFor("Ida", 511)
	eq(noScores, string.format(bc.Text.FriendsNoScores, 1), "friends who never escaped: says so, and invites")
	local failedNote, fview = friendsNoteFor("Jon", 512)
	eq(failedNote, bc.Text.FriendsFailed, "the friends call fails: says try again, no crash")
	eq(fview and fview.mode, "friends", "and still shows the friends view")
end

--======================================================================= 8. capped at 200 and throttled

do
	local readsAt = #reads
	local advancedAt = pagesAdvanced
	local p = joinAs("Kim", 513)
	h:advance(1)
	if prompt then prompt.Triggered:Fire(p) end
	h:advance(1)
	local early = #reads - readsAt
	truthy(early <= bc.ReadsBurst + 2, "450 friends: at most the burst is read at once (" .. early .. " in the first second)")
	local mid = lastView(p)
	truthy(mid and mid.note and string.find(mid.note, "of 200", 1, true) ~= nil, "the board says how far it has got (" .. tostring(mid and mid.note) .. ")")
	h:advance(59)
	local minute = #reads - readsAt
	truthy(minute <= bc.ReadsBurst + bc.ReadsPerSecond * 60 + 1, "a minute in: " .. minute .. " reads, never more than burst + rate * 60")
	h:advance(240)
	local total = #reads - readsAt
	print(string.format("  450 friends: %d reads in the first second, %d in the first minute, %d in all; %d pages turned",
		early, minute, total, pagesAdvanced - advancedAt))
	eq(total, 200, "in the end exactly the first 200 friends are read, not 450")
	truthy(pagesAdvanced - advancedAt <= 4, "and no page past the 200th friend is fetched (" .. (pagesAdvanced - advancedAt) .. " pages turned)")
	local done = lastView(p)
	eq(done and done.note, string.format(bc.Text.FriendsNoScores, 200), "then the note says none of the 200 has escaped")
end

do
	-- Hal, Ida, Jon and Kim were sent friends views since; this client (Ava's) draws only views addressed to Ava
	local texts = boardTexts()
	truthy(has(texts, "FRIENDS") ~= nil and has(texts, "Eve") ~= nil and has(texts, "Pal") == nil,
		"Ava's board still shows Ava's friends, not the views sent to other players")
end

--======================================================================= 9. names are never stored; no remote moves it

do
	local HttpService = h.game:GetService("HttpService")
	local leaked = nil
	for uid, name in { [501] = "Ava", [502] = "Bo", [503] = "Cy", [504] = "Dee", [507] = "Eli" } do
		local rec = profilesStore:GetAsync("u_" .. uid)
		local json = HttpService:JSONEncode(rec)
		if string.find(json, '"' .. name .. '"', 1, true) then leaked = leaked or name end
	end
	truthy(leaked == nil, "no saved profile holds a player's name" .. (if leaked then " (" .. leaked .. ")" else ""))
	local allNumbers = true
	for k, v in lb.__data do
		if type(v) ~= "number" or Board.userIdOf(k) == nil then allNumbers = false end
	end
	truthy(allNumbers, "the board's store holds only u_<id> keys and numbers")

	-- every client -> server remote, forged: none of them carries a depth, a floor or a time
	local before = {}
	for k, v in lb.__data do before[k] = v end
	local w = writes
	local Buy, Equip = remotes:FindFirstChild("Buy"), remotes:FindFirstChild("Equip")
	for _, args in { { 99 }, { 1e9 }, { -1 }, { 0 }, { "3" }, { { depth = 999 } } } do
		Enter:simulateFireServer(A, table.unpack(args))
	end
	Buy:simulateFireServer(A, "crownwyrm")
	Equip:simulateFireServer(A, "crownwyrm")
	h:advance(3 * Config.Save.FlushTickSeconds + 1)
	local moved = nil
	for k, v in lb.__data do if before[k] ~= v then moved = moved or k end end
	eq(moved, nil, "forged Enter / Buy / Equip payloads move nothing on the board")
	truthy(writes == w, "and cost it no write (" .. (writes - w) .. ")")
	eq(h.workspace:FindFirstChild("Vaults"):FindFirstChild("Vault_501"), nil, "(and none of them started a run)")
end

--======================================================================= 10. the board's store failing

do
	local before = order(lastView(B))
	lb.__failAll = true
	h:advance(bc.PublicCacheSeconds * 2 + 1)
	local after = lastView(B)
	eq(order(after), before, "the store failing keeps the last list on the board rather than blanking it")
	lb.__failAll = false
end

--======================================================================= 11. the sign streams out and back

-- If the place streams, the sign can leave a client while the runner is up in a vault and come back as a
-- NEW part, without the SurfaceGui this client hung on the old one. Staged here by swapping the sign for a
-- bare copy of it: Ava's client must draw again, on the new part, the last view the server sent her.
do
	local _, oldGui = boardTexts()
	truthy(oldGui ~= nil, "set-up: the sign carries Ava's drawing")
	local copy = board:Clone()
	for _, d in copy:GetDescendants() do
		if d:IsA("SurfaceGui") or d:IsA("ProximityPrompt") then d:Destroy() end
	end
	board.Parent = nil
	copy.Parent = hub
	h:advance(1)
	local gui = copy:FindFirstChildWhichIsA("SurfaceGui", true)
	truthy(gui ~= nil, "the sign that came back is drawn on again")
	local texts = {}
	if gui then
		for _, d in gui:GetDescendants() do
			if d:IsA("TextLabel") and d.Visible ~= false and (d.Text or "") ~= "" then table.insert(texts, d.Text) end
		end
	end
	local function hasIn(needle)
		for _, s in texts do if string.find(s, needle, 1, true) then return true end end
		return false
	end
	truthy(hasIn("FRIENDS") and hasIn("Eve"), "with the last view Ava was sent (her friends), not a blank board")
	copy:Destroy()
	board.Parent = hub
	h:advance(1)
end

print("")
eq(#h.warnings, 0, "no warnings")
for _, w in h.warnings do print("warning: " .. w) end
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("vaultrunners board: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("vaultrunners board check failed", 0)
end

-- FACILITY: Endless Nightmare — the TOP DIVERS board while its OrderedDataStore is DOWN (every call raises: an outage,
-- or a place opened in Studio without API access). Run: luau check_facilitynightmare_boardoff.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../facility-nightmare --out build/facility-nightmare.luau
--
-- docs/complete-game-standard.md §1 and §3: pcall everything; a board that cannot be read says so instead of claiming
-- nobody has played; a board write that failed is made at the next save, not lost. The harness allows one game per
-- process, so this is its own file (the working store is check_facilitynightmare_board.luau).

local Harness = require("./emu/harness")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end
-- written out, not read from Config
local AUTOSAVE, PUBLIC_TTL = 20, 60
local UNAVAILABLE = "The board can't be reached on this server right now."

local h = Harness.new({ bundle = require("./build/facility-nightmare"), name = "facility-nightmare", viewport = { 1280, 720 }, touch = false })
local dss = h.services.DataStoreService
local profiles = dss:GetDataStore("FacilityNightmare_v1")
profiles:SetAsync("u_8201", { data = { v = 1, essence = 0, essenceEarned = 0, bestSublevel = 3, bestAt = 1780000000, runs = 3,
	extractions = 0, perks = { deepCell = 0, nightEyes = 0, marathon = 0, soulAnchor = 0, secondWind = 0 } } })
local lb = dss:GetOrderedDataStore("FacilityNightmare_TopDivers_v1")
lb.__failAll = true -- every call to the board's store raises
local calls0 = lb.__calls

local ok, err = h:tryRun("server/Main.server")
truthy(ok, "the server boots with the board's store down (" .. tostring(err) .. ")")
local Config = h:_require(h.ReplicatedStorage:FindFirstChild("Config"))
eq(Config.Board.Text.Unavailable, UNAVAILABLE, "Config.Board.Text.Unavailable")
h.game:GetService("RunService"):setIsServer(false)
local p = h:join("Solo", 8201)
h.Players:simulateSpawn(p, h.workspace)
h:advance(AUTOSAVE + PUBLIC_TTL + 1)
truthy(lb.__calls - calls0 >= 3, "set-up: the server tried the board's store (" .. (lb.__calls - calls0) .. " calls, all raised)")
eq(lb.__data["u_8201"], nil, "set-up: nothing reached the board")

local remote = h.ReplicatedStorage:FindFirstChild("FacilityRemotes"):FindFirstChild("Board")
local function last()
	local sent = remote:sentTo(p)
	return sent[#sent] and sent[#sent].args[1]
end
local v = last()
eq(v and v.mode, "public", "the board shows its public view")
eq(v and v.note, UNAVAILABLE, "and says it can't be reached (not that nobody has played)")
eq(v and #v.rows, 0, "with no rows")

local prompt = h.workspace.Hub.TopDiversBoard:FindFirstChildWhichIsA("ProximityPrompt", true)
prompt.Triggered:Fire(p)
h:advance(2)
v = last()
eq(v and v.mode, "friends", "the prompt still answers")
truthy(v and type(v.note) == "string" and #v.note > 10, "and the friends board says something (" .. tostring(v and v.note) .. ")")
prompt.Triggered:Fire(p)
h:advance(1)

local st = h.ReplicatedStorage.FacilityRemotes.State:sentTo(p)
local s = st[#st] and st[#st].args[1]
eq(s and s.loaded, true, "the player's file still loads")
eq(s and s.bestSublevel, 3, "with the record the board could not take")

-- the store comes back: the next public read shows the board, and the write that failed is made at the next save
lb.__failAll = false
h:advance(PUBLIC_TTL + 1)
local Board = h:_require(h.ReplicatedStorage:FindFirstChild("Board"))
eq(lb.__data["u_8201"], Board.encode(3, 1780000000, Config.Board), "the record that could not be written is written once the store is back")
v = last()
eq(v and v.mode, "public", "the board is public again")
truthy(v and v.note ~= UNAVAILABLE, "and no longer says it can't be reached (" .. tostring(v and v.note) .. ")")
local row = v and v.rows and v.rows[1]
eq(row and row.userId, 8201, "Solo is on it")

eq(#h.warnings, 0, "no warnings (" .. table.concat(h.warnings, " | ") .. ")")
for _, e in h:errors() do
	print("scheduler error: " .. e)
	failed += 1
end
print(string.format("check_facilitynightmare_boardoff: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("check_facilitynightmare_boardoff failed", 0)
end

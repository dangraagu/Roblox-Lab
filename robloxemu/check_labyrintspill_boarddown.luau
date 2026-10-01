-- Labyrinth Mariozo — the highscore board while its store is down. Run: luau check_labyrintspill_boarddown.luau 2>&1
-- Rebuild the bundle first: py -3 wrap.py --game ../labyrint-spill --out build/labyrint-spill.luau
--
-- (2026-10-01, pass 2) docs/complete-game-standard.md §1 "no silent no-ops": when the very first GetSortedAsync of a
-- server fails (an outage, or Studio without API access), the board must not say "Loading..." for ever, and a board
-- write lost to the outage must not wait for the player's next join. A fresh server whose board store refuses every
-- call (the emulator's own failure injection, __failAll); the player's board is read off the wire. Its own file
-- because the emulator runs one harness per process, and check_labyrintspill_board needs a store that works.

local Harness = require("./emu/harness")
local Lib = require("./check_labyrintspill_lib")
local c = Lib.counter("labyrintspill boarddown")
local eq, truthy = c.eq, c.truthy
local today = math.floor(os.time() / 86400)

local h = Harness.new({ bundle = require("./build/labyrint-spill"), name = "labyrint-spill", viewport = { 1280, 720 }, touch = false })
local DSS = h.services.DataStoreService
DSS:GetDataStore("LabyrintSpill_v1"):SetAsync("p_601", { accepted = 3, level = 4, acceptedAt = 1780000000, rewardDay = today })
local down = DSS:GetOrderedDataStore("LabyrintTopp_v3")
down.__failAll = true
local okServer, errServer = h:tryRun("server/MazeGame.server")
truthy(okServer, "the server runs: " .. tostring(errServer))
local P = h:join("Pia", 601)
h:advance(0.5)
h.Players:simulateSpawn(P, h.workspace)
h:advance(3)
local BC = h:_require(h.ReplicatedStorage:FindFirstChild("BoardConfig"))
local function lastView()
	local sent = h.ReplicatedStorage.HudRemotes.Board:sentTo(P)
	return sent[#sent] and sent[#sent].args[1]
end
local v = lastView()
truthy(v ~= nil and v.mode == "public", "the board was sent")
truthy(v ~= nil and v.note ~= BC.Text.Loading, "with the board store down, the board does not say Loading... for ever: " .. tostring(v and v.note))
eq(v and v.note, BC.Text.PublicFailed, "it says the board could not be loaded")
truthy(type(BC.Text.PublicFailed) == "string" and string.find(string.lower(BC.Text.PublicFailed), "try again", 1, true) ~= nil,
	"and that it tries again: " .. tostring(BC.Text.PublicFailed))
-- Pia's join-time board write failed with the store. The store comes back: the lost write is retried (it rides on
-- the autosave, and costs no call while nothing is owed), and within two refreshes the board shows her, level 3.
eq(down.__data["u_601"], nil, "while the store was down, nothing was written")
down.__failAll = false
h:advance(BC.PublicCacheSeconds * 2 + 2)
eq(down.__data["u_601"] and math.floor(down.__data["u_601"] / 2e9 + 0.5), 3, "the lost board write is retried once the store answers")
v = lastView()
truthy(v ~= nil and v.note == nil and v.rows and v.rows[1] and v.rows[1].tier == 3 and v.rows[1].name == "Pia",
	"and the board shows its rows again (" .. tostring(v and v.note) .. ")")
for _, w in h.warnings do print("warning: " .. w) end
eq(#h.warnings, 0, "no warnings")
c.finish(h)

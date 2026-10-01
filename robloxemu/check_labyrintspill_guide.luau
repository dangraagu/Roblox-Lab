-- Labyrinth Mariozo — a bought "Hjelp meg" guide is kept until its level is cleared (owner decision, 30.09).
-- Run: luau check_labyrintspill_guide.luau 2>&1   (rebuild the bundle first, see check_labyrint.luau)
--
-- The guide used to be bought for ONE run: dying or walking out lost it, with no refund, and the free-break sign
-- had to hide its "nothing is lost" while one was active. The owner took the kinder option: the guide waits for
-- the player on the same level until that level is cleared. It must never become exploitable:
--   * never on another level (it cannot be banked for a harder one), never bought twice, used up on a clear;
--   * the server decides it, from the level the player paid for (saved with the player's data), never the client;
--   * a guided run still gives no time record (Progression.recordEligible, unchanged).
-- Through the real server and the real clients (AssistClient's lobby text), one player:
--   §1 three counted deaths at L42, the guide offered and bought;
--   §2 died with it: the lobby says it is kept, and the next attempt at L42 starts with it, no second charge;
--   §3 not on L41; a run that moves on from L41 into L42 has it; a walk-out keeps it too;
--   §4 kept across a rejoin (saved);
--   §5 clearing L42 uses it up: L43 has none, and L42 again has none.

local Lib = require("./check_labyrintspill_lib")
local T = Lib.counter("labyrintspill guide")
local truthy, eq = T.truthy, T.eq

local ctx = Lib.boot({ accepted = 41, coins = 5000, clients = Lib.CLIENTS_NO_SOUND, userId = 5151 })
local h = ctx.h
eq(#ctx.loadErrors, 0, "the clients load (" .. table.concat(ctx.loadErrors, "; ") .. ")")
local RS = h.ReplicatedStorage
local last = nil
RS.AssistRemotes.AssistState.OnClientEvent:Connect(function(p) last = p end)
local buy = RS.AssistRemotes.BuyAssist
local panel = ctx.plr.PlayerGui:FindFirstChild("AssistPanel")

local function dots()
	local f = ctx.folder()
	local g = f and f:FindFirstChild("Guide")
	return g and #g:GetChildren() or 0
end
local function respawn()
	local char = h.Players:simulateSpawn(ctx.plr, h.workspace)
	ctx.run(0.5)
	ctx.char, ctx.hrp, ctx.hum = char, char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid")
	ctx.hum.FloorMaterial = Enum.Material.Plastic
	ctx.hum.MoveDirection = Vector3.new(0, 0, 0)
end
local function die()
	ctx.hum.Health = 0
	ctx.run(0.2)
	respawn()
end
local function panelText()
	local out = {}
	for _, d in (panel and panel:GetDescendants() or {}) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then table.insert(out, d.Text) end
	end
	return table.concat(out, " | ")
end

--================================================================ §1 stuck, offered, bought

for _ = 1, 3 do
	ctx.startRun(42)
	die()
end
eq(last and last.fails, 3, "§1 three deaths at L42 are three counted attempts")
ctx.startRun(42)
eq(last and last.offered, true, "§1 the guide is offered")
eq(last and last.active, false, "§1 not bought yet")
ctx.run(0.1)
truthy(string.find(panelText(), "until you clear this level", 1, true) ~= nil and string.find(panelText(), "for this run", 1, true) == nil,
	"§1 the offer says the guide lasts until the level is cleared, not 'for this run' (" .. panelText() .. ")")
local r = buy:simulateInvokeServer(ctx.plr)
eq(r and r.ok, true, "§1 bought (" .. tostring(r and r.reason) .. ")")
local paid = r and r.coins
eq(last and last.active, true, "§1 active")
truthy(dots() > 0, "§1 the guide's lights are in the maze (" .. dots() .. ")")

--================================================================ §2 died with it: kept

die()
eq(ctx.folder(), nil, "§2 back in the lobby after dying")
eq(last and last.kept, true, "§2 the server says the guide is kept for L42")
ctx.run(0.3)
truthy(string.find(panelText(), "kept", 1, true) ~= nil, "§2 and the lobby card says so (" .. panelText() .. ")")
ctx.startRun(42)
eq(last and last.active, true, "§2 the next attempt at L42 starts with the guide")
truthy(dots() > 0, "§2 its lights are there (" .. dots() .. ")")
eq(last and last.coins, paid, "§2 and it cost nothing again")
local again = buy:simulateInvokeServer(ctx.plr)
eq(again and again.ok, false, "§2 it cannot be bought a second time")
eq(again and again.coins, paid, "§2 no coins taken")

--================================================================ §3 never another level; a walk-out keeps it

ctx.toLobby()
ctx.startRun(41)
eq(last and last.level, 41, "§3 on L41")
eq(last and last.active, false, "§3 the guide for L42 is not used on L41")
eq(dots(), 0, "§3 no lights on L41")
ctx.finishLevel()
ctx.run(0.3)
eq(last and last.level, 42, "§3 clearing L41 moves the run on to L42")
eq(last and last.active, true, "§3 and the kept guide lights up there too (a run that moves on into its level)")
truthy(dots() > 0, "§3 with its lights (" .. dots() .. ")")
ctx.toLobby()
ctx.startRun(42)
eq(last and last.active, true, "§3 a walk-out kept it: L42 again starts with it")

--================================================================ §4 kept across a rejoin

ctx.toLobby()
h:leave(ctx.plr)
ctx.run(0.5)
local store = h.services.DataStoreService:GetDataStore("LabyrintSpill_v1")
local saved = store:GetAsync("p_5151")
eq(saved and saved.guideLevel, 42, "§4 the kept guide is saved with the player's data")
local plr2 = h:join("Walker", 5151)
ctx.plr = plr2
ctx.run(0.3)
respawn()
ctx.startRun(42)
eq(last and last.active, true, "§4 after a rejoin, L42 still starts with the guide")

--================================================================ §5 a clear uses it up

ctx.finishLevel()
ctx.run(0.3)
eq(last and last.level, 43, "§5 L42 cleared: the run goes on to L43")
eq(last and last.active, false, "§5 L43 has no guide")
eq(last and last.kept, false, "§5 and nothing is kept any more")
local after = store:GetAsync("p_5151")
eq(after and after.guideLevel, nil, "§5 the saved data no longer carries it")
ctx.toLobby()
ctx.startRun(42)
eq(last and last.active, false, "§5 L42 again: the guide was used up by the clear")

T.finish(h)

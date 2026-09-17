-- Lost & Found Depot — what a client can PREDICT from what it can see.
--
-- Run:  py -3 wrap.py --game ../lost-found-depot --out build/lost-found-depot.luau
--       luau check_lostfounddepot_rng.luau
--
-- WHY THIS FILE EXISTS (REVIEW-1 pass 3, exploit finding 3). The shift generator ships in
-- ReplicatedStorage, the repo's Rng is an LCG whose whole state is 32 bits, and every item of a shift
-- came from one seed. A client that read only the 6 bin signs and the tray found that seed by brute
-- force in 18 s (715,827,886 candidate states), inverted fmix to get the per-session salt, and then
-- predicted the 22 cart items in order, and the next shifts' bins, trays and memos, before the server
-- armed them. DESIGN.md §8.2 and README say a client never gets any of that.
--
-- THE ATTACKER MODEL, stated so it can be argued with. The brute force is 18 s of CPU per shift, so
-- this file does not re-run it: it reads the seed from the server console line `seed N`, which is
-- exactly what the brute force recovers (the reviewer's run matched the console on both runs). From
-- that seed it does what the attacker did:
--   1. regenerate the shift with the public Shift.generate; CONTROL: the tray and bins it predicts are
--      the ones in the world (the premise of the attack still holds, and says nothing new);
--   2. predict the cart (items 9-30) and compare with what actually rolls onto the tray;
--   3. invert the last fmix to recover the salt, predict the NEXT shift's seed, and compare with the
--      next console line.
-- Nothing else from the console is read (the console also prints the cart keys, for replay).

local Harness = require("./emu/harness")
local bundle = require("./build/lost-found-depot")

local h = Harness.new({ bundle = bundle, name = "lost-found-depot-rng", viewport = { 1280, 720 }, touch = false })
do
	local sss = h.services.ServerScriptService
	for key, entry in h.bundle do
		local name = string.match(key, "^server/(.+)$")
		if name and not string.match(name, "%.server$") and h.modules[key] == nil then
			local holder = h.instance.Instance.new("ModuleScript")
			holder.Name = name
			holder.Parent = sss
			h.modules[key] = { holder = holder, key = key, entry = entry, state = "cold", value = nil }
		end
	end
end
do -- every unseeded Random pinned to its own value, so a failure replays
	local realRandom = Random
	local unseeded = 0
	Random = {
		new = function(seed)
			if seed == nil then
				unseeded += 1
				return realRandom.new(918273 + unseeded * 104729)
			end
			return realRandom.new(seed)
		end,
	}
end
-- The console, captured. Installed BEFORE the server runs: Luau resolves a global once per script.
local consoleSeeds = {}
do
	local realPrint = print
	print = function(...)
		local line = table.concat(table.pack(...), " ")
		local shift, stage, seed = string.match(line, "shift (%d+), stage (%d+), seed (%d+)")
		if seed then
			table.insert(consoleSeeds, { shift = tonumber(shift), stage = tonumber(stage), seed = tonumber(seed) })
		end
		realPrint(...)
	end
end

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL: " .. msg .. " -> got " .. tostring(a) .. ", want " .. tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL: " .. msg) end end

local okBoot, bootErr = h:tryRun("server/Main.server")
truthy(okBoot, "the server loads" .. (if okBoot then "" else ": " .. tostring(bootErr)))
if not okBoot then
	print(string.format("lost-found-depot rng: %d passed, %d failed", passed, failed))
	error("server did not load", 0)
end
h:advance(1)

-- What the client has: the public modules.
local RS = h.ReplicatedStorage
local Config = h:_require(RS:FindFirstChild("Config"))
local Rules = h:_require(RS:FindFirstChild("Rules"))
local Rng = h:_require(RS:FindFirstChild("Rng"))
local Shift = h:_require(RS:FindFirstChild("Shift"))
local Seed = h:_require(RS:FindFirstChild("Seed"))
local remotes = RS:FindFirstChild("DepotRemotes")
local StateEvent = remotes.State

local UID = 31337
local plr = h:join("Oracle", UID)
h:advance(0.1)
h.Players:simulateSpawn(plr, h.workspace)
h:advance(0.5)
local bay = plr.RespawnLocation.Parent
local ox = bay.BayPad.Position.X
local P = Vector3.new(ox, 3, 0)
local function state() local s = StateEvent:sentTo(plr) return s[#s].args[1] end
local function hrp() return plr.Character.HumanoidRootPart end

local BIN_OF_NAME, LETTER_OF_NAME = {}, {}
for id, name in Config.Rules.BinNames do BIN_OF_NAME[name] = id end
for _, it in Config.Catalog do LETTER_OF_NAME[it.name] = it.letter end

local function slotText(s)
	local t = bay["Slot_" .. s].Tag
	if not t.Enabled then return nil end
	return t.ItemName.Text .. "|" .. (string.gsub(t.TagLine.Text, "<[^>]*>", ""))
end
local function itemText(it)
	return it.name .. "|" .. Rules.tagText(Config, it.tag)
end
local function readRules()
	local text = bay.MemoBoard.SignGui.Label.Text
	for _, m in Rules.memos(Config) do
		if string.find(text, Rules.memoLine(Config, m), 1, true) then return Rules.withMemo(Config, m) end
	end
	return Rules.base(Config)
end
local function binFor(entry)
	local id = Rules.resolve(Config, Rules.parseTag(Config, entry.tag), LETTER_OF_NAME[entry.name], readRules())
	for k = 1, 6 do
		local m = bay["Bin_" .. k]
		if BIN_OF_NAME[m.Sign.SignGui.Label.Text] == id then return m end
	end
end

-- fmix inverted (the reviewer's unfmix): the last step of Seed.forShift gives the salt away
local M32 = 4294967296
local function modinv(a)
	local x = a
	for _ = 1, 6 do x = Seed.mul32(x, (2 - Seed.mul32(a, x)) % M32) end
	return x
end
local function unxs(y, k)
	local x = y
	for _ = 1, math.ceil(32 / k) do x = bit32.bxor(y, bit32.rshift(x, k)) end
	return x
end
local INV1, INV2 = modinv(0x85EBCA6B), modinv(0xC2B2AE35)
local function unfmix(v)
	v = unxs(v, 16)
	v = Seed.mul32(v, INV2)
	v = unxs(v, 13)
	v = Seed.mul32(v, INV1)
	return unxs(v, 16)
end
truthy(unfmix(Seed.fmix(123456789)) == 123456789, "CONTROL: the attacker's fmix inverse is right")
local function saltFrom(seed, shifts)
	local ctx = Seed.fmix(math.floor(Config.WorldSeed) % M32)
	ctx = Seed.fmix(bit32.bxor(ctx, UID % 1000003))
	ctx = Seed.fmix(bit32.bxor(ctx, shifts))
	return bit32.bxor(unfmix(seed), ctx)
end

--============================================================================ three shifts

local SHIFTS = 3
local trayHits, trayTotal, binHits = 0, 0, 0
local cartHits, cartTotal = 0, 0
local nextSeedHits, nextSeedTotal = 0, 0

for s = 1, SHIFTS do
	for _ = 1, 40 do
		if state().shift and state().shift.state == "ARMED" then break end
		h:advance(0.5)
	end
	local st = state()
	eq(st.shift.state, "ARMED", "shift " .. s .. " arms")
	local console = consoleSeeds[#consoleSeeds]
	eq(console and console.shift, s, "CONTROL: the console printed shift " .. s .. "'s seed")
	local seed = console.seed
	local shiftsBefore = st.shifts

	-- 1. regenerate from the seed alone
	local predicted = Shift.generate(Config, Rng, Rules, seed, console.stage, s)
	for slot = 1, Config.Shift.TraySlots do
		trayTotal += 1
		if slotText(slot) == itemText(predicted.items[predicted.tray[slot]]) then trayHits += 1 end
	end
	for arc = 1, 6 do
		if BIN_OF_NAME[bay["Bin_" .. arc].Sign.SignGui.Label.Text] == predicted.binSlots[arc] then binHits += 1 end
	end

	-- 2. play it honestly, one item at a time, and write down every item that rolls in
	local seen = {}
	for slot = 1, Config.Shift.TraySlots do seen[slot] = slotText(slot) end
	local rolledIn = {}
	for _ = 1, 400 do
		st = state()
		if st.shift.state == "SUMMARY" then break end
		hrp().CFrame = CFrame.new(P)
		local picked = false
		for slot = 1, Config.Shift.TraySlots do
			local t = bay["Slot_" .. slot]
			if t.Tag.Enabled and t:FindFirstChild("Item") then
				t.Item.ClickDetector.MouseClick:Fire(plr)
				picked = true
				break
			end
		end
		h:advance(0.4)
		for slot = 1, Config.Shift.TraySlots do
			local now = slotText(slot)
			if now ~= nil and now ~= seen[slot] then table.insert(rolledIn, now) end
			seen[slot] = now
		end
		if picked and #state().shift.carried > 0 then
			local entry = state().shift.carried[1]
			local m = binFor(entry)
			local b = m.Base.Position
			local flat = Vector3.new(b.X, 3, b.Z)
			hrp().CFrame = CFrame.new(flat + (P - flat).Unit * 5)
			remotes.Select:simulateFireServer(plr, 1)
			m.Base.Drop.Triggered:Fire(plr)
			h:advance(0.4)
		end
	end
	eq(state().shift.state, "SUMMARY", "shift " .. s .. " was played to the end")
	eq(state().shift.summary and state().shift.summary.misfiles, 0, "CONTROL: ... with no misfile, so the roll-ins are the cart in order")
	eq(#rolledIn, #predicted.cart, "CONTROL: " .. #predicted.cart .. " items rolled in")
	local hits = 0
	for i, n in predicted.cart do
		cartTotal += 1
		if rolledIn[i] == itemText(predicted.items[n]) then
			cartHits += 1
			hits += 1
		end
	end
	print(string.format("  shift %d: seed %d; the seed predicts %d of 22 cart items", s, seed, hits))

	-- 3. the salt, and the next shift's seed
	if s < SHIFTS then
		local salt = saltFrom(seed, shiftsBefore)
		eq(Seed.forShift(Config, UID, shiftsBefore, salt), seed, "CONTROL: the recovered salt reproduces this shift's seed")
		local guess = Seed.forShift(Config, UID, shiftsBefore + 1, salt)
		for _ = 1, 40 do
			if #consoleSeeds > s then break end
			h:advance(0.5)
		end
		nextSeedTotal += 1
		if consoleSeeds[s + 1] and consoleSeeds[s + 1].seed == guess then nextSeedHits += 1 end
	end
end

print(string.format("  the seed predicts: tray %d of %d, bins %d of %d, cart %d of %d; the salt predicts %d of %d next seeds",
	trayHits, trayTotal, binHits, SHIFTS * 6, cartHits, cartTotal, nextSeedHits, nextSeedTotal))
eq(trayHits, trayTotal, "CONTROL: the seed still regenerates every tray item (what the brute force finds, and all it finds)")
eq(binHits, SHIFTS * 6, "CONTROL: ... and every bin sign")
truthy(cartTotal == 66 and cartHits <= 2, "E3: the seed a client can recover predicts the cart no better than chance (" .. cartHits .. " of " .. cartTotal .. ")")
eq(nextSeedHits, 0, "E3: the salt recovered from one shift does not predict the next shift's seed")

eq(#h:errors(), 0, "no thread died")
for _, e in h:errors() do print("scheduler error: " .. e) end
print(string.format("lost-found-depot rng: %d passed, %d failed", passed, failed))
if failed > 0 then error("lost-found-depot rng check failed", 0) end

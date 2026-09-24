-- Nightwatch Manor — a returning player whose profile loads SLOWLY. Run: luau check_nightwatchmanor_join.luau 2>&1
-- Regenerate the bundle first: py -3 wrap.py --game ../nightwatch-manor --out build/nightwatch-manor.luau
--
-- +1 Jump's review found that a slow profile load made the sky announce the wrong band and replay a
-- "you reached space" fanfare to a returning player. The same trap exists here: until the DataStore
-- round-trip lands, the server holds the DEFAULT profile (night 1). Haunt.client takes its night only from
-- the State remote, which the server first pushes AFTER the load. Checked with a night-20 player (the Blood
-- Moon, the one band that celebrates) and a 20 s load, longer than any timer in the client:
--   * while loading: no chip, no card, no rest button, no hazard, and the lighting stays the server's own
--     preset (band 1) instead of flashing night 1's look at somebody on night 20;
--   * when it lands: ONE quiet card naming the Blood Moon (no "RISES", no flash), the chip, and the
--     grade gliding to the band's tint with no single-frame jump;
--   * surviving night 20 (still the Blood Moon): no second card, no flash;
--   * a respawn mid-session: nothing re-announced.

local Kit = require("./check_nightwatchmanor_kit")

local flashes = 0
local ctx = Kit.boot({
	name = "nwm-join",
	profile = { night = 20, stash = 0, best = 19, levels = {} },
	slowLoad = 20,
	beforeClient = function(c)
		c.me:WaitForChild("PlayerGui").ChildAdded:Connect(function(g)
			if g.Name == "FxFlash" then flashes += 1 end
		end)
	end,
})
local h, eq, truthy = ctx.h, ctx.eq, ctx.truthy
local Config = ctx.Config
local bands = Config.Env.Bands
local function mod(name) return h:_require(ctx.RS:FindFirstChild(name)) end
local Nightfall = mod("Nightfall")
local blood = bands[Nightfall.bandIndex(bands, 20)]
eq(blood.id, "blood", "CONTROL: night 20 is the Blood Moon")

local function rgb255(c: Color3): { number }
	return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) }
end
local cc = h.Lighting:FindFirstChild("FxColorCorrection")
local band1Tint = bands[1].colorCorrection.TintColor

--================================================================ while the profile is in flight

local sawChip, sawRest, sawWarn, tintMoved = false, false, false, 0
for _ = 1, 18 * 10 do
	ctx.frame(0.1)
	if ctx.chip.Visible then sawChip = true end
	if ctx.restBtn.Visible then sawRest = true end
	if ctx.warning.Visible then sawWarn = true end
	local t = rgb255(cc.TintColor)
	tintMoved = math.max(tintMoved, math.abs(t[1] - band1Tint[1]), math.abs(t[2] - band1Tint[2]), math.abs(t[3] - band1Tint[3]))
end
eq(ctx.lastState(), nil, "CONTROL: 18 s in, the server has pushed no State yet (the load is still in flight)")
eq(sawChip, false, "no chip while the profile loads")
eq(#ctx.cards, 0, "no card while the profile loads")
eq(sawRest, false, "no rest button while the profile loads")
eq(sawWarn, false, "no hazard while the profile loads")
truthy(tintMoved <= 1, "the grade stays the server's preset while the profile loads (moved " .. tintMoved .. "/255)")

--================================================================ it lands

local maxStep = 0
local prev = rgb255(cc.TintColor)
for _ = 1, 10 * 10 do
	ctx.frame(0.1)
	local t = rgb255(cc.TintColor)
	maxStep = math.max(maxStep, math.abs(t[1] - prev[1]), math.abs(t[2] - prev[2]), math.abs(t[3] - prev[3]))
	prev = t
end
local st = ctx.lastState()
eq(st and st.night, 20, "the profile landed: night 20")
truthy(ctx.chip.Visible and string.find(ctx.chip.Text, "Blood Moon", 1, true) ~= nil, "the chip names the Blood Moon (" .. ctx.chip.Text .. ")")
eq(#ctx.cards, 1, "exactly one card")
truthy(ctx.cards[1] ~= nil and string.find(ctx.cards[1], "BLOOD MOON", 1, true) ~= nil, "naming the Blood Moon (" .. tostring(ctx.cards[1]) .. ")")
truthy(ctx.cards[1] ~= nil and string.find(ctx.cards[1], "RISES", 1, true) == nil, "quietly: a returning player is told where they are, not congratulated again")
eq(flashes, 0, "no celebration flash")
local want = blood.colorCorrection.TintColor
local t = rgb255(cc.TintColor)
truthy(math.abs(t[1] - want[1]) <= 3 and math.abs(t[2] - want[2]) <= 3 and math.abs(t[3] - want[3]) <= 3,
	string.format("the grade glided to the Blood Moon's tint (%d,%d,%d)", t[1], t[2], t[3]))
truthy(maxStep <= 4, "with no single-frame jump (largest step " .. maxStep .. "/255)")
truthy(ctx.restBtn.Visible, "and the rest button is offered in the safehouse")

--================================================================ survive night 20: same band, nothing new

-- back to the store's own UpdateAsync (the slow one was for the load; saves would yield inside a prompt)
ctx.store.UpdateAsync = nil

ctx.surviveNights(1, 0.1)
ctx.seconds(3, 0.1)
eq((ctx.lastState() or {}).night, 21, "night 20 survived: night 21")
eq(#ctx.cards, 1, "still the Blood Moon: no second card")
eq(flashes, 0, "and no flash")

--================================================================ a respawn

local char2 = h.Players:simulateSpawn(ctx.me, h.workspace)
ctx.char, ctx.hrp, ctx.hum = char2, char2:FindFirstChild("HumanoidRootPart"), char2:FindFirstChildOfClass("Humanoid")
ctx.hum.FloorMaterial = Enum.Material.WoodPlanks
ctx.hum.MoveDirection = Vector3.new(0, 0, 0)
ctx.hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
ctx.seconds(3, 0.1)
eq(#ctx.cards, 1, "a respawn re-announces nothing")
eq(flashes, 0, "and flashes nothing")
truthy(ctx.chip.Visible and string.find(ctx.chip.Text, "Night 21", 1, true) ~= nil, "the chip carries on (" .. ctx.chip.Text .. ")")

ctx.finish("nightwatchmanor join")

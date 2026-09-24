-- Spec for EnvBus: the one-way line from the environment client (Env.client) to the HUD. Run: luau tests/EnvBus.spec.luau
--
-- Both LocalScripts require the same ModuleScript, and Roblox hands every script on one client the same
-- table, so a plain Lua list of handlers is a local bus: no Instance, nothing that could replicate. The
-- HUD draws hazard warnings and the rest line in the places its own layout already fits (and the HUD
-- check already measures), instead of a second GUI guessing where the HUD's panels are.
-- EnvBus.new() makes a private bus for tests; the module itself is the shared one.
local EnvBus = require("../src/shared/EnvBus")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

do
	local bus = EnvBus.new()
	local got = {}
	local off = bus.on(function(kind, data) table.insert(got, kind .. ":" .. tostring(data and data.v)) end)
	bus.fire("hazard", { v = 1 })
	bus.fire("rest", { v = 2 })
	eq(#got, 2, "a handler hears every message")
	eq(got[1], "hazard:1", "…in order")
	eq(got[2], "rest:2", "…with its data")
	eq(bus.last("rest").v, 2, "the last message of a kind is kept (a late listener can catch up)")
	eq(bus.last("nothing"), nil, "…nil for a kind never sent")
	off()
	bus.fire("hazard", { v = 3 })
	eq(#got, 2, "after unsubscribing, nothing more arrives")
	eq(bus.last("hazard").v, 3, "…but the bus still remembers the latest")
end

do
	local bus = EnvBus.new()
	local second = 0
	bus.on(function() error("a broken listener") end)
	bus.on(function() second += 1 end)
	local ok = pcall(bus.fire, "hazard", {})
	truthy(ok, "a listener that errors does not break the sender")
	eq(second, 1, "…nor the listeners after it")
end

do
	truthy(type(EnvBus.on) == "function" and type(EnvBus.fire) == "function" and type(EnvBus.last) == "function",
		"the module itself is a bus (what the two client scripts share)")
	local a, b = EnvBus.new(), EnvBus.new()
	local heard = 0
	a.on(function() heard += 1 end)
	b.fire("x", {})
	eq(heard, 0, "two private buses do not hear each other")
end

print(string.format("EnvBus: %d passed, %d failed", passed, failed))

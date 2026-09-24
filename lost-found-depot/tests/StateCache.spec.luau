-- Spec for StateCache: the HUD hands every State payload it receives to the wings, so the wings never
-- need their own listener on the State remote.
-- Run: luau tests/StateCache.spec.luau
--
-- WHY. Roblox queues a RemoteEvent fired before any client listener is connected and delivers the queue
-- to the FIRST connection. The server pushes the loaded profile at join, usually before a phone has
-- started its LocalScripts, so that push sits in the queue. With a second listener (the wings) racing the
-- HUD, whichever script connected first would get it and the other would wait until the next push: a HUD
-- with no cash, hotbar or tutorial hint, or a returning veteran in the first wing. So the HUD stays the
-- ONLY listener, as before the wings, and passes each payload on here; the wings read it every frame.
local StateCache = require("../src/shared/StateCache")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

do
	local st, v = StateCache.get()
	eq(st, nil, "nothing received yet: no state")
	eq(v, 0, "... at version 0")
	local a = { loaded = true, shifts = 3 }
	StateCache.set(a)
	st, v = StateCache.get()
	eq(st, a, "the payload the HUD received is the one the wings read")
	eq(v, 1, "... and the version moved, so a reader can tell a new payload from an old one")
	StateCache.set("not a table")
	st, v = StateCache.get()
	eq(st, a, "a malformed payload is ignored (the HUD ignores it too)")
	eq(v, 1, "... and does not bump the version")
	StateCache.set(nil)
	eq((StateCache.get()), a, "nil is ignored")
	local b = { loaded = true, shifts = 4 }
	StateCache.set(b)
	st, v = StateCache.get()
	eq(st, b, "the latest payload wins")
	eq(v, 2, "version 2")
	StateCache.set(b)
	local _, v3 = StateCache.get()
	eq(v3, 3, "the same table sent again is still a new push (a re-send counts)")
end

print(string.format("StateCache: %d passed, %d failed", passed, failed))

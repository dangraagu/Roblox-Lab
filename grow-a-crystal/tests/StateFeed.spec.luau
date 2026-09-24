-- Spec for StateFeed: ONE listener on the State remote, shared by every client script.
-- Run: luau tests/StateFeed.spec.luau
--
-- WHY. Roblox queues a RemoteEvent fired at a client before any listener is connected and hands the whole
-- queue to the FIRST connection only. The server pushes the player's profile (State) at join, usually before
-- the LocalScripts have started. Hud.client and Grotto.client both need it, and Roblox does not define which
-- of them starts first: with two connections, one of them lost the join push, and a returning player's HUD
-- read "💎 0" until their first click (adversarial review 2026-09-24, finding 1;
-- robloxemu/check_growacrystal_queue*.luau replay the queue rule against the real scripts).
--
-- So there is exactly one connection, made by whichever script asks first, and every script SUBSCRIBES to
-- it. What this spec pins:
--   * one connection per remote, however many scripts ask for the feed;
--   * a payload that arrived before a script subscribed is handed to it when it subscribes (the latest
--     one only: State is a full snapshot, so the latest is the whole truth);
--   * every later payload reaches every subscriber once, in order, with every argument intact;
--   * who subscribes first changes nothing about what each ends up with;
--   * each call goes through the injected `spawn` (task.spawn in the game), so a subscriber that errors or
--     yields cannot stop the others, as with separate connections;
--   * pure: the remote and the spawner are arguments (require("./X") is invalid in Roblox).
local StateFeed = require("../src/shared/StateFeed")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then passed += 1 else failed += 1; print("FAIL:", msg) end
end

-- a stand-in for a RemoteEvent: OnClientEvent with Connect, and a way to fire it as the engine would
local function fakeRemote()
	local sig = { conns = {}, connects = 0 }
	function sig:Connect(fn)
		self.connects += 1
		table.insert(self.conns, fn)
		return { Disconnect = function() end }
	end
	local remote = { OnClientEvent = sig }
	function remote.fire(...)
		for _, fn in table.clone(sig.conns) do fn(...) end
	end
	return remote, sig
end

-- the game passes task.spawn; here: run it now, and count the calls
local spawned = 0
local function spawn(fn, ...)
	spawned += 1
	fn(...)
end

--=========================================================================== one connection
do
	local remote, sig = fakeRemote()
	local a = StateFeed.of(remote, spawn)
	local b = StateFeed.of(remote, spawn)
	eq(a, b, "every script asking for the same remote gets the same feed")
	eq(sig.connects, 1, "... and the remote gets exactly one connection")
	local other = fakeRemote()
	truthy(StateFeed.of(other, spawn) ~= a, "a different remote gets its own feed")
	eq(sig.connects, 1, "... without touching the first remote")
	local ok = pcall(StateFeed.of, fakeRemote(), nil)
	truthy(not ok, "a feed without a spawner is refused (a nil here would only fail on the first push)")
end

--=========================================================================== the queue rule
do
	-- the join push reaches the ONE connection before any script has subscribed
	local remote = fakeRemote()
	local feed = StateFeed.of(remote, spawn)
	remote.fire({ dust = 523456, chambers = 8 })
	local got = nil
	feed:subscribe(function(s) got = s end)
	truthy(got ~= nil and got.dust == 523456, "a script that subscribes after the join push still gets it")
end

do
	-- the first script subscribes, the push arrives, then the second script subscribes
	local remote = fakeRemote()
	local feed = StateFeed.of(remote, spawn)
	local hud, grotto = {}, {}
	feed:subscribe(function(s) table.insert(grotto, s.n) end)
	remote.fire({ n = 1 })
	remote.fire({ n = 2 })
	feed:subscribe(function(s) table.insert(hud, s.n) end)
	eq(table.concat(grotto, ","), "1,2", "the first subscriber got both pushes, in order")
	eq(table.concat(hud, ","), "2", "the late subscriber gets the LATEST push only, once (State is a full snapshot)")
	remote.fire({ n = 3 })
	eq(table.concat(grotto, ","), "1,2,3", "later pushes reach the first subscriber once")
	eq(table.concat(hud, ","), "2,3", "... and the late one once")
end

do
	-- nothing has arrived yet: subscribing hands over nothing
	local remote = fakeRemote()
	local feed = StateFeed.of(remote, spawn)
	local calls = 0
	feed:subscribe(function() calls += 1 end)
	eq(calls, 0, "no payload yet: a subscriber is not called with nothing")
	remote.fire({ n = 1 })
	eq(calls, 1, "and is called once when the first one arrives")
end

--=========================================================================== order does not matter
do
	local function finalFor(order: string): string
		local remote = fakeRemote()
		local feed = StateFeed.of(remote, spawn)
		local last = { A = "-", B = "-" }
		local function sub(name)
			feed:subscribe(function(s) last[name] = s.v end)
		end
		remote.fire({ v = "join" })
		if order == "AB" then sub("A"); sub("B") else sub("B"); sub("A") end
		return last.A .. "/" .. last.B
	end
	eq(finalFor("AB"), "join/join", "HUD first: both scripts end up with the join push")
	eq(finalFor("BA"), "join/join", "cavern first: both scripts end up with the join push")
end

--=========================================================================== arguments survive
do
	local remote = fakeRemote()
	local feed = StateFeed.of(remote, spawn)
	remote.fire("a", nil, 3)
	local n, a, b, c = -1, nil, nil, nil
	feed:subscribe(function(...)
		n = select("#", ...)
		a, b, c = ...
	end)
	eq(n, 3, "a replayed push keeps all its arguments, nil holes included")
	eq(a, "a", "(first)")
	eq(b, nil, "(second, nil)")
	eq(c, 3, "(third)")
	remote.fire("x", nil, nil, 4)
	eq(n, 4, "a live push keeps all its arguments too")
end

--=========================================================================== isolation
do
	local remote = fakeRemote()
	local feed = StateFeed.of(remote, spawn)
	local before = spawned
	feed:subscribe(function() end)
	feed:subscribe(function() end)
	remote.fire({})
	eq(spawned - before, 2, "every subscriber is called through the spawner, one call each")

	-- with task.spawn, an error in one subscriber is reported on its own thread and the next still runs;
	-- modelled with a spawner that isolates the call the same way
	local remote2 = fakeRemote()
	local errors = 0
	local feed2 = StateFeed.of(remote2, function(fn, ...)
		if not pcall(fn, ...) then errors += 1 end
	end)
	local reached = false
	feed2:subscribe(function() error("a broken subscriber") end)
	feed2:subscribe(function() reached = true end)
	remote2.fire({})
	eq(errors, 1, "the broken subscriber failed on its own")
	truthy(reached, "... and the next subscriber still got the push")
end

do
	-- a script that subscribes from inside a delivery gets that payload once, not twice
	local remote = fakeRemote()
	local feed = StateFeed.of(remote, spawn)
	local inner = 0
	local added = false
	feed:subscribe(function()
		if not added then
			added = true
			feed:subscribe(function() inner += 1 end)
		end
	end)
	remote.fire({ n = 1 })
	eq(inner, 1, "subscribed during a delivery: that payload arrives exactly once")
	remote.fire({ n = 2 })
	eq(inner, 2, "... and the next one once")
end

print(string.format("StateFeed: %d passed, %d failed", passed, failed))
if failed > 0 then error("StateFeed spec failed", 0) end

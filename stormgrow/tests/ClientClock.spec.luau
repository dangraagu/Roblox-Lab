-- Spec for ClientClock: the client's copy of the server clock. Run: luau tests/ClientClock.spec.luau
--
-- The server writes workspace ServerNow once a second. Growth bars, the forecast and the sky run on the
-- client's extrapolation of it, capped at ClientExtrapolateMax (1.5 s), so a stalled server never lets a
-- client run ahead and show a crop ripe that the server would refuse.
local ClientClock = require("../src/shared/ClientClock")

local passed, failed = 0, 0
local function approx(a, b, msg)
	if type(a) == "number" and math.abs(a - b) <= 1e-9 then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end

approx(ClientClock.extrapolate(1000, 50, 50, 1.5), 1000, "right at the broadcast: the server's value")
approx(ClientClock.extrapolate(1000, 50, 50.4, 1.5), 1000.4, "0.4 s later: +0.4")
approx(ClientClock.extrapolate(1000, 50, 60, 1.5), 1001.5, "a stalled server: at most +1.5")
approx(ClientClock.extrapolate(1000, 50, 49, 1.5), 1000, "a local clock that ran backwards never subtracts")

print(string.format("ClientClock: %d passed, %d failed", passed, failed))
assert(failed == 0, "ClientClock tests failed")

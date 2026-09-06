-- Tests for emu/instance.luau. Run: luau tests/instance.spec.luau
--
-- datatypes.luau is written by another agent, so this spec injects a TINY local fake with
-- only the shape instance.luau actually touches (CFrame.Position, Vector3, Color3.fromRGB).
local InstanceLib = require("../emu/instance")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then
		passed += 1
	else
		failed += 1
		print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg)
	if c then
		passed += 1
	else
		failed += 1
		print("FAIL:", msg)
	end
end
local function raises(fn, msg)
	local ok = pcall(fn)
	if not ok then
		passed += 1
	else
		failed += 1
		print("FAIL:", msg, "-> expected an error, got none")
	end
end

-- ---------------------------------------------------------------- fake datatypes
local V3 = {}
V3.__index = V3
function V3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end

local CF = {}
CF.__index = CF
function CF.new(x, y, z)
	if type(x) == "table" then
		return setmetatable({ Position = x }, CF)
	end
	return setmetatable({ Position = V3.new(x, y, z) }, CF)
end

local fakeDatatypes = {
	Vector3 = V3,
	CFrame = CF,
	Color3 = {
		fromRGB = function(r, g, b)
			return { R = r, G = g, B = b }
		end,
	},
}

local api = InstanceLib.new({ datatypes = fakeDatatypes })
local Instance = api.Instance
local Signal = api.Signal

-- ---------------------------------------------------------------- basics
do
	local p = Instance.new("Part")
	eq(p.ClassName, "Part", "ClassName is the constructed class")
	eq(p.Name, "Part", "Name defaults to the class name")
	p.Name = "Floor"
	eq(p.Name, "Floor", "Name is assignable")
	eq(p.Parent, nil, "a fresh Instance has no Parent")
	raises(function()
		(p :: any).ClassName = "Model"
	end, "ClassName is read-only")
end

-- ---------------------------------------------------------------- parenting / reparenting
do
	local a = Instance.new("Folder")
	a.Name = "A"
	local b = Instance.new("Folder")
	b.Name = "B"
	local child = Instance.new("Part")
	child.Name = "Child"

	child.Parent = a
	eq(child.Parent, a, "Parent assignment sets Parent")
	eq(#a:GetChildren(), 1, "A has one child")
	eq(a:GetChildren()[1], child, "GetChildren returns the child")
	eq(#b:GetChildren(), 0, "B has no children yet")

	-- reparent: must LEAVE the old child list, not be in both
	child.Parent = b
	eq(child.Parent, b, "reparent moves Parent")
	eq(#a:GetChildren(), 0, "reparenting removes it from the old parent")
	eq(#b:GetChildren(), 1, "reparenting adds it to the new parent")

	child.Parent = nil
	eq(child.Parent, nil, "Parent = nil unparents")
	eq(#b:GetChildren(), 0, "unparenting removes it from the child list")

	-- GetChildren must hand back a COPY: mutating it cannot corrupt the tree
	child.Parent = a
	local kids = a:GetChildren()
	table.remove(kids, 1)
	eq(#a:GetChildren(), 1, "GetChildren returns a copy, not the live list")

	-- constructor's second argument parents immediately
	local direct = Instance.new("Part", a)
	eq(direct.Parent, a, "Instance.new(class, parent) parents immediately")

	-- circular references are refused
	local outer = Instance.new("Folder")
	local inner = Instance.new("Folder")
	inner.Parent = outer
	raises(function()
		outer.Parent = inner
	end, "circular parenting raises")
end

-- ---------------------------------------------------------------- ChildAdded
do
	local parent = Instance.new("Folder")
	local seen = nil
	parent.ChildAdded:Connect(function(c)
		seen = c
	end)
	local kid = Instance.new("Part")
	kid.Parent = parent
	eq(seen, kid, "ChildAdded fires with the new child")
end

-- ---------------------------------------------------------------- find / descendants
do
	local zone = Instance.new("Model")
	zone.Name = "Zone"
	local lights = Instance.new("Folder", zone)
	lights.Name = "Lights"
	local fixture = Instance.new("Part", lights)
	fixture.Name = "Fixture1"
	local pl = Instance.new("PointLight", fixture)
	pl.Name = "PL"
	local iv = Instance.new("IntValue", zone)
	iv.Name = "Day"

	eq(zone:FindFirstChild("Lights"), lights, "FindFirstChild finds a direct child")
	eq(zone:FindFirstChild("Fixture1"), nil, "FindFirstChild is NOT recursive by default")
	eq(zone:FindFirstChild("Fixture1", true), fixture, "FindFirstChild(name, true) recurses")
	eq(zone:FindFirstChild("PL", true), pl, "recursive FindFirstChild reaches grandchildren")
	eq(zone:FindFirstChild("Nope", true), nil, "recursive FindFirstChild returns nil when absent")

	eq(zone:FindFirstChildOfClass("IntValue"), iv, "FindFirstChildOfClass matches ClassName")
	eq(zone:FindFirstChildOfClass("Part"), nil, "FindFirstChildOfClass is not recursive")
	eq(zone:FindFirstChildWhichIsA("ValueBase"), iv, "FindFirstChildWhichIsA uses the class chain")
	eq(zone:FindFirstChildWhichIsA("BasePart", true), fixture, "FindFirstChildWhichIsA recurses when asked")

	eq(#zone:GetDescendants(), 4, "GetDescendants walks the whole subtree")
	truthy(pl:IsDescendantOf(zone), "IsDescendantOf walks up")
	eq(fixture:GetFullName(), "Zone.Lights.Fixture1", "GetFullName joins the ancestry")
end

-- ---------------------------------------------------------------- IsA
do
	local part = Instance.new("Part")
	truthy(part:IsA("Part"), "Part IsA Part")
	truthy(part:IsA("BasePart"), "Part IsA BasePart")
	truthy(part:IsA("Instance"), "Part IsA Instance")
	eq(part:IsA("Model"), false, "Part is not a Model")

	local label = Instance.new("TextLabel")
	truthy(label:IsA("TextLabel"), "TextLabel IsA TextLabel")
	truthy(label:IsA("GuiObject"), "TextLabel IsA GuiObject")
	truthy(label:IsA("Instance"), "TextLabel IsA Instance")
	eq(label:IsA("BasePart"), false, "TextLabel is not a BasePart")

	-- classes with no hierarchy entry still reach Instance
	local corner = Instance.new("UICorner")
	truthy(corner:IsA("Instance"), "UICorner IsA Instance")
	local madeUp = Instance.new("TotallyNewClass")
	truthy(madeUp:IsA("Instance"), "an unknown class is still an Instance")
	eq(madeUp:IsA("Part"), false, "an unknown class is not a Part")

	truthy(Instance.new("ObjectValue"):IsA("ValueBase"), "ObjectValue IsA ValueBase")
	truthy(Instance.new("PointLight"):IsA("Light"), "PointLight IsA Light")
end

-- ---------------------------------------------------------------- WaitForChild
do
	local parent = Instance.new("Folder")
	parent.Name = "ReplicatedStorage"
	local cfg = Instance.new("Folder", parent)
	cfg.Name = "Config"

	eq(parent:WaitForChild("Config"), cfg, "WaitForChild returns an existing child immediately")
	eq(parent:WaitForChild("Missing", 5), nil, "WaitForChild honours the timeout contract (nil)")
	raises(function()
		parent:WaitForChild("Missing")
	end, "WaitForChild with no timeout raises instead of hanging")
end

-- ---------------------------------------------------------------- Destroy
do
	local parent = Instance.new("Folder")
	local child = Instance.new("Part", parent)
	child.Name = "Doomed"
	local grand = Instance.new("PointLight", child)

	local destroying = 0
	child.Destroying:Connect(function()
		destroying += 1
	end)
	local fired = 0
	local conn = child.ChildAdded:Connect(function()
		fired += 1
	end)

	child:Destroy()
	eq(child.Parent, nil, "Destroy unparents")
	eq(#parent:GetChildren(), 0, "Destroy removes it from the parent's child list")
	eq(parent:FindFirstChild("Doomed"), nil, "a destroyed child is no longer findable")
	eq(destroying, 1, "Destroying fires exactly once")
	eq(conn.Connected, false, "Destroy disconnects the instance's signals")
	eq(grand.Parent, nil, "Destroy cascades to descendants")

	child:Destroy() -- idempotent
	eq(destroying, 1, "a second Destroy is a no-op")
	raises(function()
		child.Parent = parent
	end, "the Parent of a destroyed instance is locked")

	-- ClearAllChildren (the anomaly server rebuilds every pass with this)
	local zone = Instance.new("Model")
	Instance.new("Part", zone)
	Instance.new("Part", zone)
	Instance.new("Folder", zone)
	eq(#zone:GetChildren(), 3, "zone starts with three children")
	zone:ClearAllChildren()
	eq(#zone:GetChildren(), 0, "ClearAllChildren empties the model")
end

-- ---------------------------------------------------------------- Clone
do
	local src = Instance.new("Model")
	src.Name = "Rig"
	local part = Instance.new("Part", src)
	part.Name = "Torso"
	part.Transparency = 0.25
	part.CustomGameProperty = "hello"
	src:SetAttribute("Index", 7)
	local light = Instance.new("PointLight", part)
	light.Brightness = 3
	local ref = Instance.new("ObjectValue", src)
	ref.Name = "L1"
	ref.Value = part

	local copy = src:Clone()
	eq(copy.Parent, nil, "a clone is unparented")
	eq(copy.Name, "Rig", "clone keeps the Name")
	eq(copy.ClassName, "Model", "clone keeps the ClassName")
	eq(copy:GetAttribute("Index"), 7, "clone copies attributes")
	eq(#copy:GetChildren(), 2, "clone copies children")

	local copyPart = copy:FindFirstChild("Torso")
	truthy(copyPart ~= nil, "clone contains the child part")
	truthy(copyPart ~= part, "the cloned child is a NEW object")
	eq(copyPart.Transparency, 0.25, "clone copies known properties")
	eq(copyPart.CustomGameProperty, "hello", "clone copies unknown properties too")
	eq(copyPart:FindFirstChildOfClass("PointLight").Brightness, 3, "clone is deep (grandchildren)")

	-- mutating the copy must not touch the original
	copyPart.Transparency = 1
	eq(part.Transparency, 0.25, "mutating a clone leaves the original alone")

	-- references INTO the cloned subtree are rewired to the copies
	eq(copy:FindFirstChild("L1").Value, copyPart, "clone rewires internal Instance references")
	eq(ref.Value, part, "the original's reference is untouched")
end

-- ---------------------------------------------------------------- attributes
do
	local zone = Instance.new("Model")
	eq(zone:GetAttribute("Index"), nil, "an unset attribute reads back nil")
	zone:SetAttribute("Index", 3)
	eq(zone:GetAttribute("Index"), 3, "SetAttribute / GetAttribute round-trip")
	zone:SetAttribute("Index", 4)
	eq(zone:GetAttribute("Index"), 4, "SetAttribute overwrites")
	zone:SetAttribute("Label", "north")
	eq(zone:GetAttribute("Label"), "north", "attributes hold strings too")
	eq(zone:GetAttributes().Index, 4, "GetAttributes returns the whole set")
	-- attributes are NOT properties
	eq((zone :: any).Index, nil, "an attribute is not readable as a property")

	local changed = 0
	zone:GetAttributeChangedSignal("Index"):Connect(function()
		changed += 1
	end)
	zone:SetAttribute("Index", 5)
	zone:SetAttribute("Index", 5) -- same value: no change
	eq(changed, 1, "GetAttributeChangedSignal fires only on a real change")
end

-- ---------------------------------------------------------------- properties
do
	local p = Instance.new("Part")
	-- SPEC hard rule 5: unknown property writes succeed SILENTLY
	local ok = pcall(function()
		(p :: any).ThisPropertyDoesNotExist = 42
		;(p :: any).AlsoFake = { nested = true }
	end)
	truthy(ok, "an unknown property write does not raise")
	eq((p :: any).ThisPropertyDoesNotExist, 42, "an unknown property reads back what was written")
	eq((p :: any).NeverWritten, nil, "an unset property reads back nil (no error)")

	-- unknown METHOD calls must raise, so real gaps surface
	raises(function()
		return (p :: any):TotallyMadeUpMethod()
	end, "an unknown method call raises")

	-- Position is derived from CFrame, exactly as in Roblox
	p.CFrame = CF.new(1, 2, 3)
	eq(p.Position.X, 1, "Position.X comes from CFrame")
	eq(p.Position.Y, 2, "Position.Y comes from CFrame")
	p.Position = V3.new(5, 6, 7)
	eq(p.Position.X, 5, "assigning Position updates the position")
	eq(p.CFrame.Position.Z, 7, "assigning Position rebuilds the CFrame")

	-- defaults built from the injected datatypes
	eq(Instance.new("Part").Anchored, false, "Part.Anchored defaults to false")
	eq(Instance.new("Part").Size.X, 4, "Part.Size default comes from injected Vector3")

	-- GetPropertyChangedSignal
	local hits = 0
	local frame = Instance.new("Frame")
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		hits += 1
	end)
	frame.Visible = true
	frame.Visible = true -- unchanged
	frame.Visible = false
	eq(hits, 2, "GetPropertyChangedSignal fires only when the value actually changes")
end

-- ---------------------------------------------------------------- Signal
do
	local sig = Signal.new("Test")
	local calls, lastA, lastB = 0, nil, nil
	local conn = sig:Connect(function(a, b)
		calls += 1
		lastA, lastB = a, b
	end)
	local other = 0
	sig:Connect(function()
		other += 1
	end)

	sig:Fire("x", 2)
	eq(calls, 1, "a connected handler runs on Fire")
	eq(lastA, "x", "Fire passes the first argument")
	eq(lastB, 2, "Fire passes the second argument")
	eq(other, 1, "every connected handler runs")

	eq(conn.Connected, true, "a fresh connection is Connected")
	eq(sig:GetConnectionCount(), 2, "the signal holds both connections")
	conn:Disconnect()
	eq(conn.Connected, false, "Disconnect clears Connected")
	eq(sig:GetConnectionCount(), 1, "Disconnect DROPS the connection (it does not just flag it)")
	sig:Fire("y")
	eq(calls, 1, "a disconnected handler no longer runs")
	eq(other, 2, "the other handler still runs")

	conn:Disconnect() -- idempotent
	eq(other, 2, "a second Disconnect is a no-op")
	eq(sig:GetConnectionCount(), 1, "a second Disconnect does not drop somebody else's connection")

	-- reconnect/disconnect churn must not leak: the anomaly server rebuilds its prompt
	-- handlers every pass, so a leak here compounds over a whole headless run
	local churn = Signal.new("Churn")
	for _ = 1, 50 do
		churn:Connect(function() end):Disconnect()
	end
	eq(churn:GetConnectionCount(), 0, "connect/disconnect churn leaves no connections behind")

	-- nils must survive the argument round-trip
	local sawSecond = "unset"
	local nilSig = Signal.new("Nils")
	nilSig:Connect(function(_a, b)
		sawSecond = b
	end)
	nilSig:Fire(1, nil, 3)
	eq(sawSecond, nil, "Fire preserves embedded nil arguments")

	-- Once
	local onceCalls = 0
	local onceSig = Signal.new("Once")
	onceSig:Once(function()
		onceCalls += 1
	end)
	onceSig:Fire()
	onceSig:Fire()
	eq(onceCalls, 1, "Once fires at most once")

	-- disconnecting inside a handler must not skip the remaining handlers
	local seq = {}
	local s2 = Signal.new("Reentrant")
	local c1
	c1 = s2:Connect(function()
		table.insert(seq, "a")
		c1:Disconnect()
	end)
	s2:Connect(function()
		table.insert(seq, "b")
	end)
	s2:Fire()
	eq(table.concat(seq, ","), "a,b", "disconnecting mid-fire does not skip later handlers")

	raises(function()
		(sig :: any):Connect("not a function")
	end, "Connect rejects a non-function")
end

-- ---------------------------------------------------------------- ProximityPrompt / ClickDetector
do
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "ADVANCE"
	eq(prompt.ActionText, "ADVANCE", "ProximityPrompt holds ActionText")
	local who = nil
	prompt.Triggered:Connect(function(plr)
		who = plr
	end)
	local fakePlayer = Instance.new("Player")
	prompt.Triggered:Fire(fakePlayer)
	eq(who, fakePlayer, "ProximityPrompt.Triggered carries the player")

	local cd = Instance.new("ClickDetector")
	local clicks = 0
	cd.MouseClick:Connect(function()
		clicks += 1
	end)
	cd.MouseClick:Fire(fakePlayer)
	eq(clicks, 1, "ClickDetector.MouseClick fires")

	raises(function()
		(prompt :: any).Triggered = 1
	end, "assigning over an event raises")
end

-- ---------------------------------------------------------------- RemoteEvent / RemoteFunction
do
	local remote = Instance.new("RemoteEvent")
	remote.Name = "State"
	local p1 = Instance.new("Player")
	p1.Name = "Alice"
	local p2 = Instance.new("Player")
	p2.Name = "Bob"

	eq(#remote:getSent(), 0, "a fresh RemoteEvent has recorded nothing")
	remote:FireClient(p1, { day = 3, best = 7 })
	remote:FireClient(p2, { day = 1, best = 1 })
	remote:FireAllClients("shutdown", 5)

	local sent = remote:getSent()
	eq(#sent, 3, "FireClient / FireAllClients are recorded")
	eq(sent[1].player, p1, "the first payload went to Alice")
	eq(sent[1].all, false, "FireClient is not a broadcast")
	eq(sent[1].args[1].day, 3, "the recorded payload is the table that was sent")
	eq(sent[2].player, p2, "the second payload went to Bob")
	eq(sent[3].all, true, "FireAllClients is flagged as a broadcast")
	eq(sent[3].player, nil, "a broadcast has no single player")
	eq(sent[3].args[1], "shutdown", "the broadcast's first argument is recorded")
	eq(sent[3].args[2], 5, "the broadcast's second argument is recorded")
	eq(sent[3].args.n, 2, "the recorded argument count is exact")

	eq(#remote:sentTo(p1), 2, "sentTo(Alice) = her packet + the broadcast")
	eq(#remote:sentTo(p2), 2, "sentTo(Bob) = his packet + the broadcast")
	remote:clearSent()
	eq(#remote:getSent(), 0, "clearSent resets the recorder")

	-- FireClient also drives OnClientEvent so client-side code can be exercised
	local onClient = nil
	remote.OnClientEvent:Connect(function(payload)
		onClient = payload
	end)
	remote:FireClient(p1, "hud")
	eq(onClient, "hud", "FireClient reaches OnClientEvent")

	-- client -> server
	local gotPlayer, gotCode = nil, nil
	remote.OnServerEvent:Connect(function(plr, code)
		gotPlayer, gotCode = plr, code
	end)
	remote:simulateFireServer(p2, "FREEBIE")
	eq(gotPlayer, p2, "simulateFireServer delivers the firing player")
	eq(gotCode, "FREEBIE", "simulateFireServer delivers the arguments")

	local fn = Instance.new("RemoteFunction")
	raises(function()
		return fn:InvokeServer("x")
	end, "InvokeServer raises while OnServerInvoke is unset")
	fn.OnServerInvoke = function(plr, a, b)
		return plr, a + b
	end
	local who, sum = fn:simulateInvokeServer(p1, 2, 3)
	eq(who, p1, "OnServerInvoke receives the player first")
	eq(sum, 5, "OnServerInvoke returns through simulateInvokeServer")
end

-- ---------------------------------------------------------------- GUI classes just exist
do
	for _, class in { "ScreenGui", "Frame", "TextLabel", "TextButton", "UICorner", "UIStroke", "UIListLayout" } do
		local g = Instance.new(class)
		eq(g.ClassName, class, class .. " can be constructed")
		local ok = pcall(function()
			(g :: any).Text = "hi"
			;(g :: any).ZIndex = 4
		end)
		truthy(ok, class .. " holds arbitrary properties")
	end
	local gui = Instance.new("ScreenGui")
	local frame = Instance.new("Frame", gui)
	Instance.new("UICorner", frame)
	eq(#gui:GetDescendants(), 2, "GUI classes nest like any other Instance")
end

print(string.format("instance: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("instance tests failed")
end

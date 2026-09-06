--!nolint LocalShadow
-- instance.luau — headless `Instance` for robloxemu.
--
-- Owns: Instance.new, the hierarchy, properties, Attributes, and a small Signal type.
-- Does NOT own datatypes (Vector3/CFrame/Color3/Enum/...) — those arrive by DEPENDENCY
-- INJECTION so this file never races emu/datatypes.luau:
--
--     local InstanceLib = require("./instance")
--     local api = InstanceLib.new({ datatypes = <the datatypes table> })
--     local Instance = api.Instance   -- api.Instance.new("Part") ...
--
-- Design notes that matter for fidelity (SPEC.md "Fidelity over convenience"):
--  * UNKNOWN PROPERTY WRITES SUCCEED SILENTLY. Roblox game code sets a long tail of
--    properties; refusing them would make every scene build explode. They are stored and
--    read back verbatim, so the scene dumper can still see them.
--  * READING an unset property returns nil (never raises).
--  * UNKNOWN METHOD CALLS RAISE. `inst:NoSuchMethod()` resolves to nil and calling nil is
--    an error naming the method — a real gap surfaces instead of silently no-op'ing.
--  * WaitForChild NEVER HANGS. The headless tree is built synchronously, so an existing
--    child is returned immediately. A missing child returns nil when a timeout was given
--    (Roblox's timeout contract) and RAISES an "infinite yield" error when none was, which
--    is exactly the failure a real Roblox server would log.
--  * Instance state lives in a single private field `__emu`. Every key beginning with `__`
--    bypasses the property machinery, so it can never collide with a Roblox property name.

local InstanceLib = {}

-- ---------------------------------------------------------------- class hierarchy (data)
-- Only what :IsA() needs. Anything NOT listed is treated as a direct child of Instance,
-- so `Instance.new("UICorner"):IsA("Instance")` is true without an entry.
local DEFAULT_CLASS_PARENT: { [string]: string } = {
	-- 3D
	PVInstance = "Instance",
	Model = "PVInstance",
	BasePart = "PVInstance",
	Part = "BasePart",
	MeshPart = "BasePart",
	WedgePart = "Part",
	TrussPart = "BasePart",
	SpawnLocation = "Part",
	Seat = "Part",
	Terrain = "BasePart",
	-- values
	ValueBase = "Instance",
	IntValue = "ValueBase",
	NumberValue = "ValueBase",
	StringValue = "ValueBase",
	BoolValue = "ValueBase",
	ObjectValue = "ValueBase",
	CFrameValue = "ValueBase",
	Vector3Value = "ValueBase",
	Color3Value = "ValueBase",
	-- lights / fx
	Light = "Instance",
	PointLight = "Light",
	SpotLight = "Light",
	SurfaceLight = "Light",
	PostEffect = "Instance",
	BloomEffect = "PostEffect",
	BlurEffect = "PostEffect",
	ColorCorrectionEffect = "PostEffect",
	DepthOfFieldEffect = "PostEffect",
	SunRaysEffect = "PostEffect",
	-- constraints / misc 3D
	Constraint = "Instance",
	WeldConstraint = "Instance",
	Attachment = "Instance",
	Trail = "Instance",
	Beam = "Instance",
	ParticleEmitter = "Instance",
	ClickDetector = "Instance",
	ProximityPrompt = "Instance",
	Sound = "Instance",
	Humanoid = "Instance",
	-- GUI
	GuiBase = "Instance",
	GuiBase2d = "GuiBase",
	GuiObject = "GuiBase2d",
	Frame = "GuiObject",
	ScrollingFrame = "GuiObject",
	GuiLabel = "GuiObject",
	GuiButton = "GuiObject",
	TextLabel = "GuiLabel",
	ImageLabel = "GuiLabel",
	TextButton = "GuiButton",
	ImageButton = "GuiButton",
	TextBox = "GuiObject",
	ViewportFrame = "GuiObject",
	VideoFrame = "GuiObject",
	LayerCollector = "GuiBase2d",
	ScreenGui = "LayerCollector",
	BillboardGui = "LayerCollector",
	SurfaceGui = "LayerCollector",
	-- UI modifiers
	UIBase = "Instance",
	UIComponent = "UIBase",
	UIConstraint = "UIComponent",
	UILayout = "UIComponent",
	UIGridStyleLayout = "UILayout",
	UIListLayout = "UIGridStyleLayout",
	UIGridLayout = "UIGridStyleLayout",
	UIPageLayout = "UIGridStyleLayout",
	UITableLayout = "UILayout",
	UICorner = "UIComponent",
	UIStroke = "UIComponent",
	UIGradient = "UIComponent",
	UIPadding = "UIComponent",
	UIScale = "UIComponent",
	UIAspectRatioConstraint = "UIConstraint",
	UISizeConstraint = "UIConstraint",
	UITextSizeConstraint = "UIConstraint",
	-- containers / services (services.luau adds its own on top)
	Folder = "Instance",
	Configuration = "Instance",
	Camera = "Instance",
	Player = "Instance",
	RemoteEvent = "Instance",
	RemoteFunction = "Instance",
	BindableEvent = "Instance",
	BindableFunction = "Instance",
	Tween = "Instance",
	Atmosphere = "Instance",
	Sky = "Instance",
}

-- ---------------------------------------------------------------- Signal
local Signal = {}
Signal.__index = Signal

function Signal.new(name: string?)
	return setmetatable({ __name = name or "Signal", __conns = {} }, Signal)
end

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local conns = self._signal.__conns
	for i, c in conns do
		if c == self then
			table.remove(conns, i)
			break
		end
	end
end
Connection.disconnect = Connection.Disconnect

function Signal:Connect(fn)
	if type(fn) ~= "function" then
		error("Signal:Connect expects a function, got " .. typeof(fn), 2)
	end
	local conn = setmetatable({ Connected = true, _signal = self, _fn = fn }, Connection)
	table.insert(self.__conns, conn)
	return conn
end
Signal.connect = Signal.Connect

-- Roblox's :Once — fires at most once, then disconnects itself.
function Signal:Once(fn)
	if type(fn) ~= "function" then
		error("Signal:Once expects a function, got " .. typeof(fn), 2)
	end
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

-- Fire every currently-connected handler. Iterates a SNAPSHOT so a handler may connect or
-- disconnect during the fire without skipping/duplicating anybody (Roblox behaves this way,
-- and our game code disconnects inside handlers).
function Signal:Fire(...)
	local snapshot = table.clone(self.__conns)
	local args = table.pack(...)
	for _, conn in snapshot do
		if conn.Connected then
			conn._fn(table.unpack(args, 1, args.n))
		end
	end
end

-- Emulator-only introspection. A long headless run reconnects prompt handlers every pass;
-- if Disconnect only flipped a flag without dropping the connection, the list would grow
-- without bound and Fire would get slower for the whole run.
function Signal:GetConnectionCount(): number
	return #self.__conns
end

function Signal:DisconnectAll()
	local snapshot = table.clone(self.__conns)
	table.clear(self.__conns)
	for _, conn in snapshot do
		conn.Connected = false
	end
end

-- Headless: there is no scheduler in this file, so a blocking Wait would deadlock the run.
-- Raise loudly instead of hanging (see SPEC.md hard rule 5 — real gaps must surface).
function Signal:Wait()
	error("robloxemu: " .. tostring(self.__name) .. ":Wait() is not supported headlessly (use :Connect)", 2)
end

InstanceLib.Signal = Signal

-- ---------------------------------------------------------------- factory
-- deps = { datatypes = <table from emu/datatypes.luau> }
function InstanceLib.new(deps)
	deps = deps or {}
	local dt = deps.datatypes or {}

	-- shared, mutable so services.luau can point it at Players.LocalPlayer
	local config = { getLocalPlayer = nil }

	local CLASS_PARENT: { [string]: string } = table.clone(DEFAULT_CLASS_PARENT)
	local CLASS: { [string]: any } = {}
	local infoCache: { [string]: any } = {}

	local function try(fn, ...)
		local ok, v = pcall(fn, ...)
		if ok then
			return v
		end
		return nil
	end

	-- ------------------------------------------------------------ class registry
	local function defineClass(className: string, spec)
		assert(type(className) == "string", "defineClass: className must be a string")
		CLASS[className] = spec
		if spec.parent then
			CLASS_PARENT[className] = spec.parent
		end
		infoCache = {} -- a later definition must not be shadowed by a cached flattening
	end

	-- Class chain, most-derived first, always terminating at "Instance".
	local function chainOf(className: string)
		local out, c, guard = {}, className, 0
		while c ~= nil and guard < 64 do
			table.insert(out, c)
			local p = CLASS_PARENT[c]
			if p == nil and c ~= "Instance" then
				p = "Instance" -- unknown class => direct child of Instance
			end
			c = p
			guard += 1
		end
		return out
	end

	local function classInfo(className: string)
		local cached = infoCache[className]
		if cached then
			return cached
		end
		local chain = chainOf(className)
		local info = { methods = {}, events = {}, defaults = {}, getters = {}, setters = {}, inits = {} }
		-- base -> derived so a derived class overrides its base
		for i = #chain, 1, -1 do
			local spec = CLASS[chain[i]]
			if spec then
				if spec.methods then
					for k, v in spec.methods do
						info.methods[k] = v
					end
				end
				if spec.events then
					for _, e in spec.events do
						info.events[e] = true
					end
				end
				if spec.defaults then
					for k, v in spec.defaults do
						info.defaults[k] = v
					end
				end
				if spec.init then
					table.insert(info.inits, spec.init)
				end
			end
		end
		-- computed get/set run derived-first, so a subclass can intercept before its base
		for i = 1, #chain do
			local spec = CLASS[chain[i]]
			if spec then
				if spec.get then
					table.insert(info.getters, spec.get)
				end
				if spec.set then
					table.insert(info.setters, spec.set)
				end
			end
		end
		infoCache[className] = info
		return info
	end

	-- ------------------------------------------------------------ core object
	local InstanceMT = {}

	local function isInstance(v): boolean
		return type(v) == "table" and getmetatable(v) == InstanceMT and rawget(v, "__emu") ~= nil
	end

	local function stateOf(inst)
		return rawget(inst, "__emu")
	end

	local function getSignal(inst, name)
		local st = stateOf(inst)
		local sig = st.signals[name]
		if not sig then
			sig = Signal.new(st.className .. "." .. name)
			st.signals[name] = sig
		end
		return sig
	end

	-- Fire only if somebody ever asked for the signal. Building a Signal per part per event
	-- would allocate thousands of dead tables while a scene is built.
	local function fireIfExists(inst, name, ...)
		local sig = stateOf(inst).signals[name]
		if sig then
			sig:Fire(...)
		end
	end

	local function isA(inst, className: string): boolean
		if type(className) ~= "string" then
			return false
		end
		local c, guard = stateOf(inst).className, 0
		while c ~= nil and guard < 64 do
			if c == className then
				return true
			end
			local p = CLASS_PARENT[c]
			if p == nil and c ~= "Instance" then
				p = "Instance"
			end
			c = p
			guard += 1
		end
		return false
	end

	local function fullName(inst): string
		local parts, node, guard = {}, inst, 0
		while node ~= nil and guard < 128 do
			table.insert(parts, 1, tostring(stateOf(node).props.Name))
			node = stateOf(node).parent
			guard += 1
		end
		return table.concat(parts, ".")
	end

	local function removeChild(parent, child)
		local kids = stateOf(parent).children
		for i, c in kids do
			if c == child then
				table.remove(kids, i)
				return
			end
		end
	end

	-- The one place Parent is mutated. `internal` skips the destroyed-lock so Destroy can
	-- unparent the very instance it is locking.
	local function setParent(inst, newParent, internal: boolean?)
		local st = stateOf(inst)
		if newParent ~= nil and not isInstance(newParent) then
			error(
				string.format(
					"Unable to assign property Parent. Instance expected, got %s",
					typeof(newParent)
				),
				3
			)
		end
		if st.destroyed and newParent ~= nil and not internal then
			error(
				string.format(
					"The Parent property of %s is locked, current parent: NULL, new parent %s",
					tostring(st.props.Name),
					tostring(stateOf(newParent).props.Name)
				),
				3
			)
		end
		local old = st.parent
		if old == newParent then
			return
		end
		if newParent ~= nil then
			-- circular-reference guard: walking UP from newParent must never reach inst
			local node, guard = newParent, 0
			while node ~= nil and guard < 512 do
				if node == inst then
					error(
						string.format(
							"Attempt to set parent of %s to %s would result in circular reference",
							fullName(inst),
							tostring(stateOf(newParent).props.Name)
						),
						3
					)
				end
				node = stateOf(node).parent
				guard += 1
			end
		end
		if old ~= nil then
			removeChild(old, inst)
		end
		st.parent = newParent
		if newParent ~= nil then
			table.insert(stateOf(newParent).children, inst)
		end
		if old ~= nil then
			fireIfExists(old, "ChildRemoved", inst)
		end
		if newParent ~= nil then
			fireIfExists(newParent, "ChildAdded", inst)
		end
		fireIfExists(inst, "AncestryChanged", inst, newParent)
	end

	local create -- forward (Clone / services need it)

	InstanceMT.__index = function(self, key)
		-- private emulator state / test hooks never touch the property machinery
		if type(key) == "string" and string.sub(key :: string, 1, 2) == "__" then
			return rawget(self, key)
		end
		local st = rawget(self, "__emu")
		local info = classInfo(st.className)
		local m = info.methods[key]
		if m ~= nil then
			return m
		end
		if info.events[key] then
			return getSignal(self, key)
		end
		for _, get in info.getters do
			local v = get(self, key)
			if v ~= nil then
				return v
			end
		end
		local prop = st.props[key]
		if prop ~= nil then
			return prop
		end
		-- Dot access falls through to a CHILD, exactly as in Roblox: `ReplicatedStorage.Config`
		-- is the ModuleScript named "Config". Our shared modules rely on this — several use the
		-- dual-path idiom `(script and require(script.Parent.Rng)) or require("./Rng")` so the
		-- same file works in Roblox and under the luau CLI, and without child lookup the Roblox
		-- branch handed `require` a nil.
		if type(key) == "string" then
			for _, child in st.children do
				if rawget(child, "__emu").props.Name == key then
					return child
				end
			end
		end
		-- Unset property and no such child -> nil (never raises). Calling a nil member raises
		-- naturally and Luau names the method in the error, which is the "surface the gap"
		-- behaviour we want.
		return nil
	end

	InstanceMT.__newindex = function(self, key, value)
		if type(key) == "string" and string.sub(key :: string, 1, 2) == "__" then
			rawset(self, key, value)
			return
		end
		local st = rawget(self, "__emu")
		local info = classInfo(st.className)
		if key == "Parent" then
			setParent(self, value)
			return
		end
		if key == "ClassName" then
			error("Unable to assign property ClassName. Property is read-only", 2)
		end
		if info.events[key] then
			error(string.format("Unable to assign property %s. Property is read-only", tostring(key)), 2)
		end
		if info.methods[key] ~= nil then
			error(string.format("Unable to assign property %s. It is a method of %s", tostring(key), st.className), 2)
		end
		if key == "Name" then
			value = tostring(value)
		end
		local old = st.props[key]
		for _, set in info.setters do
			if set(self, key, value) == true then
				if old ~= value then
					local ps = st.propSignals[key]
					if ps then
						ps:Fire()
					end
				end
				return
			end
		end
		st.props[key] = value
		if old ~= value then
			local ps = st.propSignals[key]
			if ps then
				ps:Fire()
			end
		end
	end

	InstanceMT.__tostring = function(self)
		return tostring(rawget(self, "__emu").props.Name)
	end

	-- ------------------------------------------------------------ base methods
	local baseMethods = {}

	baseMethods.IsA = function(self, className)
		return isA(self, className)
	end

	baseMethods.GetChildren = function(self)
		return table.clone(stateOf(self).children)
	end
	baseMethods.getChildren = baseMethods.GetChildren

	baseMethods.GetDescendants = function(self)
		local out = {}
		local function walk(node)
			for _, c in stateOf(node).children do
				table.insert(out, c)
				walk(c)
			end
		end
		walk(self)
		return out
	end

	baseMethods.FindFirstChild = function(self, name, recursive)
		for _, c in stateOf(self).children do
			if stateOf(c).props.Name == name then
				return c
			end
		end
		if recursive then
			for _, c in stateOf(self).children do
				local found = baseMethods.FindFirstChild(c, name, true)
				if found then
					return found
				end
			end
		end
		return nil
	end
	baseMethods.findFirstChild = baseMethods.FindFirstChild

	baseMethods.FindFirstChildOfClass = function(self, className)
		for _, c in stateOf(self).children do
			if stateOf(c).className == className then
				return c
			end
		end
		return nil
	end

	baseMethods.FindFirstChildWhichIsA = function(self, className, recursive)
		for _, c in stateOf(self).children do
			if isA(c, className) then
				return c
			end
		end
		if recursive then
			for _, c in stateOf(self).children do
				local found = baseMethods.FindFirstChildWhichIsA(c, className, true)
				if found then
					return found
				end
			end
		end
		return nil
	end

	baseMethods.FindFirstAncestor = function(self, name)
		local node = stateOf(self).parent
		while node ~= nil do
			if stateOf(node).props.Name == name then
				return node
			end
			node = stateOf(node).parent
		end
		return nil
	end

	baseMethods.FindFirstAncestorOfClass = function(self, className)
		local node = stateOf(self).parent
		while node ~= nil do
			if stateOf(node).className == className then
				return node
			end
			node = stateOf(node).parent
		end
		return nil
	end

	baseMethods.IsDescendantOf = function(self, other)
		local node = stateOf(self).parent
		while node ~= nil do
			if node == other then
				return true
			end
			node = stateOf(node).parent
		end
		return false
	end

	-- Headless tree is built synchronously, so an existing child is the answer immediately.
	-- Missing + timeout  -> nil  (Roblox's documented timeout return).
	-- Missing + no timeout -> raise (a real Roblox server would hang here; we say so).
	baseMethods.WaitForChild = function(self, name, timeout)
		local found = baseMethods.FindFirstChild(self, name)
		if found then
			return found
		end
		if timeout ~= nil then
			return nil
		end
		error(
			string.format(
				"robloxemu: Infinite yield possible on '%s:WaitForChild(\"%s\")' — the child does not exist and the emulator cannot yield",
				fullName(self),
				tostring(name)
			),
			2
		)
	end

	baseMethods.GetFullName = function(self)
		return fullName(self)
	end

	baseMethods.GetPropertyChangedSignal = function(self, propertyName)
		local st = stateOf(self)
		local sig = st.propSignals[propertyName]
		if not sig then
			sig = Signal.new(st.className .. "." .. tostring(propertyName) .. "Changed")
			st.propSignals[propertyName] = sig
		end
		return sig
	end

	baseMethods.SetAttribute = function(self, name, value)
		local st = stateOf(self)
		if type(name) ~= "string" then
			error("SetAttribute: attribute name must be a string", 2)
		end
		local old = st.attributes[name]
		st.attributes[name] = value
		if old ~= value then
			local sig = st.attrSignals[name]
			if sig then
				sig:Fire()
			end
			fireIfExists(self, "AttributeChanged", name)
		end
	end

	baseMethods.GetAttribute = function(self, name)
		return stateOf(self).attributes[name]
	end

	baseMethods.GetAttributes = function(self)
		return table.clone(stateOf(self).attributes)
	end

	baseMethods.GetAttributeChangedSignal = function(self, name)
		local st = stateOf(self)
		local sig = st.attrSignals[name]
		if not sig then
			sig = Signal.new(st.className .. ".Attribute:" .. tostring(name))
			st.attrSignals[name] = sig
		end
		return sig
	end

	local function destroy(self)
		local st = stateOf(self)
		if st.destroyed then
			return
		end
		fireIfExists(self, "Destroying")
		setParent(self, nil, true)
		st.destroyed = true
		for _, c in table.clone(st.children) do
			destroy(c)
		end
		for _, sig in st.signals do
			sig:DisconnectAll()
		end
		for _, sig in st.propSignals do
			sig:DisconnectAll()
		end
		for _, sig in st.attrSignals do
			sig:DisconnectAll()
		end
	end

	baseMethods.Destroy = function(self)
		destroy(self)
	end
	baseMethods.destroy = baseMethods.Destroy

	baseMethods.ClearAllChildren = function(self)
		for _, c in table.clone(stateOf(self).children) do
			destroy(c)
		end
	end

	-- Deep copy: children + properties + attributes. The clone is UNPARENTED (Roblox).
	-- References that pointed INSIDE the copied subtree are rewired to the copies — an
	-- ObjectValue in a cloned Folder must not keep pointing at the original's part.
	baseMethods.Clone = function(self)
		local map = {}
		local function copyOf(src)
			local st = stateOf(src)
			local copy = create(st.className)
			local cst = stateOf(copy)
			for k, v in st.props do
				cst.props[k] = v
			end
			for k, v in st.attributes do
				cst.attributes[k] = v
			end
			map[src] = copy
			for _, child in st.children do
				local cc = copyOf(child)
				stateOf(cc).parent = copy
				table.insert(cst.children, cc)
			end
			return copy
		end
		local root = copyOf(self)
		for _, new in map do
			local props = stateOf(new).props
			for k, v in props do
				local mapped = map[v]
				if mapped ~= nil then
					props[k] = mapped
				end
			end
		end
		return root
	end

	-- ------------------------------------------------------------ built-in classes
	defineClass("Instance", {
		events = {
			"ChildAdded",
			"ChildRemoved",
			"DescendantAdded",
			"DescendantRemoving",
			"Destroying",
			"AncestryChanged",
			"AttributeChanged",
			"Changed",
		},
		methods = baseMethods,
		get = function(self, key)
			local st = rawget(self, "__emu")
			if key == "ClassName" then
				return st.className
			end
			if key == "Parent" then
				return st.parent
			end
			return nil
		end,
	})

	defineClass("PVInstance", {
		parent = "Instance",
		methods = {
			GetPivot = function(self)
				local st = stateOf(self)
				local primary = st.props.PrimaryPart
				if primary ~= nil and isInstance(primary) then
					return primary.CFrame
				end
				return st.props.CFrame or rawget(self, "__pivot")
			end,
			PivotTo = function(self, cf)
				local st = stateOf(self)
				rawset(self, "__pivot", cf)
				local primary = st.props.PrimaryPart
				if primary ~= nil and isInstance(primary) then
					-- Move the whole model by the delta when the injected CFrame supports the
					-- maths; otherwise fall back to placing the primary part (documented
					-- approximation — headless scenes only ever read the result back).
					local old = primary.CFrame
					local delta = old ~= nil and try(function()
						return cf * old:Inverse()
					end) or nil
					if delta ~= nil then
						local moved = false
						for _, d in baseMethods.GetDescendants(self) do
							if isA(d, "BasePart") then
								local ncf = try(function()
									return delta * d.CFrame
								end)
								if ncf ~= nil then
									d.CFrame = ncf
									moved = true
								end
							end
						end
						if moved then
							return
						end
					end
					primary.CFrame = cf
					return
				end
				st.props.CFrame = cf
			end,
			MoveTo = function(self, position)
				local st = stateOf(self)
				local primary = st.props.PrimaryPart
				if primary ~= nil and isInstance(primary) then
					primary.Position = position
				else
					st.props.Position = position
				end
			end,
			SetPrimaryPartCFrame = function(self, cf)
				local primary = stateOf(self).props.PrimaryPart
				if primary ~= nil and isInstance(primary) then
					primary.CFrame = cf
				end
			end,
			GetPrimaryPartCFrame = function(self)
				local primary = stateOf(self).props.PrimaryPart
				return primary ~= nil and primary.CFrame or nil
			end,
		},
	})

	defineClass("Model", { parent = "PVInstance" })

	-- BasePart: Position is DERIVED from CFrame, exactly as in Roblox, so scene dumps and
	-- distance checks (`(hrp.Position - pad.Position).Magnitude`) read the truth after a
	-- `part.CFrame = ...` write.
	local basePartDefaults = {
		Anchored = false,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
		Transparency = 0,
		Reflectance = 0,
	}
	if dt.Vector3 and dt.Vector3.new then
		basePartDefaults.Size = try(dt.Vector3.new, 4, 1, 2)
	end
	if dt.CFrame and dt.CFrame.new then
		basePartDefaults.CFrame = try(dt.CFrame.new, 0, 0, 0)
	end
	if dt.Color3 and dt.Color3.fromRGB then
		basePartDefaults.Color = try(dt.Color3.fromRGB, 163, 162, 165)
	end

	local function cframePosition(cf)
		if cf == nil then
			return nil
		end
		local p = try(function()
			return cf.Position
		end)
		if p ~= nil then
			return p
		end
		return try(function()
			return cf.p
		end)
	end

	defineClass("BasePart", {
		parent = "PVInstance",
		defaults = basePartDefaults,
		events = { "Touched", "TouchEnded" },
		methods = {
			SetNetworkOwner = function() end,
			SetNetworkOwnershipAuto = function() end,
			GetNetworkOwner = function()
				return nil
			end,
			BreakJoints = function() end,
			ApplyImpulse = function() end,
		},
		get = function(self, key)
			if key == "Position" then
				local st = rawget(self, "__emu")
				local p = cframePosition(st.props.CFrame)
				if p ~= nil then
					return p
				end
				return st.props.Position
			end
			return nil
		end,
		set = function(self, key, value)
			if key == "Position" then
				local st = rawget(self, "__emu")
				st.props.Position = value
				-- Approximation: rebuilding the CFrame from a bare position DROPS rotation.
				-- Roblox keeps it; our games only ever write whole CFrames, and read Position.
				if dt.CFrame and dt.CFrame.new then
					local cf = try(dt.CFrame.new, value)
					if cf ~= nil then
						st.props.CFrame = cf
					end
				end
				return true
			end
			return false
		end,
	})

	defineClass("Part", { parent = "BasePart" })
	defineClass("SpawnLocation", { parent = "Part" })

	defineClass("ProximityPrompt", {
		parent = "Instance",
		events = { "Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan" },
		defaults = { ActionText = "", ObjectText = "", HoldDuration = 0, MaxActivationDistance = 10, Enabled = true },
	})

	defineClass("ClickDetector", {
		parent = "Instance",
		events = { "MouseClick", "RightMouseClick", "MouseHoverEnter", "MouseHoverLeave" },
		defaults = { MaxActivationDistance = 32 },
	})

	defineClass("Humanoid", {
		parent = "Instance",
		events = { "Died", "HealthChanged", "MoveToFinished", "StateChanged", "Touched" },
		defaults = { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50 },
		methods = {
			MoveTo = function(self, position)
				rawset(self, "__moveTarget", position)
				fireIfExists(self, "MoveToFinished", true)
			end,
			TakeDamage = function(self, amount)
				local st = stateOf(self)
				st.props.Health = math.max(0, (st.props.Health or 100) - (tonumber(amount) or 0))
				fireIfExists(self, "HealthChanged", st.props.Health)
				if st.props.Health <= 0 then
					fireIfExists(self, "Died")
				end
			end,
			ChangeState = function() end,
			GetState = function()
				return nil
			end,
		},
	})

	defineClass("Player", {
		parent = "Instance",
		events = { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Idled", "Chatted" },
		defaults = { UserId = 0, Character = nil, AccountAge = 0, MembershipType = "None" },
		methods = {
			IsFriendsWith = function()
				return false
			end,
			GetMouse = function()
				return nil
			end,
			Kick = function(self, reason)
				rawset(self, "__kicked", reason or true)
			end,
			LoadCharacter = function(self)
				error("robloxemu: Player:LoadCharacter() is not implemented (use Players:simulateSpawn)", 2)
			end,
		},
	})

	-- RemoteEvent — the payload RECORDER. Every FireClient/FireAllClients is appended to
	-- `__sent` so a test can assert exactly what the HUD would have received; this is how we
	-- verify client-visible state without a client.
	defineClass("RemoteEvent", {
		parent = "Instance",
		events = { "OnServerEvent", "OnClientEvent" },
		init = function(self)
			rawset(self, "__sent", {})
		end,
		methods = {
			FireClient = function(self, player, ...)
				table.insert(rawget(self, "__sent"), { player = player, all = false, args = table.pack(...) })
				fireIfExists(self, "OnClientEvent", ...)
			end,
			FireAllClients = function(self, ...)
				table.insert(rawget(self, "__sent"), { player = nil, all = true, args = table.pack(...) })
				fireIfExists(self, "OnClientEvent", ...)
			end,
			FireServer = function(self, ...)
				local plr = config.getLocalPlayer and config.getLocalPlayer() or nil
				getSignal(self, "OnServerEvent"):Fire(plr, ...)
			end,
			-- TEST HOOK: pretend `player`'s client fired this remote.
			simulateFireServer = function(self, player, ...)
				getSignal(self, "OnServerEvent"):Fire(player, ...)
			end,
			-- TEST HOOKS: everything recorded, everything sent to one player, and a reset.
			getSent = function(self)
				return rawget(self, "__sent")
			end,
			sentTo = function(self, player)
				local out = {}
				for _, rec in rawget(self, "__sent") do
					if rec.all or rec.player == player then
						table.insert(out, rec)
					end
				end
				return out
			end,
			clearSent = function(self)
				table.clear(rawget(self, "__sent"))
			end,
		},
	})

	defineClass("RemoteFunction", {
		parent = "Instance",
		methods = {
			InvokeServer = function(self, ...)
				local fn = stateOf(self).props.OnServerInvoke
				if type(fn) ~= "function" then
					error(
						string.format("robloxemu: OnServerInvoke is not set on %s", fullName(self)),
						2
					)
				end
				local plr = config.getLocalPlayer and config.getLocalPlayer() or nil
				return fn(plr, ...)
			end,
			-- TEST HOOK: invoke as a specific player (there is no LocalPlayer on a server).
			simulateInvokeServer = function(self, player, ...)
				local fn = stateOf(self).props.OnServerInvoke
				if type(fn) ~= "function" then
					error(
						string.format("robloxemu: OnServerInvoke is not set on %s", fullName(self)),
						2
					)
				end
				return fn(player, ...)
			end,
			InvokeClient = function(self, _player, ...)
				local fn = stateOf(self).props.OnClientInvoke
				if type(fn) ~= "function" then
					return nil
				end
				return fn(...)
			end,
		},
	})

	defineClass("BindableEvent", {
		parent = "Instance",
		events = { "Event" },
		methods = {
			Fire = function(self, ...)
				getSignal(self, "Event"):Fire(...)
			end,
		},
	})

	defineClass("BindableFunction", {
		parent = "Instance",
		methods = {
			Invoke = function(self, ...)
				local fn = stateOf(self).props.OnInvoke
				if type(fn) ~= "function" then
					return nil
				end
				return fn(...)
			end,
		},
	})

	-- GUI + UI classes need almost no behaviour — the hierarchy table above gives them
	-- :IsA("GuiObject") and the generic property bag gives them everything else.
	--
	-- The exception is the handful of properties Roblox COMPUTES rather than stores. Our HUDs
	-- read them: `UIListLayout.AbsoluteContentSize` is what every ScrollingFrame divides to get
	-- its CanvasSize, and reading nil there is a crash, not a wrong number. These are the zero
	-- values Roblox reports for an empty layout, seeded so the code runs; nothing here performs
	-- any actual layout, so a check that needs real geometry must compute it itself (see
	-- Harness.guiRects).
	if dt.Vector2 then
		local zero2 = dt.Vector2.zero
		defineClass("UIGridStyleLayout", { defaults = { AbsoluteContentSize = zero2 } })
		defineClass("GuiBase2d", { defaults = { AbsoluteSize = zero2, AbsolutePosition = zero2 } })
	end
	-- Same reasoning for the UI modifiers whose default our code divides by or compares
	-- against. A UIScale created and never assigned reads 1 in Roblox, and dividing by the nil
	-- we used to return crashed the HUD before it drew anything.
	defineClass("UIScale", { defaults = { Scale = 1 } })
	defineClass("UIStroke", { defaults = { Thickness = 1, Transparency = 0, Enabled = true } })
	defineClass("UIAspectRatioConstraint", { defaults = { AspectRatio = 1 } })

	-- The GUI input events. Every HUD button wires `Activated:Connect(...)` at construction, so
	-- without these a client script cannot even finish loading. They also give a headless run the
	-- only handle it has on the UI: `button.Activated:Fire()` is how a test presses a button.
	-- Roblox gives every GuiObject a zero Size/Position/AnchorPoint, and code reads them back
	-- (the geometry walk in Harness.guiRects does, for one). Returning nil instead made a frame
	-- that was never explicitly positioned look like "not a GUI object at all".
	local zeroUDim2 = if dt.UDim2 then dt.UDim2.new(0, 0, 0, 0) else nil
	defineClass("GuiObject", {
		defaults = {
			Visible = true,
			Active = false,
			ZIndex = 1,
			Size = zeroUDim2,
			Position = zeroUDim2,
			AnchorPoint = if dt.Vector2 then dt.Vector2.zero else nil,
		},
		events = {
			"InputBegan", "InputEnded", "InputChanged",
			"MouseEnter", "MouseLeave", "MouseMoved",
			"TouchTap", "TouchLongPress", "TouchPan",
			"SelectionGained", "SelectionLost",
		},
	})
	defineClass("GuiButton", {
		events = {
			"Activated",
			"MouseButton1Click", "MouseButton1Down", "MouseButton1Up",
			"MouseButton2Click", "MouseButton2Down", "MouseButton2Up",
		},
	})
	defineClass("TextBox", {
		events = { "Focused", "FocusLost", "ReturnPressedFromOnScreenKeyboard" },
	})

	-- ------------------------------------------------------------ constructor
	create = function(className, parent)
		if type(className) ~= "string" then
			error("Instance.new expects a className string, got " .. typeof(className), 3)
		end
		local st = {
			className = className,
			props = { Name = className },
			children = {},
			parent = nil,
			attributes = {},
			signals = {},
			propSignals = {},
			attrSignals = {},
			destroyed = false,
		}
		local obj = setmetatable({}, InstanceMT)
		rawset(obj, "__emu", st)
		local info = classInfo(className)
		for k, v in info.defaults do
			st.props[k] = v
		end
		for _, init in info.inits do
			init(obj)
		end
		if parent ~= nil then
			setParent(obj, parent)
		end
		return obj
	end

	local Instance = {}
	Instance.new = function(className, parent)
		return create(className, parent)
	end

	return {
		Instance = Instance,
		Signal = Signal,
		-- construction / registration for services.luau + the harness
		create = create,
		defineClass = defineClass,
		classParent = CLASS_PARENT,
		-- helpers
		isInstance = isInstance,
		isA = isA,
		getSignal = getSignal,
		fireIfExists = fireIfExists,
		stateOf = stateOf,
		-- services.luau points this at Players.LocalPlayer for RemoteEvent:FireServer
		config = config,
		datatypes = dt,
	}
end

return InstanceLib

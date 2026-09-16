-- FxClient.luau — client-only visual juice: camera shake, full-screen flash/vignette,
-- FOV punch, and HUD theming helpers (UICorner / UIStroke / UIGradient). Code-only.
-- Server never calls this; it touches the local Camera + PlayerGui only.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local FxClient = {}

local function camera(): Camera?
	return workspace.CurrentCamera
end

-- Decaying camera shake for `duration` seconds at `magnitude` studs/rad. Additive on top of
-- whatever the default camera does (bound just after the camera render step, unbound at end).
function FxClient.shake(duration: number, magnitude: number)
	if not RunService:IsClient() then return end
	local cam = camera()
	if not cam then return end
	local elapsed = 0
	local name = "FxShake_" .. tostring(math.random(1, 1e6))
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt)
		elapsed += dt
		local k = 1 - math.min(elapsed / duration, 1)
		local m = magnitude * k * k
		local c = camera()
		if c then
			c.CFrame = c.CFrame * CFrame.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
				* CFrame.Angles((math.random() - 0.5) * m * 0.03, (math.random() - 0.5) * m * 0.03, 0)
		end
		if elapsed >= duration then
			RunService:UnbindFromRenderStep(name)
		end
	end)
end

-- Momentary FOV punch (in then back).
function FxClient.fovPunch(delta: number, outTime: number?, backTime: number?)
	if not RunService:IsClient() then return end
	local cam = camera()
	if not cam then return end
	local base = cam.FieldOfView
	local up = TweenService:Create(cam, TweenInfo.new(outTime or 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base + delta })
	up:Play()
	up.Completed:Connect(function()
		TweenService:Create(cam, TweenInfo.new(backTime or 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base }):Play()
	end)
end

-- Full-screen colour flash that fades out (jumpscare / damage vignette).
function FxClient.flash(color: Color3, holdAlpha: number?, fadeTime: number?)
	if not RunService:IsClient() then return end
	local plr = Players.LocalPlayer
	local pg = plr and plr:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "FxFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999
	gui.ResetOnSpawn = false
	gui.Parent = pg
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - (holdAlpha or 0.55)
	f.BorderSizePixel = 0
	f.Parent = gui
	local tw = TweenService:Create(f, TweenInfo.new(fadeTime or 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	tw:Play()
	tw.Completed:Connect(function()
		gui:Destroy()
	end)
end

-- ---------------------------------------------------------------- HUD theming
-- Round + stroke a Frame/Button. opts = { corner=number, stroke=Color3, strokeThickness=number,
-- gradient={Color3, Color3}, gradientRotation=number }
function FxClient.theme(gui: GuiObject, opts)
	opts = opts or {}
	if opts.corner ~= false then
		local c = gui:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, opts.corner or 10)
		c.Parent = gui
	end
	if opts.stroke then
		local s = gui:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		s.Color = opts.stroke
		s.Thickness = opts.strokeThickness or 1.5
		s.Transparency = opts.strokeTransparency or 0.2
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = gui
	end
	if opts.gradient then
		local g = gui:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
		g.Color = ColorSequence.new(opts.gradient[1], opts.gradient[2])
		g.Rotation = opts.gradientRotation or 90
		g.Parent = gui
	end
	return gui
end

-- Fade + slide a GuiObject in from a small offset (call once when it appears).
function FxClient.popIn(gui: GuiObject, fromOffset: UDim2?, time: number?)
	if not RunService:IsClient() then return end
	local target = gui.Position
	gui.Position = target + (fromOffset or UDim2.fromOffset(0, 12))
	local startT = {}
	for _, prop in { "BackgroundTransparency" } do
		startT[prop] = (gui :: any)[prop]
	end
	TweenService:Create(gui, TweenInfo.new(time or 0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = target }):Play()
end

return FxClient

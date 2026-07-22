--!strict
-- Spiller lyd lokalt for DENNE spilleren, styrt av Sounds-modulen. Reagerer på
-- server-Fx (mynt / edelsten / knapp / død) og på nivå-fullført (medalje/rekord).
-- Alt er myk-feilende: mangler en remote eller en lyd, blir det bare stille.

local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local okMod, Sounds = pcall(function() return require(RS:WaitForChild("Sounds", 10)) end)
if not okMod or typeof(Sounds) ~= "table" then return end

local function makeSound(cfg)
	local s = Instance.new("Sound")
	s.SoundId = cfg.id
	s.Volume = cfg.volume or 0.5
	s.PlaybackSpeed = cfg.speed or 1
	s.Parent = SoundService
	return s
end

-- Forhåndslag én gjenbrukbar Sound pr Fx-nøkkel.
local fxSounds = {}
if typeof(Sounds.Fx) == "table" then
	for key, cfg in pairs(Sounds.Fx) do
		if typeof(cfg) == "table" and cfg.id then fxSounds[key] = makeSound(cfg) end
	end
end

local function play(key)
	if not Sounds.Enabled then return end
	local s = fxSounds[key]
	if s then
		s.TimePosition = 0
		s:Play()
	end
end

-- Server-Fx + nivå-fullført.
local hud = RS:WaitForChild("HudRemotes", 15)
if hud then
	local fx = hud:WaitForChild("Fx", 10)
	if fx then
		fx.OnClientEvent:Connect(function(key)
			if typeof(key) == "string" then pcall(play, key) end
		end)
	end
	local complete = hud:WaitForChild("LevelComplete", 10)
	if complete then
		complete.OnClientEvent:Connect(function(data)
			if typeof(data) ~= "table" then return end
			if data.isNewRecord then
				play("record")
			elseif data.medal and data.medal ~= "none" then
				play("medal")
			else
				play("complete")
			end
		end)
	end
end

-- Bakgrunnsmusikk (valgfritt — kun hvis MusicId er satt).
if Sounds.Enabled and typeof(Sounds.MusicId) == "string" and Sounds.MusicId ~= "" then
	local music = Instance.new("Sound")
	music.SoundId = Sounds.MusicId
	music.Volume = Sounds.MusicVolume or 0.15
	music.Looped = true
	music.Parent = SoundService
	pcall(function() music:Play() end)
end

--!strict
-- Lyd-oppsett. SFX bruker en INNEBYGD Roblox-lyd (rbxasset://...) som alltid
-- funker, så spillet lager lyd uten noe oppsett. Vil du ha finere/egne lyder?
-- Bytt id-ene under med gratis lyder fra Creator Store -> Audio i Studio
-- (lim inn "rbxassetid://<tall>"). En id som ikke lastes gir bare stillhet +
-- en advarsel — aldri krasj. Sett Enabled=false for å skru av all lyd.
-- Musikk er AV til du legger inn en MusicId.

local PING = "rbxasset://sounds/electronicpingshort.wav"

local Sounds = {}
Sounds.Enabled = true
Sounds.MusicId = ""            -- legg inn en rbxassetid:// loop for bakgrunnsmusikk
Sounds.MusicVolume = 0.15

-- volume 0-1, speed = PlaybackSpeed (pitch). Vi varierer én ping for variasjon;
-- bytt gjerne hver enkelt til en egen, penere lyd.
Sounds.Fx = {
	coin     = { id = PING, volume = 0.45, speed = 1.0 },
	gem      = { id = PING, volume = 0.60, speed = 1.5 },
	button   = { id = PING, volume = 0.50, speed = 0.8 },
	death    = { id = PING, volume = 0.60, speed = 0.5 },
	complete = { id = PING, volume = 0.60, speed = 1.3 },
	medal    = { id = PING, volume = 0.70, speed = 1.7 },
	record   = { id = PING, volume = 0.90, speed = 2.0 },
	shield   = { id = PING, volume = 0.60, speed = 1.1 },
}

return Sounds

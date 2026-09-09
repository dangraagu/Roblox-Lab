-- MazeRef.luau — ett sted som svarer på "hvilken mappe i workspace er MIN labyrint?".
--
-- Hvorfor den finnes: tema-butikken og minikartet var DØDE i live-spillet. Begge lette etter
-- `workspace.MazeGame`, men live-byggeren `buildInstance` navngir mappa `Maze_<id>` — det er
-- bare den ubrukte `buildLevel` (CONFIG.UseLobby = false) som noen gang lager en `MazeGame`.
-- Så `recolorAll` returnerte på første linje hver eneste gang, og minikartet fant aldri noe å
-- tegne. 17 vegg-temaer til 500-2000 mynter og en perk til 800 mynter tok betalt for ingenting.
--
-- Å bare bytte navnet holder ikke. Med per-spiller-instanser står det mange `Maze_<id>`-mapper
-- der samtidig, én pr aktiv spiller, så en klient som tar den første ville farget om eller tegnet
-- kart over en ANNEN spillers labyrint. Serveren merker derfor spilleren med sin egen mappe
-- (`placeInInstance` setter attributtet, `teardownPlayerInstance` fjerner det), og alt som
-- trenger labyrinten spør her.
--
-- Modulen rører ingen Roblox-API selv: workspace og spilleren kommer inn som argumenter, slik at
-- oppslaget kan enhetstestes fra luau-CLI-en. Den require-er heller ingenting — en bar
-- streng-require løser seg i CLI-en og er UGYLDIG i Roblox, og denne fila kjører i begge.
--
-- Bruk fra et klientskript:
--   local MazeRef = require(ReplicatedStorage:WaitForChild("MazeRef"))
--   local folder = MazeRef.folder(workspace, player)
--   player:GetAttributeChangedSignal(MazeRef.ATTRIBUTE):Connect(...)   -- bytter instans

local MazeRef = {}

-- Kontrakt mellom serveren og de tre klientskriptene. Endres denne strengen ett sted uten de
-- andre, er temaene og minikartet døde igjen — testene låser den derfor eksplisitt.
MazeRef.ATTRIBUTE = "MazeFolder"

-- Navnet den delte labyrinten har på rollback-stien (CONFIG.UseLobby = false). Der finnes ingen
-- instanser, så attributtet settes aldri, og alt må falle tilbake hit.
MazeRef.LEGACY_NAME = "MazeGame"

local function attributeName(player): string?
	if player == nil then
		return nil
	end
	local ok, value = pcall(function()
		return player:GetAttribute(MazeRef.ATTRIBUTE)
	end)
	if not ok or type(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

-- Mappa denne spilleren skal male, tegne kart over og lytte på. `nil` i lobbyen.
function MazeRef.folder(workspaceRoot, player)
	if workspaceRoot == nil then
		return nil
	end
	local name = attributeName(player)
	if name ~= nil then
		local own = workspaceRoot:FindFirstChild(name)
		if own ~= nil then
			return own
		end
		-- Attributtet kan henge igjen et øyeblikk etter at instansen er revet; fall videre ned
		-- til den delte mappa i stedet for å returnere noe som ikke finnes.
	end
	return workspaceRoot:FindFirstChild(MazeRef.LEGACY_NAME)
end

-- Er en mappe med dette navnet MIN? Brukes av ChildAdded, som ellers ville reagert på hver
-- eneste instans som bygges i serveren.
function MazeRef.matchesName(player, name): boolean
	if type(name) ~= "string" then
		return false
	end
	local mine = attributeName(player)
	if mine ~= nil then
		return name == mine
	end
	return name == MazeRef.LEGACY_NAME
end

-- Ligger denne delen inne i MIN labyrint? Brukes av DescendantAdded, som ellers ville malt
-- deler i naboens instans etter hvert som serveren bygger den.
function MazeRef.isMine(workspaceRoot, player, part): boolean
	local folder = MazeRef.folder(workspaceRoot, player)
	if folder == nil or part == nil then
		return false
	end
	local ok, inside = pcall(function()
		return part:IsDescendantOf(folder)
	end)
	return ok and inside == true
end

return MazeRef

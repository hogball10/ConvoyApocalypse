--!strict
--[[
	Convoy runs: host starts from garage, friends join with own vehicles.
	Endless scrolling road, biome cycling, zombies, scrap payout.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local PartsCatalog = require(Shared:WaitForChild("PartsCatalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local VehicleFactory = require(script.Parent:WaitForChild("VehicleFactory"))
local ArtKit = require(script.Parent:WaitForChild("ArtKit"))

export type Participant = {
	player: Player,
	vehicle: Model,
	kills: number,
	alive: boolean,
	overwhelmTimer: number,
	pickups: number,
	bossKills: number,
	-- Latest steering sent by the player's client, and when it arrived.
	throttle: number,
	steer: number,
	inputAt: number,
}

export type RunSession = {
	id: string,
	hostUserId: number,
	participants: { [number]: Participant },
	distance: number,
	biomeIndex: number,
	active: boolean,
	roadFolder: Folder,
	zombieFolder: Folder,
	nextZombie: number,
	pickupFolder: Folder,
	nextPickup: number,
	bossesSpawned: number,
	connection: RBXScriptConnection?,
	-- Step bookkeeping: replication throttle, last distance the road was
	-- rebuilt at, and the biome currently pushed to Lighting.
	accum: number,
	lastRoadDistance: number,
	appliedBiome: string?,
}

-- Rebuilding the road and re-pushing Lighting every Heartbeat is wasted work;
-- segments are 60 studs long so this is still far ahead of the player.
local ROAD_REFRESH_STUDS = 15

-- Zombies are cheap individually but each one runs its own chase loop, and the
-- spawn interval shrinks with distance while the batch size grows. Without a
-- ceiling a long run ends up with hundreds of them.
local MAX_ZOMBIES = 45

-- Steering. STEER_RATE is radians per second at handling 1, STEER_RECENTER how
-- fast the nose swings back to straight, MAX_HEADING how far it may point off
-- the road, and ROAD_HALF_WIDTH where the car's centre hits the guardrails.
local STEER_RATE = 0.9
local STEER_RECENTER = 1.4
local MAX_HEADING = 0.6
local ROAD_HALF_WIDTH = 13

-- Where each car was last frame, to charge fuel for the ground actually covered.
local lastPositions: { [Model]: Vector3 } = setmetatable({}, { __mode = "k" }) :: any

-- Fractional shots carried over between frames, per car.
local fireCharge: { [Model]: { [number]: number } } = setmetatable({}, { __mode = "k" }) :: any
local mountCache: { [Model]: { key: string, mounts: { any } } } = setmetatable({}, { __mode = "k" }) :: any
local MAX_SHOTS_PER_FRAME = 4

-- A client input older than this is ignored (the player released everything or
-- dropped), and the seat's own values are used instead.
local INPUT_TIMEOUT = 0.5

-- Seconds after a run ends before players are sent back to their garage.
local AUTO_RETURN_DELAY = 8

-- Seconds before the same zombie can be rammed again.
local RAM_COOLDOWN = 0.5

local ConvoyRunService = {}
ConvoyRunService._runs = {} :: { [string]: RunSession }
ConvoyRunService._playerRun = {} :: { [number]: string }
-- Set by GarageService: puts a player back in their garage after a run.
ConvoyRunService.ReturnHandler = nil :: ((Player, boolean?) -> ())?

local function notify(player: Player, message: string)
	Remotes.Event("Notification"):FireClient(player, message)
end

-- Step drives the car from the server, so the server has to own its physics.
-- Sitting welds the character on, and a character's assembly belongs to its
-- client: left alone, the client drags the car back to wherever the character
-- was standing and discards every velocity Step writes. Move the character to
-- the seat first, then take ownership back once the seat weld exists.
local function seatDriver(player: Player, vehicle: Model)
	task.defer(function()
		local character = player.Character or player.CharacterAdded:Wait()
		local hum = character:FindFirstChildOfClass("Humanoid")
		local seat = vehicle:FindFirstChild("DriveSeat") :: VehicleSeat?
		local body = vehicle.PrimaryPart
		if not hum or not seat or not body then
			return
		end
		character:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
		seat:Sit(hum)
		if seat.Occupant ~= hum then
			seat:GetPropertyChangedSignal("Occupant"):Wait()
		end
		if body.Parent then
			body:SetNetworkOwner(nil)
		end
	end)
end

local function getBiome(distance: number): (string, number)
	local index = (math.floor(distance / Constants.BIOME_LENGTH) % #Constants.BIOMES) + 1
	return Constants.BIOMES[index], index
end

local WorldTheme = require(script.Parent:WaitForChild("WorldTheme"))

local SURFACE = {
	asphalt = "rbxassetid://107150125861280",
	dirt = "rbxassetid://122110081091825",
	concrete = "rbxassetid://128182410041801",
}

local function paintTop(part: BasePart, image: string, studs: number)
	part.Color = Color3.fromRGB(150, 148, 145)
	local tex = Instance.new("Texture")
	tex.Name = "Surface"
	tex.Face = Enum.NormalId.Top
	tex.Texture = image
	tex.StudsPerTileU = studs
	tex.StudsPerTileV = studs
	tex.Parent = part
end

local function placeProp(name: string, cf: CFrame, parent: Instance, color: Color3?): Instance?
	local template = ArtKit.Template(name)
	if not template then
		return nil
	end
	local inst = ArtKit.Place(template, cf, true)
	if color then
		if inst:IsA("BasePart") and inst.Name ~= "LampHead" then
			inst.Color = color
		end
		for _, desc in inst:GetDescendants() do
			if desc:IsA("BasePart") and desc.Name ~= "LampHead" then
				desc.Color = color
			end
		end
	end
	inst.Parent = parent
	return inst
end

local function biomeColor(name: string): Color3
	if name == "WastelandHighways" then
		return Color3.fromRGB(110, 95, 70)
	elseif name == "RuinedCity" then
		return Color3.fromRGB(75, 78, 85)
	elseif name == "Desert" then
		return Color3.fromRGB(210, 175, 115)
	elseif name == "SnowyMountains" then
		return Color3.fromRGB(210, 220, 230)
	end
	return Color3.fromRGB(80, 80, 80)
end

local function ensureWorld(): Folder
	local world = Workspace:FindFirstChild("ConvoyWorld")
	if not world then
		world = Instance.new("Folder")
		world.Name = "ConvoyWorld"
		world.Parent = Workspace
	end
	return world :: Folder
end

local function buildRoadSegment(parent: Folder, z: number, biome: string)
	local seg = Instance.new("Model")
	seg.Name = "Road_" .. tostring(z)
	seg.Parent = parent

	local ground = biomeColor(biome)
	local asphalt = ground:Lerp(Color3.fromRGB(35, 35, 38), 0.55)

	local road = Instance.new("Part")
	road.Name = "Asphalt"
	road.Size = Vector3.new(36, 1, 60)
	road.Anchored = true
	road.Material = Enum.Material.Asphalt
	road.Color = asphalt
	road.CFrame = CFrame.new(0, 0, -z)
	road.Parent = seg
	paintTop(road, SURFACE.asphalt, 6)

	-- Lane dashes
	for i = -2, 2 do
		local dash = Instance.new("Part")
		dash.Name = "LaneDash"
		dash.Size = Vector3.new(0.6, 0.12, 6)
		dash.Anchored = true
		dash.CanCollide = false
		dash.Material = Enum.Material.SmoothPlastic
		dash.Color = Color3.fromRGB(196, 176, 110)
		dash.Transparency = 0
		dash.CFrame = CFrame.new(0, 0.56, -z + i * 12)
		dash.Parent = seg
	end

	-- Shoulders / terrain
	for _, x in { -24, 24 } do
		local shoulder = Instance.new("Part")
		shoulder.Name = "Shoulder"
		shoulder.Size = Vector3.new(12, 1.2, 60)
		shoulder.Anchored = true
		shoulder.Material = if biome == "SnowyMountains" then Enum.Material.Snow elseif biome == "Desert" then Enum.Material.Sand else Enum.Material.Ground
		shoulder.Color = ground
		shoulder.CFrame = CFrame.new(x, -0.1, -z)
		shoulder.Parent = seg
		paintTop(shoulder, SURFACE.dirt, 8)
	end

	local farMat = if biome == "SnowyMountains" then Enum.Material.Snow elseif biome == "Desert" then Enum.Material.Sand else Enum.Material.Ground
	local far = Instance.new("Part")
	far.Name = "FarGround"
	far.Size = Vector3.new(240, 2, 60)
	far.Anchored = true
	far.Material = farMat
	far.Color = ground
	far.CFrame = CFrame.new(0, -1.2, -z)
	far.Parent = seg
	paintTop(far, SURFACE.dirt, 10)

	for _, x in { -17, 17 } do
		for n = -2, 2 do
			placeProp("Guardrail", CFrame.new(x, 0.5, -z + n * 12), seg)
		end
	end
	placeProp("LampPost", CFrame.new(20, 0.5, -z + 8), seg)
	placeProp("LampHead", CFrame.new(20, 0.5, -z + 8), seg)

	-- Biome props. Names match Blender models in ServerStorage.ConvoyArt.
	local rng = Random.new(z + (#biome * 17))
	local roadside = {
		WastelandHighways = { "Wreck", "BusWreck", "Barricade", "DeadTree", "RoadSign", "Rubble" },
		RuinedCity = { "Ruin", "Rubble", "Billboard", "Jersey", "BusWreck" },
		Desert = { "Rock", "Cactus", "RoadSign", "DeadTree" },
		SnowyMountains = { "Pine", "Rock", "DeadTree", "Barricade" },
	}
	local choices = roadside[biome] or { "Wreck", "Bush" }
	for _ = 1, 4 do
		local side = if rng:NextNumber() > 0.5 then 1 else -1
		local px = side * rng:NextNumber(20, 38)
		local pz = -z + rng:NextNumber(-25, 25)
		local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		local groundCf = CFrame.new(px, 0.5, pz) * yaw
		local pick = choices[rng:NextInteger(1, #choices)]
		if not placeProp(pick, groundCf, seg) then
			placeProp("Rock", groundCf, seg)
		end
		if biome == "Desert" then
			placeProp("Cactus", CFrame.new(px + side * 4, 0.5, pz + 5), seg)
			placeProp("Bush", CFrame.new(px + side * 2, 0.5, pz - 3), seg, Color3.fromRGB(140, 120, 60))
		elseif biome == "SnowyMountains" then
			placeProp("Rock", CFrame.new(px + side * 4, 0.5, pz - 6), seg, Color3.fromRGB(200, 205, 210))
		elseif biome == "WastelandHighways" then
			placeProp("Bush", CFrame.new(px + side * 2.5, 0.5, pz + 5), seg)
		end
	end
	if biome == "WastelandHighways" or biome == "RuinedCity" then
		local lane = rng:NextNumber(-6, 6)
		placeProp("SpikeStrip", CFrame.new(lane, 0.55, -z + rng:NextNumber(-18, 18)), seg)
		local shoulder = if rng:NextNumber() > 0.5 then 15 else -15
		placeProp("Jersey", CFrame.new(shoulder, 0.5, -z + 8) * CFrame.Angles(0, math.rad(90), 0), seg)
	end
	if rng:NextNumber() < 0.7 then
		local side = if rng:NextNumber() > 0.5 then 42 else -42
		placeProp("Antenna", CFrame.new(side, 0.5, -z + 6), seg)
	end
end

local function refreshRoad(session: RunSession)
	local biome = select(1, getBiome(session.distance))
	if biome ~= session.appliedBiome then
		WorldTheme.SetBiome(biome)
		session.appliedBiome = biome
	end
	session.lastRoadDistance = session.distance
	local centerZ = session.distance
	for _, child in session.roadFolder:GetChildren() do
		local zAttr = tonumber(string.match(child.Name, "Road_(%-?%d+)"))
		if zAttr and math.abs(zAttr - centerZ) > 220 then
			child:Destroy()
		end
	end
	for i = -2, 6 do
		local z = math.floor((centerZ + i * 60) / 60) * 60
		local name = "Road_" .. tostring(z)
		if not session.roadFolder:FindFirstChild(name) then
			buildRoadSegment(session.roadFolder, z, biome)
		end
	end
end

local function spawnZombie(session: RunSession, isBoss: boolean?)
	local biomeName, _ = getBiome(session.distance)
	local scale = 1 + session.distance / 800
	local boss = isBoss == true
	local isRunner = not boss and session.distance > 300 and math.random() < 0.25
	local isBrute = boss or (session.distance > 700 and math.random() < 0.12)

	local zombie = Instance.new("Model")
	zombie.Name = if boss then "Juggernaut" elseif isBrute then "Brute" elseif isRunner then "Runner" else "Walker"

	local skin = if biomeName == "SnowyMountains"
		then Color3.fromRGB(170, 185, 175)
		elseif biomeName == "Desert" then Color3.fromRGB(150, 125, 85)
		else Color3.fromRGB(70, 100, 65)
	if isRunner then
		skin = skin:Lerp(Color3.fromRGB(160, 40, 40), 0.35)
	end
	if isBrute then
		skin = skin:Lerp(Color3.fromRGB(40, 40, 50), 0.4)
	end

	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = if isBrute then Vector3.new(2.6, 3.2, 1.6) else Vector3.new(1.8, 2.6, 1.1)
	body.Color = skin
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = false
	body.CanCollide = true
	body.Parent = zombie

	local lane = if boss then 0 else (math.random() - 0.5) * 28
	local ahead = session.distance + 80 + math.random(0, 40)
	body.CFrame = CFrame.new(lane, 2.2, -ahead)

	-- The kit zombie is a Model with one MeshPart per colour; only "Skin" takes
	-- the biome tint. An older single-mesh export is tinted whole.
	local zombieArt = ArtKit.Template("Zombie")
	if zombieArt then
		body.Transparency = 1
		local visual = ArtKit.Place(zombieArt, body.CFrame, false)
		visual.Name = "ZombieMesh"
		local scale = if boss then 2.4 elseif isBrute then 1.4 elseif isRunner then 0.88 else 1
		local pieces: { BasePart } = {}
		if visual:IsA("BasePart") then
			visual.Color = skin
			visual.Size *= scale
			table.insert(pieces, visual)
		elseif visual:IsA("Model") then
			visual.WorldPivot = body.CFrame
			visual:ScaleTo(scale)
			for _, desc in visual:GetDescendants() do
				if desc:IsA("BasePart") then
					if desc.Name == "Skin" then
						desc.Color = skin
					elseif desc.Name == "Eyes" and isRunner then
						desc.Color = Color3.fromRGB(255, 60, 40)
					end
					desc.CanQuery = false
					table.insert(pieces, desc)
				end
			end
		end
		for _, piece in pieces do
			local meshWeld = Instance.new("WeldConstraint")
			meshWeld.Part0 = body
			meshWeld.Part1 = piece
			meshWeld.Parent = body
		end
		visual.Parent = zombie
	end

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = if isBrute then Vector3.new(1.6, 1.6, 1.6) else Vector3.new(1.2, 1.2, 1.2)
	head.Color = skin:Lerp(Color3.fromRGB(40, 80, 40), 0.2)
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.Massless = true
	if zombie:FindFirstChild("ZombieMesh") then
		head.Transparency = 1
	end
	head.CFrame = body.CFrame * CFrame.new(0, body.Size.Y * 0.55, 0)
	head.Parent = zombie
	local headWeld = Instance.new("WeldConstraint")
	headWeld.Part0 = body
	headWeld.Part1 = head
	headWeld.Parent = body

	for _, x in { -0.25, 0.25 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.25, 0.25, 0.25)
		eye.Color = if isRunner then Color3.fromRGB(255, 60, 40) else Color3.fromRGB(180, 255, 80)
		eye.Material = Enum.Material.Neon
		eye.CanCollide = false
		eye.Massless = true
		eye.Transparency = head.Transparency
		eye.CFrame = head.CFrame * CFrame.new(x, 0.1, -0.5)
		eye.Parent = zombie
		local ew = Instance.new("WeldConstraint")
		ew.Part0 = head
		ew.Part1 = eye
		ew.Parent = head
	end

	local hum = Instance.new("Humanoid")
	hum.MaxHealth = Constants.ZOMBIE_BASE_HEALTH * scale * (if boss then 12 elseif isBrute then 2.5 else 1) * (if isRunner then 0.7 else 1)
	hum.Health = hum.MaxHealth
	hum.WalkSpeed = Constants.ZOMBIE_BASE_SPEED * (if isRunner then 1.8 else 1) * (if isBrute then 0.7 else 1) * math.min(scale, 2)
	hum.HipHeight = body.Size.Y * 0.5
	hum.Parent = zombie

	zombie.PrimaryPart = body

	zombie:SetAttribute("Damage", Constants.ZOMBIE_BASE_DAMAGE * scale * (if boss then 3 elseif isBrute then 2 else 1))
	zombie:SetAttribute("Boss", boss)
	zombie:SetAttribute("RunId", session.id)
	zombie.Parent = session.zombieFolder

	-- Simple chase toward nearest alive vehicle
	task.spawn(function()
		while zombie.Parent and hum.Health > 0 and session.active do
			local nearest: BasePart? = nil
			local nearestDist = math.huge
			for _, participant in session.participants do
				if participant.alive and participant.vehicle.PrimaryPart then
					local d = (participant.vehicle.PrimaryPart.Position - body.Position).Magnitude
					if d < nearestDist then
						nearestDist = d
						nearest = participant.vehicle.PrimaryPart
					end
				end
			end
			if nearest then
				hum:MoveTo(nearest.Position)
				-- Contact damage
				if nearestDist < 6 then
					for _, participant in session.participants do
						if participant.alive and participant.vehicle.PrimaryPart == nearest then
							ConvoyRunService.DamageVehicle(session, participant, zombie:GetAttribute("Damage") :: number)
						end
					end
				end
			end
			task.wait(0.35)
		end
	end)

	-- Ram detection via Touched on vehicles is handled in bindVehicle
	Debris:AddItem(zombie, if boss then 90 else 45)
end

-- Every kill goes through here so boss kills pay out and announce consistently.
local function creditKill(session: RunSession, participant: Participant, zombie: Model)
	participant.kills += 1
	participant.vehicle:SetAttribute("Kills", participant.kills)
	local siphon = (participant.vehicle:GetAttribute("FuelPerKill") :: number?) or 0
	if siphon > 0 then
		local maxFuel = participant.vehicle:GetAttribute("MaxFuel") :: number
		local fuel = participant.vehicle:GetAttribute("Fuel") :: number
		participant.vehicle:SetAttribute("Fuel", math.min(maxFuel, fuel + siphon))
	end
	if zombie:GetAttribute("Boss") == true then
		participant.bossKills += 1
		for _, p in session.participants do
			notify(p.player, participant.player.Name .. " took down a JUGGERNAUT!")
		end
	end
	zombie:Destroy()
end

local PICKUP_KINDS = {
	{ kind = "Fuel", color = Color3.fromRGB(240, 170, 45), weight = 4 },
	{ kind = "Scrap", color = Color3.fromRGB(255, 220, 90), weight = 5 },
	{ kind = "Repair", color = Color3.fromRGB(70, 220, 120), weight = 3 },
}
local PICKUP_RADIUS = 9
local PICKUP_INTERVAL = 6
local BOSS_EVERY = 1000

local function spawnPickup(session: RunSession)
	local total = 0
	for _, k in PICKUP_KINDS do
		total += k.weight
	end
	local roll = math.random() * total
	local chosen = PICKUP_KINDS[1]
	for _, k in PICKUP_KINDS do
		roll -= k.weight
		if roll <= 0 then
			chosen = k
			break
		end
	end

	local part = Instance.new("Part")
	part.Name = "Pickup_" .. chosen.kind
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(3, 3, 3)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = chosen.color
	part.Position = Vector3.new((math.random() - 0.5) * 24, 3.5, -(session.distance + 140 + math.random(0, 60)))
	part:SetAttribute("Kind", chosen.kind)
	local light = Instance.new("PointLight")
	light.Color = chosen.color
	light.Range = 16
	light.Brightness = 2
	light.Parent = part
	part.Parent = session.pickupFolder
	Debris:AddItem(part, 40)
end

local function collectPickup(participant: Participant, pickup: BasePart)
	local kind = pickup:GetAttribute("Kind")
	local vehicle = participant.vehicle
	if kind == "Fuel" then
		local maxFuel = vehicle:GetAttribute("MaxFuel") :: number
		vehicle:SetAttribute("Fuel", math.min(maxFuel, (vehicle:GetAttribute("Fuel") :: number) + maxFuel * Constants.FUEL_PICKUP_FRACTION))
		notify(participant.player, string.format("+%d%% fuel", math.round(Constants.FUEL_PICKUP_FRACTION * 100)))
	elseif kind == "Repair" then
		local maxHealth = vehicle:GetAttribute("MaxHealth") :: number
		vehicle:SetAttribute("Health", math.min(maxHealth, (vehicle:GetAttribute("Health") :: number) + maxHealth * 0.25))
		notify(participant.player, "+25% repairs")
	else
		DataService.AddScrap(participant.player, 25)
		notify(participant.player, "+25 scrap")
	end
	participant.pickups += 1
	pickup:Destroy()
end

-- ── Weapons ────────────────────────────────────────────────────────────────

local function tracer(from: Vector3, to: Vector3, color: Color3, width: number)
	local dist = (to - from).Magnitude
	if dist < 0.5 then
		return
	end
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Size = Vector3.new(width, width, dist)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -dist / 2)
	beam.Parent = Workspace
	Debris:AddItem(beam, 0.16)
end

-- A jagged bolt: a few short beams with sideways kinks, so it reads as
-- lightning rather than a straight laser.
local function bolt(from: Vector3, to: Vector3)
	local along = to - from
	local dist = along.Magnitude
	if dist < 1 then
		return
	end
	local dir = along / dist
	local side = dir:Cross(Vector3.yAxis)
	if side.Magnitude < 0.01 then
		side = Vector3.xAxis
	end
	side = side.Unit
	local up = side:Cross(dir)
	local segments = math.clamp(math.floor(dist / 4), 3, 9)
	local last = from
	for i = 1, segments do
		local point = from + along * (i / segments)
		if i < segments then
			point += side * (math.random() - 0.5) * 3 + up * (math.random() - 0.5) * 3
		end
		tracer(last, point, Color3.fromRGB(150, 215, 255), 0.45)
		tracer(last, point, Color3.fromRGB(255, 255, 255), 0.15)
		last = point
	end
	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Transparency = 1
	flash.Position = to
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 215, 255)
	light.Range = 14
	light.Brightness = 3
	light.Parent = flash
	flash.Parent = Workspace
	Debris:AddItem(flash, 0.15)
end

local function hit(session: RunSession, participant: Participant, zombie: Model, damage: number): boolean
	local hum = zombie:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end
	hum:TakeDamage(damage)
	if hum.Health <= 0 then
		creditKill(session, participant, zombie)
	end
	return true
end

-- Live zombies as (model, position-in-vehicle-space) so each weapon only has to
-- describe its own targeting shape.
-- The guns on a car, decoded once from the JSON the factory stored. A car with
-- no mount list but a gun stat (a hand-set test car) gets one centred gun.
local function mountsOf(vehicle: Model): { any }
	local raw = vehicle:GetAttribute("WeaponsJson")
	local damage = (vehicle:GetAttribute("GunDamage") :: number?) or 0
	local rate = (vehicle:GetAttribute("FireRate") :: number?) or 0
	-- Re-decode only when the stored weapons actually change.
	local key = tostring(raw) .. "|" .. tostring(damage) .. "|" .. tostring(rate) .. "|" .. tostring(vehicle:GetAttribute("WeaponKind"))
	local cached = mountCache[vehicle]
	if cached and cached.key == key then
		return cached.mounts
	end
	local mounts: { any } = {}
	if typeof(raw) == "string" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and typeof(decoded) == "table" then
			mounts = decoded
		end
	end
	if #mounts == 0 and damage > 0 and rate > 0 then
		mounts = {
			{
				kind = (vehicle:GetAttribute("WeaponKind") :: string?) or "minigun",
				damage = damage,
				fireRate = rate,
				x = 0,
				y = 2,
				z = 0,
			},
		}
	end
	mountCache[vehicle] = { key = key, mounts = mounts }
	return mounts
end

local function targets(session: RunSession, body: BasePart): { { model: Model, rel: Vector3, pos: Vector3 } }
	local list = {}
	for _, zombie in session.zombieFolder:GetChildren() do
		if zombie:IsA("Model") and zombie.PrimaryPart then
			local pos = zombie.PrimaryPart.Position
			table.insert(list, { model = zombie, rel = body.CFrame:PointToObjectSpace(pos), pos = pos })
		end
	end
	return list
end

-- Forward is -Z in vehicle space; nearer first.
local function inFront(list, minZ: number, maxZ: number, halfWidth: number)
	local out = {}
	for _, t in list do
		if t.model.Parent and t.rel.Z < -minZ and t.rel.Z > -maxZ and math.abs(t.rel.X) < halfWidth then
			table.insert(out, t)
		end
	end
	table.sort(out, function(a, b)
		return a.rel.Z > b.rel.Z
	end)
	return out
end

local function fireWeapon(
	session: RunSession,
	participant: Participant,
	body: BasePart,
	damage: number,
	kind: string,
	muzzle: Vector3,
	all: { { model: Model, rel: Vector3, pos: Vector3 } }
)
	if kind == "tesla" then
		-- Arcs to the nearest zombie, then chains to up to three neighbours.
		local first = inFront(all, 2, 55, 20)[1]
		if not first then
			return
		end
		local struck: { [Model]: boolean } = {}
		local current = first
		local from = muzzle
		local dmg = damage
		for _ = 1, 4 do
			struck[current.model] = true
			bolt(from, current.pos)
			hit(session, participant, current.model, dmg)
			from = current.pos
			dmg *= 0.75
			local nextTarget
			local nextDist = 18
			for _, t in all do
				if not struck[t.model] and t.model.Parent then
					local d = (t.pos - current.pos).Magnitude
					if d < nextDist then
						nextDist = d
						nextTarget = t
					end
				end
			end
			if not nextTarget then
				break
			end
			current = nextTarget
		end
	elseif kind == "flame" then
		-- Short cone, burns everything in it.
		for _, t in inFront(all, 1, 28, 9) do
			hit(session, participant, t.model, damage * 0.5)
		end
		local mid = body.CFrame:PointToWorldSpace(Vector3.new(0, 1.5, -14))
		tracer(muzzle, mid, Color3.fromRGB(255, 120, 30), 3)
	elseif kind == "rail" then
		-- Pierces: every zombie in a long narrow lane takes the full hit.
		local lane = inFront(all, 1, 140, 3.5)
		for _, t in lane do
			hit(session, participant, t.model, damage)
		end
		tracer(muzzle, body.CFrame:PointToWorldSpace(Vector3.new(0, 2.5, -140)), Color3.fromRGB(150, 255, 255), 0.6)
	elseif kind == "shotgun" then
		-- Wide cone, up to five zombies, only up close.
		local count = 0
		for _, t in inFront(all, 1, 38, 14) do
			tracer(muzzle, t.pos, Color3.fromRGB(255, 220, 120), 0.2)
			hit(session, participant, t.model, damage)
			count += 1
			if count >= 5 then
				break
			end
		end
	elseif kind == "rocket" then
		-- Lobs at the nearest far zombie and splashes everything around it.
		local aim = inFront(all, 8, 100, 24)[1]
		if not aim then
			return
		end
		tracer(muzzle, aim.pos, Color3.fromRGB(255, 200, 80), 0.5)
		local blast = Instance.new("Explosion")
		blast.Position = aim.pos
		blast.BlastRadius = 14
		blast.BlastPressure = 0
		blast.DestroyJointRadiusPercent = 0
		blast.ExplosionType = Enum.ExplosionType.NoCraters
		blast.Parent = Workspace
		for _, t in all do
			if t.model.Parent and (t.pos - aim.pos).Magnitude <= 14 then
				hit(session, participant, t.model, damage)
			end
		end
	elseif kind == "mine" then
		-- Lays a mine just behind the car; anything chasing it sets it off.
		local drop = body.CFrame:PointToWorldSpace(Vector3.new(0, 0, 7))
		local victims = {}
		for _, t in all do
			if t.model.Parent and (t.pos - drop).Magnitude <= 13 then
				table.insert(victims, t)
			end
		end
		if #victims == 0 then
			return
		end
		local blast = Instance.new("Explosion")
		blast.Position = drop
		blast.BlastRadius = 10
		blast.BlastPressure = 0
		blast.DestroyJointRadiusPercent = 0
		blast.ExplosionType = Enum.ExplosionType.NoCraters
		blast.Parent = Workspace
		for _, t in victims do
			hit(session, participant, t.model, damage)
		end
	elseif kind == "ram" then
		return
	else
		-- Minigun and anything unrecognised: rapid single-target fire.
		local aim = inFront(all, 2, 60, 12)[1]
		if aim then
			tracer(muzzle, aim.pos, Color3.fromRGB(255, 240, 160), 0.15)
			hit(session, participant, aim.model, damage)
		end
	end
end

function ConvoyRunService.DamageVehicle(session: RunSession, participant: Participant, rawDamage: number)
	local vehicle = participant.vehicle
	if not participant.alive then
		return
	end
	local reduction = vehicle:GetAttribute("DamageReduction") :: number or 0
	local damage = rawDamage * (1 - math.clamp(reduction, 0, 0.9))
	-- A shield soaks damage first and stops recharging for a few seconds.
	local shield = (vehicle:GetAttribute("Shield") :: number?) or 0
	if shield > 0 then
		vehicle:SetAttribute("LastHit", os.clock())
		local absorbed = math.min(shield, damage)
		vehicle:SetAttribute("Shield", shield - absorbed)
		damage -= absorbed
		if damage <= 0 then
			return
		end
	end
	local health = (vehicle:GetAttribute("Health") :: number) - damage
	vehicle:SetAttribute("Health", health)
	if health <= 0 then
		participant.alive = false
		vehicle:SetAttribute("Alive", false)
		notify(participant.player, "Your vehicle was destroyed!")
		ConvoyRunService.CheckEnd(session)
	end
end

function ConvoyRunService.BindVehicle(session: RunSession, participant: Participant)
	local vehicle = participant.vehicle
	local body = vehicle.PrimaryPart
	if not body then
		return
	end

	body.Touched:Connect(function(hit)
		if not session.active or not participant.alive then
			return
		end
		local model = hit:FindFirstAncestorOfClass("Model")
		if not model or model.Parent ~= session.zombieFolder then
			return
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return
		end

		local speed = body.AssemblyLinearVelocity.Magnitude
		if speed < 20 then
			return
		end

		-- Touched fires for every part of the zombie and keeps firing while they
		-- overlap, so without this one collision costs the car many self-hits.
		local now = os.clock()
		local lastRam = model:GetAttribute("LastRam") :: number?
		if lastRam and now - lastRam < RAM_COOLDOWN then
			return
		end
		model:SetAttribute("LastRam", now)

		local ram = vehicle:GetAttribute("RamDamage") :: number or Constants.RAM_DAMAGE
		hum:TakeDamage(ram * (speed / 40))
		ConvoyRunService.DamageVehicle(session, participant, Constants.RAM_SELF_DAMAGE)

		if hum.Health <= 0 then
			creditKill(session, participant, model)
		end
	end)
end

-- Shop boosts become vehicle stats for this run; they are used up in EndRun.
local function applyBoosts(player: Player, vehicle: Model)
	local fuelMult = DataService.BoostEffect(player, "fuelMult")
	if fuelMult ~= 1 then
		local maxFuel = (vehicle:GetAttribute("MaxFuel") :: number) * fuelMult
		vehicle:SetAttribute("MaxFuel", maxFuel)
		vehicle:SetAttribute("Fuel", maxFuel)
	end
	local healthMult = DataService.BoostEffect(player, "healthMult")
	if healthMult ~= 1 then
		local maxHealth = (vehicle:GetAttribute("MaxHealth") :: number) * healthMult
		vehicle:SetAttribute("MaxHealth", maxHealth)
		vehicle:SetAttribute("Health", maxHealth)
	end
	local pickupMult = DataService.BoostEffect(player, "pickupMult")
	vehicle:SetAttribute("PickupMult", ((vehicle:GetAttribute("PickupMult") :: number?) or 1) * pickupMult)
	local scrapMult = DataService.BoostEffect(player, "scrapMult")
	vehicle:SetAttribute("ScrapMult", ((vehicle:GetAttribute("ScrapMult") :: number?) or 1) * scrapMult)

	local active = DataService.ActiveBoostNames(player)
	if #active > 0 then
		notify(player, "Boosts active: " .. table.concat(active, ", "))
	end
end

function ConvoyRunService.Start(host: Player)
	if ConvoyRunService._playerRun[host.UserId] then
		notify(host, "Already in a run")
		return
	end

	local blocks = DataService.GetActiveBlocks(host)
	if not blocks then
		notify(host, "Data not ready")
		return
	end
	local missing = PartsCatalog.MissingFromBlocks(blocks)
	if #missing > 0 then
		notify(host, "Place these on the pad: " .. table.concat(missing, ", "))
		return
	end

	local preview = Workspace:FindFirstChild("WorldPreview")
	if preview then
		preview:Destroy()
	end

	local world = ensureWorld()
	local runId = "run_" .. tostring(host.UserId) .. "_" .. tostring(os.time())

	local roadFolder = Instance.new("Folder")
	roadFolder.Name = "Road_" .. runId
	roadFolder.Parent = world

	local zombieFolder = Instance.new("Folder")
	zombieFolder.Name = "Zombies_" .. runId
	zombieFolder.Parent = world

	local pickupFolder = Instance.new("Folder")
	pickupFolder.Name = "Pickups_" .. runId
	pickupFolder.Parent = world

	local vehiclesFolder = Instance.new("Folder")
	vehiclesFolder.Name = "Vehicles_" .. runId
	vehiclesFolder.Parent = world

	local spawnCF = CFrame.new(0, 0.6, 0)
	local vehicle = VehicleFactory.Create(host, blocks, spawnCF)
	applyBoosts(host, vehicle)
	vehicle.Parent = vehiclesFolder

	seatDriver(host, vehicle)

	local session: RunSession = {
		id = runId,
		hostUserId = host.UserId,
		participants = {},
		distance = 0,
		biomeIndex = 1,
		active = true,
		roadFolder = roadFolder,
		zombieFolder = zombieFolder,
		nextZombie = 0,
		pickupFolder = pickupFolder,
		nextPickup = 3,
		bossesSpawned = 0,
		connection = nil,
		accum = 0,
		-- Negative so the first Step always builds the road.
		lastRoadDistance = -math.huge,
		appliedBiome = nil,
	}

	local participant: Participant = {
		player = host,
		vehicle = vehicle,
		kills = 0,
		alive = true,
		overwhelmTimer = 0,
		pickups = 0,
		bossKills = 0,
		throttle = 0,
		steer = 0,
		inputAt = 0,
	}
	session.participants[host.UserId] = participant
	ConvoyRunService._runs[runId] = session
	ConvoyRunService._playerRun[host.UserId] = runId
	ConvoyRunService.BindVehicle(session, participant)

	refreshRoad(session)
	Remotes.Event("RunState"):FireClient(host, ConvoyRunService.Serialize(session))
	notify(host, "Run started! Survive as far as you can.")

	session.connection = RunService.Heartbeat:Connect(function(dt)
		ConvoyRunService.Step(session, dt)
	end)
end

function ConvoyRunService.Join(player: Player, hostUserId: number)
	local runId = ConvoyRunService._playerRun[hostUserId]
	local session = runId and ConvoyRunService._runs[runId]
	if not session or not session.active then
		notify(player, "No active run to join")
		return
	end
	if ConvoyRunService._playerRun[player.UserId] then
		notify(player, "Already in a run")
		return
	end

	local blocks = DataService.GetActiveBlocks(player)
	if not blocks then
		return
	end
	local missing = PartsCatalog.MissingFromBlocks(blocks)
	if #missing > 0 then
		notify(player, "Place these on the pad: " .. table.concat(missing, ", "))
		return
	end

	local offset = 0
	for _ in session.participants do
		offset += 8
	end

	local vehiclesFolder = session.roadFolder.Parent:FindFirstChild("Vehicles_" .. session.id) :: Folder
	local spawnCF = CFrame.new(offset, 0.6, -session.distance)
	local vehicle = VehicleFactory.Create(player, blocks, spawnCF)
	applyBoosts(player, vehicle)
	vehicle.Parent = vehiclesFolder

	seatDriver(player, vehicle)

	local participant: Participant = {
		player = player,
		vehicle = vehicle,
		kills = 0,
		alive = true,
		overwhelmTimer = 0,
		pickups = 0,
		bossKills = 0,
		throttle = 0,
		steer = 0,
		inputAt = 0,
	}
	session.participants[player.UserId] = participant
	ConvoyRunService._playerRun[player.UserId] = session.id
	ConvoyRunService.BindVehicle(session, participant)

	for _, p in session.participants do
		Remotes.Event("RunState"):FireClient(p.player, ConvoyRunService.Serialize(session))
	end
	notify(player, "Joined convoy!")
end

function ConvoyRunService.Step(session: RunSession, dt: number)
	if not session.active then
		return
	end

	local leadDistance = session.distance
	local anyAlive = false

	for _, participant in session.participants do
		local vehicle = participant.vehicle
		local body = vehicle.PrimaryPart
		if not body or not participant.alive then
			continue
		end
		anyAlive = true

		-- Drive motors from VehicleSeat throttle
		local seat = vehicle:FindFirstChild("DriveSeat") :: VehicleSeat?
		-- Prefer what the client sent; fall back to the seat if it has gone quiet.
		local throttle = if seat then seat.ThrottleFloat else 0
		local steer = if seat then seat.SteerFloat else 0
		if os.clock() - participant.inputAt < INPUT_TIMEOUT then
			throttle = participant.throttle
			steer = participant.steer
		end
		local speedStat = vehicle:GetAttribute("Speed") :: number
		local accel = vehicle:GetAttribute("Accel") :: number
		local boostMult = vehicle:GetAttribute("BoostMult") :: number
		local fuel = vehicle:GetAttribute("Fuel") :: number

		-- Direct velocity drive (reliable prototype feel). WASD via VehicleSeat.
		local handling = vehicle:GetAttribute("Handling") :: number
		local targetSpeed = 0
		if fuel > 0 then
			targetSpeed = throttle * speedStat
			-- Soft auto-cruise while seated so the loop is playable immediately
			if seat and seat.Occupant and math.abs(throttle) < 0.05 then
				targetSpeed = speedStat * 0.55
		end
		end

		local forward = body.CFrame.LookVector
		local right = body.CFrame.RightVector
		local vel = body.AssemblyLinearVelocity
		local desired = forward * targetSpeed + right * (steer * speedStat * 0.35)
		local blend = math.clamp(accel * 0.08 * dt * 60, 0.05, 1)
		local newVel = vel:Lerp(Vector3.new(desired.X, vel.Y, desired.Z), blend)
		body.AssemblyLinearVelocity = newVel

		-- The road runs straight down -Z, so the heading is kept within a cone
		-- around it: steering swings the nose a little, and letting go
		-- straightens the car back out. Left unbounded, a held key spun the car
		-- in circles and drove it off the road.
		local _, heading = body.CFrame:ToEulerAnglesYXZ()
		if math.abs(steer) > 0.05 and fuel > 0 then
			heading -= steer * handling * STEER_RATE * dt
		else
			heading -= math.sign(heading) * math.min(math.abs(heading), STEER_RECENTER * dt)
		end
		heading = math.clamp(heading, -MAX_HEADING, MAX_HEADING)

		-- Keep upright and on the tarmac
		local pos = body.Position
		local limit = ROAD_HALF_WIDTH
		if math.abs(pos.X) > limit then
			pos = Vector3.new(math.sign(pos.X) * limit, pos.Y, pos.Z)
			local v = body.AssemblyLinearVelocity
			if v.X * pos.X > 0 then
				body.AssemblyLinearVelocity = Vector3.new(0, v.Y, v.Z)
			end
		end
		body.CFrame = CFrame.new(pos) * CFrame.Angles(0, heading, 0)
		body.AssemblyAngularVelocity = Vector3.zero

		-- Fuel drain
		-- Fuel goes by distance driven, so tank capacity translates directly
		-- into range whatever the engine or the throttle.
		local here = Vector3.new(pos.X, 0, pos.Z)
		local before = lastPositions[vehicle]
		lastPositions[vehicle] = here
		local moved = if before then (here - before).Magnitude else 0
		local spent = moved * Constants.FUEL_PER_METER
		if moved < dt then
			-- Barely moving: idle burn only.
			spent += Constants.IDLE_FUEL_DRAIN * dt
		end
		fuel = math.max(0, fuel - spent)
		vehicle:SetAttribute("Fuel", fuel)

		-- Shield recharges once it has gone a few seconds without a hit
		local maxShield = (vehicle:GetAttribute("MaxShield") :: number?) or 0
		if maxShield > 0 and os.clock() - ((vehicle:GetAttribute("LastHit") :: number?) or 0) > 3 then
			local shield = vehicle:GetAttribute("Shield") :: number
			vehicle:SetAttribute("Shield", math.min(maxShield, shield + (vehicle:GetAttribute("ShieldRegen") :: number) * dt))
		end

		-- Repair utility
		local repair = vehicle:GetAttribute("RepairPerSec") :: number
		if repair > 0 then
			local health = vehicle:GetAttribute("Health") :: number
			local maxHealth = vehicle:GetAttribute("MaxHealth") :: number
			vehicle:SetAttribute("Health", math.min(maxHealth, health + repair * dt))
		end

		-- Distance from -Z travel
		local zDist = -body.Position.Z
		if zDist > leadDistance then
			leadDistance = zDist
		end

		-- Out of fuel overwhelm
		if fuel <= 0 then
			participant.overwhelmTimer += dt
			if participant.overwhelmTimer >= Constants.OVERWHELM_GRACE then
				participant.alive = false
				vehicle:SetAttribute("Alive", false)
				notify(participant.player, "Out of fuel — overwhelmed!")
			end
		else
			participant.overwhelmTimer = 0
		end

		-- Every mounted weapon fires on its own timer; each kind fires
		-- differently (see fireWeapon).
		if fuel > 0 then
			local mounts = mountsOf(vehicle)
			local live = nil
			local charges = fireCharge[vehicle]
			if not charges then
				charges = {}
				fireCharge[vehicle] = charges
			end
			for index, mount in mounts do
				-- Charge builds at fireRate per second and each whole point is a
				-- shot, so fast guns really fire fast whatever the frame rate.
				local charge = (charges[index] or 0) + mount.fireRate * dt
				local shots = math.min(math.floor(charge), MAX_SHOTS_PER_FRAME)
				charges[index] = if shots >= MAX_SHOTS_PER_FRAME then 0 else charge - shots
				if shots > 0 then
					live = live or targets(session, body)
					local muzzle = body.CFrame:PointToWorldSpace(Vector3.new(mount.x, mount.y + 0.5, mount.z - 1))
					for _ = 1, shots do
						fireWeapon(session, participant, body, mount.damage, mount.kind, muzzle, live)
					end
				end
			end
		end
	end

	session.distance = math.max(session.distance, leadDistance)
	local _, biomeIndex = getBiome(session.distance)
	session.biomeIndex = biomeIndex
	if session.distance - session.lastRoadDistance >= ROAD_REFRESH_STUDS then
		refreshRoad(session)
	end

	-- Spawn zombies
	session.nextZombie -= dt
	local density = Constants.ZOMBIE_SPAWN_INTERVAL / (1 + session.distance / 1000)
	if session.nextZombie <= 0 then
		session.nextZombie = density
		local count = 1 + math.floor(session.distance / 1500)
		local headroom = MAX_ZOMBIES - #session.zombieFolder:GetChildren()
		for _ = 1, math.min(count, headroom) do
			spawnZombie(session)
		end
	end

	-- Pickups: fuel / scrap / repair orbs ahead of the convoy
	session.nextPickup -= dt
	if session.nextPickup <= 0 then
		session.nextPickup = PICKUP_INTERVAL
		spawnPickup(session)
	end
	for _, pickup in session.pickupFolder:GetChildren() do
		if not pickup:IsA("BasePart") then
			continue
		end
		for _, participant in session.participants do
			local pBody = participant.vehicle.PrimaryPart
			local reach = PICKUP_RADIUS * ((participant.vehicle:GetAttribute("PickupMult") :: number?) or 1)
			if participant.alive and pBody and (pBody.Position - pickup.Position).Magnitude < reach then
				collectPickup(participant, pickup)
				break
			end
		end
	end

	-- Juggernaut boss every BOSS_EVERY studs
	local bossDue = math.floor(session.distance / BOSS_EVERY)
	if bossDue > session.bossesSpawned then
		session.bossesSpawned = bossDue
		spawnZombie(session, true)
		for _, participant in session.participants do
			notify(participant.player, "A JUGGERNAUT approaches! Ram it or shoot it down.")
		end
	end

	-- Replicate state ~10Hz worth via throttle
	session.accum += dt
	if session.accum >= 0.15 then
		session.accum = 0
		local payload = ConvoyRunService.Serialize(session)
		for _, participant in session.participants do
			Remotes.Event("RunState"):FireClient(participant.player, payload)
		end
	end

	if not anyAlive then
		ConvoyRunService.EndRun(session)
	end
end

function ConvoyRunService.CheckEnd(session: RunSession)
	for _, participant in session.participants do
		if participant.alive then
			return
		end
	end
	ConvoyRunService.EndRun(session)
end

function ConvoyRunService.Serialize(session: RunSession): any
	local biome = select(1, getBiome(session.distance))
	local vehicles = {}
	for userId, participant in session.participants do
		local v = participant.vehicle
		vehicles[tostring(userId)] = {
			health = v:GetAttribute("Health"),
			maxHealth = v:GetAttribute("MaxHealth"),
			fuel = v:GetAttribute("Fuel"),
			maxFuel = v:GetAttribute("MaxFuel"),
			shield = v:GetAttribute("Shield"),
			maxShield = v:GetAttribute("MaxShield"),
			kills = participant.kills,
			alive = participant.alive,
			name = participant.player.Name,
		}
	end
	return {
		runId = session.id,
		distance = session.distance,
		biome = biome,
		active = session.active,
		vehicles = vehicles,
		hostUserId = session.hostUserId,
	}
end

function ConvoyRunService.EndRun(session: RunSession)
	if not session.active then
		return
	end
	session.active = false
	if session.connection then
		session.connection:Disconnect()
		session.connection = nil
	end

	local distance = session.distance
	local distanceScrap = math.floor(distance / Constants.SCRAP_PER_METERS)

	for _, participant in session.participants do
		local killScrap = participant.kills * Constants.SCRAP_PER_KILL
		local bossScrap = participant.bossKills * Constants.BOSS_SCRAP
		local scrapMult = (participant.vehicle:GetAttribute("ScrapMult") :: number?) or 1
		local distanceScrap = math.floor(distanceScrap * scrapMult)
		killScrap = math.floor(killScrap * scrapMult)
		bossScrap = math.floor(bossScrap * scrapMult)
		local total = distanceScrap + killScrap + bossScrap
		local xp = math.floor(distance / Constants.XP_PER_METERS)
			+ participant.kills * Constants.XP_PER_KILL
			+ participant.bossKills * Constants.XP_PER_BOSS
		xp = math.floor(xp * DataService.BoostEffect(participant.player, "xpMult"))
		local boostNames = DataService.ActiveBoostNames(participant.player)
		local previous = DataService.Get(participant.player)
		local isRecord = previous ~= nil and distance > previous.highScore
		DataService.AddScrap(participant.player, total)
		DataService.UpdateHighScore(participant.player, distance)
		local level, levelsGained = DataService.AddRunProgress(participant.player, xp, participant.kills)
		DataService.ConsumeBoosts(participant.player)
		DataService.Save(participant.player)
		notify(
			participant.player,
			string.format("Run over! Distance %.0f m | +%d scrap | +%d xp", distance, total, xp)
		)
		if levelsGained > 0 then
			notify(participant.player, string.format("LEVEL UP! You are now level %d", level))
		end
		Remotes.Event("RunState"):FireClient(participant.player, {
			runId = session.id,
			distance = distance,
			biome = select(1, getBiome(distance)),
			active = false,
			ended = true,
			scrapEarned = total,
			distanceScrap = distanceScrap,
			killScrap = killScrap,
			bossScrap = bossScrap,
			kills = participant.kills,
			bossKills = participant.bossKills,
			pickups = participant.pickups,
			xpEarned = xp,
			boosts = boostNames,
			level = level,
			levelsGained = levelsGained,
			newRecord = isRecord,
			vehicles = {},
		})
		ConvoyRunService._playerRun[participant.player.UserId] = nil
	end

	-- Nobody should be left standing in the wasteland: return everyone to their
	-- garage a few seconds after the run ends (the end screen has a button for
	-- doing it sooner).
	local returning = {}
	for _, participant in session.participants do
		table.insert(returning, participant.player)
	end
	task.delay(AUTO_RETURN_DELAY, function()
		local handler = ConvoyRunService.ReturnHandler
		if not handler then
			return
		end
		for _, player in returning do
			if player.Parent and not ConvoyRunService._playerRun[player.UserId] then
				handler(player, true)
			end
		end
	end)

	-- Cleanup world pieces
	task.delay(3, function()
		if session.roadFolder.Parent then
			session.roadFolder:Destroy()
		end
		if session.zombieFolder.Parent then
			session.zombieFolder:Destroy()
		end
		if session.pickupFolder.Parent then
			session.pickupFolder:Destroy()
		end
		local world = Workspace:FindFirstChild("ConvoyWorld")
		if world then
			local vehicles = world:FindFirstChild("Vehicles_" .. session.id)
			if vehicles then
				vehicles:Destroy()
			end
		end
	end)

	ConvoyRunService._runs[session.id] = nil
end

function ConvoyRunService.Init()
	Remotes.Event("StartRun").OnServerEvent:Connect(function(player)
		ConvoyRunService.Start(player)
	end)
	Remotes.Event("JoinRun").OnServerEvent:Connect(function(player, hostUserId: number)
		if typeof(hostUserId) ~= "number" then
			return
		end
		ConvoyRunService.Join(player, hostUserId)
	end)
	Remotes.Event("VehicleInput").OnServerEvent:Connect(function(player, throttle, steer)
		if typeof(throttle) ~= "number" or typeof(steer) ~= "number" then
			return
		end
		local runId = ConvoyRunService._playerRun[player.UserId]
		local session = runId and ConvoyRunService._runs[runId]
		local participant = session and session.participants[player.UserId]
		if not participant then
			return
		end
		-- NaN and out-of-range values would otherwise steer the car arbitrarily.
		participant.throttle = if throttle ~= throttle then 0 else math.clamp(throttle, -1, 1)
		participant.steer = if steer ~= steer then 0 else math.clamp(steer, -1, 1)
		participant.inputAt = os.clock()
	end)

	Remotes.Event("LeaveRun").OnServerEvent:Connect(function(player)
		local runId = ConvoyRunService._playerRun[player.UserId]
		local session = runId and ConvoyRunService._runs[runId]
		if not session then
			return
		end
		local participant = session.participants[player.UserId]
		if participant then
			participant.alive = false
			participant.vehicle:SetAttribute("Alive", false)
		end
		ConvoyRunService.CheckEnd(session)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local runId = ConvoyRunService._playerRun[player.UserId]
		local session = runId and ConvoyRunService._runs[runId]
		if session then
			session.participants[player.UserId] = nil
			ConvoyRunService._playerRun[player.UserId] = nil
			if player.UserId == session.hostUserId or next(session.participants) == nil then
				ConvoyRunService.EndRun(session)
			else
				ConvoyRunService.CheckEnd(session)
			end
		end
	end)
end

function ConvoyRunService.IsInRun(player: Player): boolean
	return ConvoyRunService._playerRun[player.UserId] ~= nil
end

return ConvoyRunService

--!strict
--[[
	Convoy runs: host starts from garage, friends join with own vehicles.
	Endless scrolling road, biome cycling, zombies, scrap payout.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

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

-- Seconds before the same zombie can be rammed again.
local RAM_COOLDOWN = 0.5

local ConvoyRunService = {}
ConvoyRunService._runs = {} :: { [string]: RunSession }
ConvoyRunService._playerRun = {} :: { [number]: string }

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

local function spawnZombie(session: RunSession)
	local biomeName, _ = getBiome(session.distance)
	local scale = 1 + session.distance / 800
	local isRunner = session.distance > 300 and math.random() < 0.25
	local isBrute = session.distance > 700 and math.random() < 0.12

	local zombie = Instance.new("Model")
	zombie.Name = if isBrute then "Brute" elseif isRunner then "Runner" else "Walker"

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

	local lane = (math.random() - 0.5) * 28
	local ahead = session.distance + 80 + math.random(0, 40)
	body.CFrame = CFrame.new(lane, 2.2, -ahead)

	-- The kit zombie is a Model with one MeshPart per colour; only "Skin" takes
	-- the biome tint. An older single-mesh export is tinted whole.
	local zombieArt = ArtKit.Template("Zombie")
	if zombieArt then
		body.Transparency = 1
		local visual = ArtKit.Place(zombieArt, body.CFrame, false)
		visual.Name = "ZombieMesh"
		local scale = if isBrute then 1.4 elseif isRunner then 0.88 else 1
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
	hum.MaxHealth = Constants.ZOMBIE_BASE_HEALTH * scale * (if isBrute then 2.5 else 1) * (if isRunner then 0.7 else 1)
	hum.Health = hum.MaxHealth
	hum.WalkSpeed = Constants.ZOMBIE_BASE_SPEED * (if isRunner then 1.8 else 1) * (if isBrute then 0.7 else 1) * math.min(scale, 2)
	hum.HipHeight = body.Size.Y * 0.5
	hum.Parent = zombie

	zombie.PrimaryPart = body

	zombie:SetAttribute("Damage", Constants.ZOMBIE_BASE_DAMAGE * scale * (if isBrute then 2 else 1))
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
	Debris:AddItem(zombie, 45)
end

function ConvoyRunService.DamageVehicle(session: RunSession, participant: Participant, rawDamage: number)
	local vehicle = participant.vehicle
	if not participant.alive then
		return
	end
	local reduction = vehicle:GetAttribute("DamageReduction") :: number or 0
	local damage = rawDamage * (1 - math.clamp(reduction, 0, 0.9))
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
			participant.kills += 1
			vehicle:SetAttribute("Kills", participant.kills)
			model:Destroy()
		end
	end)
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

	local vehiclesFolder = Instance.new("Folder")
	vehiclesFolder.Name = "Vehicles_" .. runId
	vehiclesFolder.Parent = world

	local spawnCF = CFrame.new(0, 0.6, 0)
	local vehicle = VehicleFactory.Create(host, blocks, spawnCF)
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
	vehicle.Parent = vehiclesFolder

	seatDriver(player, vehicle)

	local participant: Participant = {
		player = player,
		vehicle = vehicle,
		kills = 0,
		alive = true,
		overwhelmTimer = 0,
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
		local throttle = if seat then seat.ThrottleFloat else 0
		local steer = if seat then seat.SteerFloat else 0
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

		if math.abs(steer) > 0.05 and fuel > 0 then
			local yaw = -steer * handling * 2.2 * dt
			body.CFrame = body.CFrame * CFrame.Angles(0, yaw, 0)
		end

		-- Keep upright
		local _, y = body.CFrame:ToEulerAnglesYXZ()
		body.CFrame = CFrame.new(body.Position) * CFrame.Angles(0, y, 0)
		body.AssemblyAngularVelocity = Vector3.new(0, body.AssemblyAngularVelocity.Y * 0.2, 0)

		-- Fuel drain
		local drain = Constants.IDLE_FUEL_DRAIN
		if math.abs(targetSpeed) > 1 then
			drain = Constants.FUEL_DRAIN_PER_SECOND
		end
		fuel = math.max(0, fuel - drain * dt)
		vehicle:SetAttribute("Fuel", fuel)

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

		-- Auto gun: damage nearby zombies in front
		local gunDamage = vehicle:GetAttribute("GunDamage") :: number
		local fireRate = vehicle:GetAttribute("FireRate") :: number
		if gunDamage > 0 and fireRate > 0 and fuel > 0 then
			-- Probabilistic fire each step scaled by fireRate
			if math.random() < fireRate * dt then
				for _, zombie in session.zombieFolder:GetChildren() do
					if zombie:IsA("Model") and zombie.PrimaryPart then
						local offset = body.CFrame:PointToObjectSpace(zombie.PrimaryPart.Position)
						if offset.Z < -2 and offset.Z > -60 and math.abs(offset.X) < 12 then
							local hum = zombie:FindFirstChildOfClass("Humanoid")
							if hum and hum.Health > 0 then
								hum:TakeDamage(gunDamage)
								if hum.Health <= 0 then
									participant.kills += 1
									vehicle:SetAttribute("Kills", participant.kills)
									zombie:Destroy()
								end
								break
							end
						end
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
		local total = distanceScrap + killScrap
		DataService.AddScrap(participant.player, total)
		DataService.UpdateHighScore(participant.player, distance)
		DataService.Save(participant.player)
		notify(
			participant.player,
			string.format(
				"Run over! Distance %.0f m | +%d scrap (dist %d + kills %d)",
				distance,
				total,
				distanceScrap,
				killScrap
			)
		)
		Remotes.Event("RunState"):FireClient(participant.player, {
			runId = session.id,
			distance = distance,
			biome = select(1, getBiome(distance)),
			active = false,
			ended = true,
			scrapEarned = total,
			vehicles = {},
		})
		ConvoyRunService._playerRun[participant.player.UserId] = nil
	end

	-- Cleanup world pieces
	task.delay(3, function()
		if session.roadFolder.Parent then
			session.roadFolder:Destroy()
		end
		if session.zombieFolder.Parent then
			session.zombieFolder:Destroy()
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

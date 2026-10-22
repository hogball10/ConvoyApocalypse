--!strict
--[[
	Personal garage sessions. Friends can join host garage to help view/equip.
	Host has final control for equip on host vehicle; guests manage their own loadouts.
	Trading only allowed when both in same garage.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local PartsCatalog = require(Shared:WaitForChild("PartsCatalog"))
local BlockBuilder = require(Shared:WaitForChild("BlockBuilder"))
local Constants = require(Shared:WaitForChild("Constants"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local VehicleFactory = require(script.Parent:WaitForChild("VehicleFactory"))
local ConvoyRunService = require(script.Parent:WaitForChild("ConvoyRunService"))
local ArtKit = require(script.Parent:WaitForChild("ArtKit"))

export type GarageSession = {
	hostUserId: number,
	occupants: { [number]: boolean },
	previewVehicle: Model?,
	folder: Folder,
}

local GarageService = {}
GarageService._garages = {} :: { [number]: GarageSession } -- keyed by host
GarageService._playerGarage = {} :: { [number]: number } -- player -> hostUserId
GarageService._targets = {} :: { [number]: { [string]: string } }
GarageService._pullCooldown = {} :: { [number]: number }
GarageService._spins = {} :: { [number]: { [string]: { token: number, busy: boolean, partId: string?, model: Model? } } }

local function notify(player: Player, msg: string)
	Remotes.Event("Notification"):FireClient(player, msg)
end

local function ensureGaragesFolder(): Folder
	local folder = Workspace:FindFirstChild("Garages")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Garages"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function anchored(name: string, size: Vector3, color: Color3, cf: CFrame, parent: Instance, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	p.Anchored = true
	p.CastShadow = true
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- Items on the spinning frame. Eight fit a lever without crowding the corners.
local REEL_SIZE = 8

-- Where each lever stands, as (x, z) from the garage origin.
local LEVER_SPOTS: { [string]: { number } } = {
	Body = { -22, -8 },
	Drive = { -22, 6 },
	Gear = { 22, -8 },
	Weapons = { 22, 6 },
}

-- A lever's listed price is for a Common; what it landed on costs more the
-- rarer it is.
local function leverCost(kind: string, tier: string?): number
	local base = Constants.LEVER_COSTS[kind] or 30
	return math.floor(base * (Constants.LEVER_TIER_MULT[tier or "Common"] or 1) + 0.5)
end

local setLeverSign: (Folder, string, string) -> ()

local function leverTitle(kind: string): string
	for _, entry in PartsCatalog.LeverKinds do
		if entry.kind == kind then
			return entry.title
		end
	end
	return kind
end

local function buildGaragePad(host: Player, index: number): Folder
	local root = ensureGaragesFolder()
	local folder = Instance.new("Folder")
	folder.Name = "Garage_" .. host.Name
	folder.Parent = root

	local origin = Vector3.new(index * 100, 0, 220)
	local accent = Color3.fromRGB(255, 140, 50)

	-- Main bay floor
	local floor = anchored("Floor", Vector3.new(56, 1.2, 48), Color3.fromRGB(210, 210, 210), CFrame.new(origin), folder, Enum.Material.Concrete)
	local floorTex = Instance.new("Texture")
	floorTex.Name = "Surface"
	floorTex.Face = Enum.NormalId.Top
	floorTex.Texture = "rbxassetid://128182410041801"
	floorTex.StudsPerTileU = 6
	floorTex.StudsPerTileV = 6
	floorTex.Parent = floor

	-- Hazard stripes around bay
	local stripe = anchored("Hazard", Vector3.new(54, 0.15, 2), Color3.fromRGB(255, 180, 40), CFrame.new(origin + Vector3.new(0, 0.7, -18)), folder, Enum.Material.Neon)
	stripe.Transparency = 0.15

	-- Back wall + side walls (open front)
	anchored("BackWall", Vector3.new(56, 16, 1.2), Color3.fromRGB(35, 35, 40), CFrame.new(origin + Vector3.new(0, 8, 24)), folder, Enum.Material.Metal)
	anchored("LeftWall", Vector3.new(1.2, 16, 48), Color3.fromRGB(38, 38, 44), CFrame.new(origin + Vector3.new(-28, 8, 0)), folder, Enum.Material.Metal)
	anchored("RightWall", Vector3.new(1.2, 16, 48), Color3.fromRGB(38, 38, 44), CFrame.new(origin + Vector3.new(28, 8, 0)), folder, Enum.Material.Metal)

	-- Roof with neon trim
	anchored("Roof", Vector3.new(58, 1, 50), Color3.fromRGB(28, 28, 32), CFrame.new(origin + Vector3.new(0, 16.5, 0)), folder, Enum.Material.Metal)
	local neonBeam = anchored("NeonBeam", Vector3.new(50, 0.4, 0.4), accent, CFrame.new(origin + Vector3.new(0, 15.8, -10)), folder, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Brightness = 2.2
	light.Range = 40
	light.Color = accent
	light.Parent = neonBeam

	-- Overhead work lights
	for _, x in { -12, 12 } do
		local lamp = anchored("Lamp", Vector3.new(3, 0.6, 3), Color3.fromRGB(255, 230, 180), CFrame.new(origin + Vector3.new(x, 15.5, -4)), folder, Enum.Material.Neon)
		local pl = Instance.new("PointLight")
		pl.Brightness = 1.6
		pl.Range = 28
		pl.Color = Color3.fromRGB(255, 220, 170)
		pl.Parent = lamp
	end

	-- Props modeled in Blender. Floor top is 0.6 above the bay origin.
	local function prop(name: string, offset: Vector3, yaw: number)
		local template = ArtKit.Template(name)
		if not template then
			return
		end
		local inst = ArtKit.Place(template, CFrame.new(origin + Vector3.new(offset.X, 0.6, offset.Z)) * CFrame.Angles(0, yaw, 0), true)
		inst.Parent = folder
	end
	if ArtKit.Template("Workbench") then
		prop("Workbench", Vector3.new(-18, 0, 14), math.rad(180))
		prop("Crate", Vector3.new(18, 0, 12), 0.4)
		prop("Crate", Vector3.new(23, 0, 14), 1.1)
		prop("Barrel", Vector3.new(16, 0, 16), 0.6)
		prop("Barrel", Vector3.new(14.2, 0, 16.4), 0.2)
		prop("TireStack", Vector3.new(22, 0, 15), 1.4)
		prop("LampPost", Vector3.new(-24, 0, -18), math.rad(90))
		prop("LampHead", Vector3.new(-24, 0, -18), math.rad(90))
		prop("ScrapPile", Vector3.new(-23, 0, 17), 0.5)
		prop("Hoist", Vector3.new(8, 0, 14), math.rad(200))
		prop("Barricade", Vector3.new(-8, 0, 16), 0.2)
		prop("RoadSign", Vector3.new(24, 0, -18), math.rad(-40))
	else
		anchored("Workbench", Vector3.new(8, 3, 3), Color3.fromRGB(70, 55, 40), CFrame.new(origin + Vector3.new(-18, 2, 14)), folder, Enum.Material.Wood)
		anchored("CrateA", Vector3.new(3, 3, 3), Color3.fromRGB(90, 70, 40), CFrame.new(origin + Vector3.new(18, 2, 12)), folder, Enum.Material.Wood)
		anchored("CrateB", Vector3.new(2.5, 2.5, 2.5), Color3.fromRGB(80, 60, 35), CFrame.new(origin + Vector3.new(21, 1.7, 8)), folder, Enum.Material.Wood)
		anchored("Barrel", Vector3.new(2, 3, 2), Color3.fromRGB(55, 80, 45), CFrame.new(origin + Vector3.new(16, 2, 16)), folder, Enum.Material.Metal)
	end

	-- Ramp out the front
	local ramp = anchored("Ramp", Vector3.new(14, 1, 12), Color3.fromRGB(50, 50, 55), CFrame.new(origin + Vector3.new(0, -0.2, -28)) * CFrame.Angles(math.rad(-12), 0, 0), folder, Enum.Material.DiamondPlate)

	-- Vehicle lift platform marking
	anchored("LiftPad", Vector3.new(10, 0.2, 14), Color3.fromRGB(55, 55, 60), CFrame.new(origin + Vector3.new(0, 0.75, -4)), folder, Enum.Material.DiamondPlate)

	local function buildLever(kind: string, xOffset: number, zOffset: number, title: string, cost: number, accentColor: Color3)
		local rootPos = origin + Vector3.new(xOffset, 0, zOffset)

		local pedestal = anchored("LeverBase_" .. kind, Vector3.new(3.4, 1.4, 3.4), Color3.fromRGB(36, 36, 42), CFrame.new(rootPos + Vector3.new(0, 1.3, -2)), folder, Enum.Material.DiamondPlate)
		pedestal:SetAttribute("LeverKind", kind)

		local pivotPos = rootPos + Vector3.new(0, 2.15, -2)
		local rest = CFrame.new(pivotPos) * CFrame.new(0, 1.2, 0)
		local arm = anchored("LeverArm_" .. kind, Vector3.new(0.38, 2.5, 0.38), accentColor, rest, folder, Enum.Material.Neon)
		arm.CanCollide = false
		arm:SetAttribute("RestCF", rest)
		arm:SetAttribute("PivotX", pivotPos.X)
		arm:SetAttribute("PivotY", pivotPos.Y)
		arm:SetAttribute("PivotZ", pivotPos.Z)
		local knob = anchored("LeverKnob_" .. kind, Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(230, 230, 235), rest * CFrame.new(0, 1.35, 0), folder, Enum.Material.SmoothPlastic)
		knob.Shape = Enum.PartType.Ball
		knob.CanCollide = false

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PullPrompt"
		prompt.ActionText = "Pull"
		prompt.ObjectText = title .. " (free)"
		prompt.HoldDuration = 0.35
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = arm

		local spinCenter = rootPos + Vector3.new(0, 9.2, 0.6)
		local spinHalf = 5
		arm:SetAttribute("SpinX", spinCenter.X)
		arm:SetAttribute("SpinY", spinCenter.Y)
		arm:SetAttribute("SpinZ", spinCenter.Z)
		arm:SetAttribute("SpinHalf", spinHalf)
		local corners = {
			spinCenter + Vector3.new(-spinHalf, 0, -spinHalf),
			spinCenter + Vector3.new(spinHalf, 0, -spinHalf),
			spinCenter + Vector3.new(spinHalf, 0, spinHalf),
			spinCenter + Vector3.new(-spinHalf, 0, spinHalf),
		}
		for edge = 1, 4 do
			local a = corners[edge]
			local b = corners[edge % 4 + 1]
			local beam = anchored(
				"SpinFrame_" .. kind .. tostring(edge),
				Vector3.new(0.16, 0.16, (b - a).Magnitude),
				accentColor,
				CFrame.lookAt((a + b) / 2, b),
				folder,
				Enum.Material.Neon
			)
			beam.CanCollide = false
			beam.Transparency = 0.35
		end
		local pad = anchored("SpinPad_" .. kind, Vector3.new(2.4, 0.18, 2.4), Color3.fromRGB(18, 18, 22), CFrame.new(spinCenter + Vector3.new(0, -1.1, spinHalf)), folder, Enum.Material.SmoothPlastic)
		pad.CanCollide = false
		prompt.Triggered:Connect(function(player)
			GarageService.PullLever(player, kind)
		end)

		local sign = anchored("LeverSign_" .. kind, Vector3.new(7.5, 3.4, 0.25), Color3.fromRGB(16, 16, 20), CFrame.new(rootPos + Vector3.new(0, 5.1, 0.2)), folder, Enum.Material.SmoothPlastic)
		sign.CanCollide = false
		local signGui = Instance.new("SurfaceGui")
		signGui.Face = Enum.NormalId.Back
		signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		signGui.PixelsPerStud = 40
		signGui.Parent = sign
		local status = Instance.new("TextLabel")
		status.Name = "StatusLabel"
		status.Size = UDim2.fromScale(1, 1)
		status.BackgroundTransparency = 1
		status.Text = GarageService.LeverIdleText(kind, title, cost)
		status.TextColor3 = accentColor
		status.Font = Enum.Font.GothamBold
		status.TextScaled = true
		status.Parent = signGui
	end

	-- The build plate takes up x -14..14 around the car, so the levers stand on
	-- the strips beside it, two to a wall, well clear of whatever is being built.
	for _, entry in PartsCatalog.LeverKinds do
		local spot = LEVER_SPOTS[entry.kind] or { 22, 0 }
		buildLever(entry.kind, spot[1], spot[2], entry.title, leverCost(entry.kind), entry.color)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "GarageSpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Anchored = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.CFrame = CFrame.new(origin + Vector3.new(-14, 2, 8))
	spawn.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 48)
	billboard.StudsOffset = Vector3.new(0, 12, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = floor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	label.BackgroundTransparency = 0.25
	label.Text = "  " .. host.Name .. "'S GARAGE"
	label.TextColor3 = accent
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 2
	stroke.Parent = label

	local buildX = origin.X
	local buildY = origin.Y + 1.8
	local buildZ = origin.Z - 4
	local plate = anchored("BuildPlate", Vector3.new(28, 1, 32), Color3.fromRGB(36, 120, 52), CFrame.new(buildX, buildY - 0.5, buildZ), folder, Enum.Material.SmoothPlastic)
	plate:SetAttribute("IsBuildPad", true)
	for ix = -13, 13, 2 do
		for iz = -15, 15, 2 do
			local stud = anchored("PadStud", Vector3.new(0.16, 0.4, 0.4), Color3.fromRGB(64, 160, 78), CFrame.new(buildX + ix, buildY + 0.08, buildZ + iz), plate, Enum.Material.SmoothPlastic)
			stud.Shape = Enum.PartType.Cylinder
			stud.CFrame = CFrame.new(buildX + ix, buildY + 0.08, buildZ + iz) * CFrame.Angles(0, 0, math.rad(90))
			stud.CanCollide = false
			stud.CanQuery = false
		end
	end

	anchored("BinShelf", Vector3.new(8, 0.4, 18), Color3.fromRGB(72, 56, 40), CFrame.new(origin + Vector3.new(20, 2.2, -4)), folder, Enum.Material.Wood)
	local bin = Instance.new("Folder")
	bin.Name = "Bin"
	bin.Parent = folder

	local info = anchored("InfoSign", Vector3.new(8, 4.5, 0.3), Color3.fromRGB(16, 16, 20), CFrame.new(origin + Vector3.new(-18, 4.2, -12)), folder, Enum.Material.SmoothPlastic)
	local infoGui = Instance.new("SurfaceGui")
	infoGui.Name = "InfoGui"
	infoGui.Face = Enum.NormalId.Back
	infoGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	infoGui.PixelsPerStud = 36
	infoGui.Parent = info
	local function line(name: string, y: number, text: string, color: Color3)
		local lbl = Instance.new("TextLabel")
		lbl.Name = name
		lbl.BackgroundTransparency = 1
		lbl.Position = UDim2.new(0, 6, y, 0)
		lbl.Size = UDim2.new(1, -12, 0.3, 0)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextColor3 = color
		lbl.Text = text
		lbl.Parent = infoGui
	end
	line("ScrapReadout", 0.02, "Scrap", Color3.fromRGB(255, 196, 80))
	line("HintReadout", 0.34, "Place an engine, wheels, fuel, and a seat", Color3.fromRGB(255, 186, 90))
	line("MessageReadout", 0.66, "Buy a part. Press I for inventory.", Color3.fromRGB(220, 220, 225))

	local startPad = anchored("StartPad", Vector3.new(6, 1, 6), Color3.fromRGB(255, 130, 40), CFrame.new(origin + Vector3.new(0, 1.2, -22)), folder, Enum.Material.Neon)
	local startGui = Instance.new("SurfaceGui")
	startGui.Face = Enum.NormalId.Top
	startGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	startGui.PixelsPerStud = 30
	startGui.Parent = startPad
	local startLabel = Instance.new("TextLabel")
	startLabel.Size = UDim2.fromScale(1, 1)
	startLabel.BackgroundTransparency = 1
	startLabel.Text = "START"
	startLabel.TextScaled = true
	startLabel.Font = Enum.Font.GothamBlack
	startLabel.TextColor3 = Color3.fromRGB(20, 16, 12)
	startLabel.Parent = startGui
	local startPrompt = Instance.new("ProximityPrompt")
	startPrompt.Name = "StartPrompt"
	startPrompt.ActionText = "Start Run"
	startPrompt.ObjectText = "Convoy"
	startPrompt.HoldDuration = 0.6
	startPrompt.RequiresLineOfSight = false
	startPrompt.MaxActivationDistance = 14
	startPrompt.Parent = startPad
	startPrompt.Triggered:Connect(function(who)
		if who.UserId ~= host.UserId then
			notify(who, "Only the garage owner starts the run")
			return
		end
		ConvoyRunService.Start(who)
	end)

	folder:SetAttribute("OwnerUserId", host.UserId)
	folder:SetAttribute("OriginX", origin.X)
	folder:SetAttribute("OriginZ", origin.Z)
	folder:SetAttribute("BuildX", buildX)
	folder:SetAttribute("BuildY", buildY)
	folder:SetAttribute("BuildZ", buildZ)
	return folder
end

local function refreshBin(folder: Folder, host: Player)
	local bin = folder:FindFirstChild("Bin")
	if not bin then
		return
	end
	bin:ClearAllChildren()
	local profile = DataService.Get(host)
	local blocks = DataService.GetActiveBlocks(host)
	if not profile or not blocks then
		return
	end
	local used: { [string]: number } = {}
	for _, block in blocks do
		used[block.partId] = (used[block.partId] or 0) + 1
	end
	local bx = folder:GetAttribute("OriginX") :: number
	local bz = folder:GetAttribute("OriginZ") :: number
	local index = 0
	for partId, count in profile.ownedParts do
		local part = PartsCatalog.Get(partId)
		local left = count - (used[partId] or 0)
		if part and left > 0 and part.category ~= "Chassis" then
			index += 1
			local col = (index - 1) % 3
			local row = math.floor((index - 1) / 3)
			local size = PartsCatalog.BlockSize(partId, 0)
			local cf = CFrame.new(bx + 18 + col * 2.3, 2.4 + size.Y / 2, bz - 11 + row * 2.6)
			local model = BlockBuilder.Create(partId, cf)
			model.Name = "BinItem"
			model:SetAttribute("BinPartId", partId)
			model:SetAttribute("BinCount", left)
			for _, desc in model:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.Anchored = true
					desc.CanCollide = false
					desc:SetAttribute("BinPartId", partId)
				end
			end
			local hostPart = model.PrimaryPart
			if hostPart then
				local bill = Instance.new("BillboardGui")
				bill.Size = UDim2.fromOffset(72, 22)
				bill.StudsOffset = Vector3.new(0, 1.5, 0)
				bill.AlwaysOnTop = true
				bill.Parent = hostPart
				local text = Instance.new("TextLabel")
				text.Size = UDim2.fromScale(1, 1)
				text.BackgroundTransparency = 0.25
				text.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
					text.Text = part.name .. "  x" .. tostring(left)
				text.TextColor3 = Color3.new(1, 1, 1)
				text.Font = Enum.Font.GothamBold
				text.TextScaled = true
				text.Parent = bill
			end
			model.Parent = bin
		end
	end
end

function GarageService.RefreshPreview(hostUserId: number)
	local garage = GarageService._garages[hostUserId]
	local host = Players:GetPlayerByUserId(hostUserId)
	if not garage or not host then
		return
	end
	if garage.previewVehicle then
		garage.previewVehicle:Destroy()
		garage.previewVehicle = nil
	end
	local blocks = DataService.GetActiveBlocks(host)
	if not blocks then
		return
	end
	local folder = garage.folder
	local vehicle = VehicleFactory.Create(host, blocks, CFrame.new(
		folder:GetAttribute("BuildX") :: number,
		folder:GetAttribute("BuildY") :: number,
		folder:GetAttribute("BuildZ") :: number
	))
	for _, desc in vehicle:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end
	local seat = vehicle:FindFirstChild("DriveSeat")
	if seat and seat:IsA("VehicleSeat") then
		seat.Disabled = true
	end
	vehicle.Name = "PreviewVehicle"
	vehicle.Parent = folder
	garage.previewVehicle = vehicle
	refreshBin(folder, host)
	local missing = PartsCatalog.MissingFromBlocks(blocks)
	local hint = folder:FindFirstChild("HintReadout", true)
	if hint and hint:IsA("TextLabel") then
		if #missing == 0 then
			hint.Text = "Ready. Hold the orange pad to start."
			hint.TextColor3 = Color3.fromRGB(130, 220, 130)
		else
			hint.Text = "Still need: " .. table.concat(missing, ", ")
			hint.TextColor3 = Color3.fromRGB(255, 186, 90)
		end
	end
end

function GarageService.OpenFor(player: Player)
	if GarageService._garages[player.UserId] then
		GarageService.TeleportToGarage(player, player.UserId)
		return
	end

	local index = 0
	for _ in GarageService._garages do
		index += 1
	end

	local folder = buildGaragePad(player, index)
	local session: GarageSession = {
		hostUserId = player.UserId,
		occupants = { [player.UserId] = true },
		previewVehicle = nil,
		folder = folder,
	}
	GarageService._garages[player.UserId] = session
	GarageService._playerGarage[player.UserId] = player.UserId
	GarageService.RefreshPreview(player.UserId)
	GarageService.TeleportToGarage(player, player.UserId)
	Remotes.Event("EnterGarage"):FireClient(player, {
		hostUserId = player.UserId,
		isHost = true,
	})
end

function GarageService.TeleportToGarage(player: Player, hostUserId: number)
	local garage = GarageService._garages[hostUserId]
	if not garage then
		return
	end
	local spawn = garage.folder:FindFirstChild("GarageSpawn")
	if spawn and spawn:IsA("SpawnLocation") then
		player.RespawnLocation = spawn
	end
	local lobby = Workspace:FindFirstChild("SpawnLocation")
	if lobby and lobby:IsA("SpawnLocation") and lobby ~= spawn then
		lobby.Enabled = false
	end
	local character = player.Character
	if spawn and spawn:IsA("BasePart") and character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(spawn.CFrame + Vector3.new(0, 3, 0))
	end
end

-- Brings a player back to the garage they belong to, from wherever they are:
-- respawning them first if they are dead or still seated in a wrecked car.
function GarageService.ReturnToGarage(player: Player, silent: boolean?)
	if ConvoyRunService.IsInRun(player) then
		if not silent then
			notify(player, "Finish the run first")
		end
		return
	end
	local hostId = GarageService._playerGarage[player.UserId]
	if not hostId or not GarageService._garages[hostId] then
		hostId = player.UserId
	end
	if not GarageService._garages[hostId] then
		GarageService.OpenFor(player)
		return
	end
	GarageService._playerGarage[player.UserId] = hostId
	GarageService._garages[hostId].occupants[player.UserId] = true
	-- Tells the client the run is behind it: closes the end screen, brings the garage UI back.
	Remotes.Event("EnterGarage"):FireClient(player, {
		hostUserId = hostId,
		isHost = hostId == player.UserId,
	})

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		-- RespawnLocation points at the garage spawn, so a fresh character lands there.
		GarageService.TeleportToGarage(player, hostId)
		player:LoadCharacter()
		return
	end
	humanoid.Sit = false
	GarageService.TeleportToGarage(player, hostId)
	if not silent then
		notify(player, "Back in the garage")
	end
end

function GarageService.Join(player: Player, hostUserId: number)
	if ConvoyRunService.IsInRun(player) then
		notify(player, "Leave your run first")
		return
	end
	local garage = GarageService._garages[hostUserId]
	local host = Players:GetPlayerByUserId(hostUserId)
	if not garage or not host then
		notify(player, "Garage not found")
		return
	end
	-- Friends check (allow in Studio / same server always for prototype flexibility)
	local isFriend = false
	local ok, result = pcall(function()
		return player:IsFriendsWithAsync(hostUserId)
	end)
	if ok then
		isFriend = result
	end
	if not isFriend and player.UserId ~= hostUserId then
		-- Still allow if both in same server for easier testing; soft warn
		notify(player, "Joining garage (friend check soft in prototype)")
	end

	-- Leave previous
	local prev = GarageService._playerGarage[player.UserId]
	if prev and GarageService._garages[prev] then
		GarageService._garages[prev].occupants[player.UserId] = nil
	end

	garage.occupants[player.UserId] = true
	GarageService._playerGarage[player.UserId] = hostUserId
	GarageService.TeleportToGarage(player, hostUserId)
	Remotes.Event("EnterGarage"):FireClient(player, {
		hostUserId = hostUserId,
		isHost = player.UserId == hostUserId,
	})
	notify(host, player.Name .. " joined your garage")
	notify(player, "Joined " .. host.Name .. "'s garage")
end

function GarageService.AreInSameGarage(a: Player, b: Player): boolean
	local ga = GarageService._playerGarage[a.UserId]
	local gb = GarageService._playerGarage[b.UserId]
	return ga ~= nil and ga == gb
end

function GarageService.GetOccupants(hostUserId: number): { number }
	local garage = GarageService._garages[hostUserId]
	if not garage then
		return {}
	end
	local list = {}
	for userId in garage.occupants do
		table.insert(list, userId)
	end
	return list
end

-- What a lever's sign says between pulls: its name, the category it is set to
-- roll, the price and the odds.
function GarageService.LeverIdleText(kind: string, title: string, cost: number, targetId: string?): string
	local target = PartsCatalog.FindTarget(kind, targetId or PartsCatalog.TargetsFor(kind)[1].id)
	local total = 0
	for _, entry in Constants.RARITY_ODDS do
		total += entry.weight
	end
	local odds = {}
	for _, entry in Constants.RARITY_ODDS do
		table.insert(odds, string.format("%s %.1f%%", entry.tier, entry.weight / total * 100))
	end
	return string.format("%s\nRolling: %s\nBuy from %d scrap\n%s", title, if target then target.label else "?", cost, table.concat(odds, "  "))
end

function GarageService.PlayerTargets(player: Player): { [string]: string }
	local bag = GarageService._targets[player.UserId]
	if not bag then
		bag = { Body = "brick", Drive = "engine", Gear = "armor", Weapons = "minigun" }
		GarageService._targets[player.UserId] = bag
	end
	return bag
end

function GarageService.SelectTarget(player: Player, kind: string, targetId: string)
	if not PartsCatalog.IsLeverKind(kind) then
		return
	end
	local target = PartsCatalog.FindTarget(kind, targetId)
	if not target then
		return
	end
	local bag = GarageService.PlayerTargets(player)
	bag[kind] = targetId
	Remotes.Event("LeverTarget"):FireClient(player, kind, targetId)
	local hostId = GarageService._playerGarage[player.UserId]
	local garage = hostId and GarageService._garages[hostId]
	local state = hostId and GarageService._spins[hostId] and GarageService._spins[hostId][kind]
	-- Don't overwrite the sign while a spin is running or an offer is waiting.
	if garage and not (state and (state.busy or state.partId)) then
		setLeverSign(garage.folder, kind, GarageService.LeverIdleText(kind, leverTitle(kind), leverCost(kind), targetId))
	end
	notify(player, "Lever set to " .. target.label)
end

function GarageService.AnimateLever(folder: Folder, kind: string)
	local arm = folder:FindFirstChild("LeverArm_" .. kind, true)
	local knob = folder:FindFirstChild("LeverKnob_" .. kind, true)
	if not arm or not arm:IsA("BasePart") then
		return
	end
	local rest = arm:GetAttribute("RestCF")
	if typeof(rest) ~= "CFrame" then
		rest = arm.CFrame
	end
	local px = arm:GetAttribute("PivotX")
	local py = arm:GetAttribute("PivotY")
	local pz = arm:GetAttribute("PivotZ")
	local pivot = if typeof(px) == "number" and typeof(py) == "number" and typeof(pz) == "number"
		then Vector3.new(px, py, pz)
		else arm.Position
	local pulled = CFrame.new(pivot) * CFrame.Angles(math.rad(-58), 0, 0) * CFrame.new(0, 1.2, 0)
	local infoOut = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local infoBack = TweenInfo.new(0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
	TweenService:Create(arm, infoOut, { CFrame = pulled }):Play()
	if knob and knob:IsA("BasePart") then
		TweenService:Create(knob, infoOut, { CFrame = pulled * CFrame.new(0, 1.35, 0) }):Play()
	end
	task.delay(0.18, function()
		if arm.Parent then
			TweenService:Create(arm, infoBack, { CFrame = rest :: CFrame }):Play()
		end
		if knob and knob.Parent and knob:IsA("BasePart") then
			TweenService:Create(knob, infoBack, { CFrame = (rest :: CFrame) * CFrame.new(0, 1.35, 0) }):Play()
		end
	end)

	local drop = Instance.new("Part")
	drop.Name = "LeverDrop"
	drop.Size = Vector3.new(1.1, 1.1, 1.1)
	drop.Material = Enum.Material.Neon
	drop.Anchored = true
	drop.CanCollide = false
	drop.Color = Color3.fromRGB(255, 190, 80)
	drop.CFrame = CFrame.new(pivot + Vector3.new(0, 2.2, 0))
	drop.Parent = folder
	TweenService:Create(drop, TweenInfo.new(0.8), {
		CFrame = drop.CFrame + Vector3.new(0, 2.5, 0),
		Transparency = 1,
	}):Play()
	Debris:AddItem(drop, 1)
end

local function spinBag(hostId: number, kind: string)
	local all = GarageService._spins[hostId]
	if not all then
		all = {}
		GarageService._spins[hostId] = all
	end
	local state = all[kind]
	if not state then
		state = { token = 0, busy = false, partId = nil, model = nil }
		all[kind] = state
	end
	return state
end

function setLeverSign(folder: Folder, kind: string, text: string)
	local sign = folder:FindFirstChild("LeverSign_" .. kind, true)
	local label = sign and sign:FindFirstChild("StatusLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function squarePoint(center: Vector3, half: number, t: number): Vector3
	local edge = half * 2
	local dist = (t % 1) * edge * 4
	local x, z
	if dist < edge then
		x = -half + dist
		z = -half
	elseif dist < edge * 2 then
		x = half
		z = -half + (dist - edge)
	elseif dist < edge * 3 then
		x = half - (dist - edge * 2)
		z = half
	else
		x = -half
		z = half - (dist - edge * 3)
	end
	return center + Vector3.new(x, 0, z)
end

local function spinCenterOf(folder: Folder, kind: string): (Vector3?, number)
	local arm = folder:FindFirstChild("LeverArm_" .. kind, true)
	if not arm then
		return nil, 6
	end
	local x = arm:GetAttribute("SpinX")
	local y = arm:GetAttribute("SpinY")
	local z = arm:GetAttribute("SpinZ")
	local half = arm:GetAttribute("SpinHalf")
	if typeof(x) ~= "number" or typeof(y) ~= "number" or typeof(z) ~= "number" then
		return nil, 6
	end
	return Vector3.new(x, y, z), if typeof(half) == "number" then half else 6
end

local function moveBlock(model: Model, cf: CFrame)
	local host = model.PrimaryPart
	if not host then
		return
	end
	local delta = cf * host.CFrame:Inverse()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = delta * part.CFrame
		end
	end
end

local function showBlock(partId: string, cf: CFrame, parent: Instance): Model
	local model = BlockBuilder.Create(partId, cf)
	model.Name = "SpinItem"
	model:SetAttribute("SpinDisplay", true)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	model.Parent = parent
	return model
end

function GarageService.BuyOffer(player: Player, kind: string)
	if ConvoyRunService.IsInRun(player) then
		notify(player, "Finish the run first")
		return
	end
	local hostId = GarageService._playerGarage[player.UserId]
	if not hostId then
		return
	end
	local state = spinBag(hostId, kind)
	if state.busy or not state.partId then
		notify(player, "Nothing to buy")
		return
	end
	local part = PartsCatalog.Get(state.partId)
	if not part then
		return
	end
	local cost = leverCost(kind, part.tier)
	if not DataService.TrySpendScrap(player, cost) then
		notify(player, "Need " .. tostring(cost) .. " scrap")
		return
	end
	local partId = state.partId
	local ok = DataService.GrantPart(player, partId)
	if not ok then
		DataService.AddScrap(player, cost)
		notify(player, "Purchase failed")
		return
	end
	state.token += 1
	state.partId = nil
	if state.model then
		state.model:Destroy()
		state.model = nil
	end
	local garage = GarageService._garages[hostId]
	if garage then
		setLeverSign(garage.folder, kind, part.name .. "\nBought\nPull for another spin")
	end
	Remotes.Event("LeverResult"):FireClient(player, {
		name = part.name,
		tier = part.tier,
		category = part.category,
		placed = false,
		kind = kind,
	})
	if GarageService._garages[player.UserId] then
		GarageService.RefreshPreview(player.UserId)
	end
	notify(player, part.name .. " added to inventory. Press I, then click the green pad")
end

function GarageService.PullLever(player: Player, kind: string)
	if ConvoyRunService.IsInRun(player) then
		notify(player, "Finish the run before you pull again")
		return
	end
	local hostId = GarageService._playerGarage[player.UserId]
	local garage = hostId and GarageService._garages[hostId]
	if not garage then
		notify(player, "Open the garage first")
		return
	end
	local state = spinBag(hostId, kind)
	if state.busy then
		notify(player, "Still spinning")
		return
	end
	local now = os.clock()
	local last = GarageService._pullCooldown[player.UserId] or 0
	if now - last < 0.4 then
		return
	end
	GarageService._pullCooldown[player.UserId] = now

	local bag = GarageService.PlayerTargets(player)
	local selected = PartsCatalog.FindTarget(kind, bag[kind] or "") or PartsCatalog.TargetsFor(kind)[1]
	if not selected then
		notify(player, "Nothing on this lever")
		return
	end
	local center, half = spinCenterOf(garage.folder, kind)
	if not center then
		notify(player, "The spin frame is missing")
		return
	end

	-- The reel only ever shows the selected category; the tiers on it are
	-- decoration except for the one that lands.
	local reelCount = REEL_SIZE
	local winnerIndex = math.random(1, reelCount)
	local tier = PartsCatalog.RollTier()
	local partId = PartsCatalog.PartIdFor(selected.prefix, tier)
	local part = PartsCatalog.Get(partId)
	if not part then
		notify(player, "That part is missing from the catalog")
		return
	end

	state.token += 1
	local token = state.token
	state.busy = true
	state.partId = nil
	if state.model then
		state.model:Destroy()
		state.model = nil
	end

	GarageService.AnimateLever(garage.folder, kind)
	setLeverSign(garage.folder, kind, "Spinning...\nPull is free")

	local folder = garage.folder
	local landingT = 0.625
	local base = (winnerIndex - 1) / reelCount
	local extra = (landingT - base) % 1
	local travelEnd = 2 + extra
	local duration = 2.8
	local models = {}
	for index = 1, reelCount do
		local shownId = if index == winnerIndex then partId else PartsCatalog.PartIdFor(selected.prefix, PartsCatalog.RollTier())
		local pos = squarePoint(center, half, (index - 1) / reelCount)
		table.insert(models, showBlock(shownId, CFrame.new(pos), folder))
	end

	task.spawn(function()
		local started = os.clock()
		while true do
			if state.token ~= token or not folder.Parent then
				for _, model in models do
					if model.Parent then
						model:Destroy()
					end
				end
				return
			end
			local alpha = math.clamp((os.clock() - started) / duration, 0, 1)
			local eased = 1 - (1 - alpha) * (1 - alpha)
			local travel = eased * travelEnd
			for index, model in models do
				if model.Parent then
					local pos = squarePoint(center, half, (index - 1) / reelCount + travel)
					moveBlock(model, CFrame.new(pos))
				end
			end
			if alpha >= 1 then
				break
			end
			task.wait(0.03)
		end
		if state.token ~= token or not folder.Parent then
			for _, model in models do
				if model.Parent then
					model:Destroy()
				end
			end
			return
		end
		for index, model in models do
			if index ~= winnerIndex and model.Parent then
				model:Destroy()
			end
		end
		local winner = models[winnerIndex]
		if not winner or not winner.Parent then
			state.busy = false
			return
		end
		local rest = squarePoint(center, half, landingT) + Vector3.new(0, 0.35, 0)
		moveBlock(winner, CFrame.new(rest))
		state.model = winner
		state.partId = partId
		state.busy = false

		local host = winner.PrimaryPart
		if host then
			host.CanQuery = true
			local cost = leverCost(kind, tier)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "BuyPrompt"
			prompt.ActionText = "Buy"
			prompt.ObjectText = part.name .. " (" .. tostring(cost) .. " scrap)"
			prompt.HoldDuration = 0.35
			prompt.MaxActivationDistance = 14
			prompt.RequiresLineOfSight = false
			prompt.Parent = host
			prompt.Triggered:Connect(function(buyer)
				GarageService.BuyOffer(buyer, kind)
			end)

			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromOffset(200, 52)
			billboard.StudsOffset = Vector3.new(0, 2.6, 0)
			billboard.AlwaysOnTop = true
			billboard.Parent = host
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
			label.BackgroundTransparency = 0.25
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = Constants.TIER_COLORS[tier] or Color3.new(1, 1, 1)
			label.Text = tier .. " " .. part.name .. "\n" .. tostring(cost) .. " scrap"
			label.Parent = billboard
		end
		setLeverSign(folder, kind, tier .. " " .. part.name .. "\n" .. tostring(leverCost(kind, tier)) .. " scrap to buy\nPull again to spin")
		notify(player, tier .. " " .. part.name .. " — buy it, or pull again")
	end)
end

function GarageService.Init()
	Remotes.Event("PlaceBlock").OnServerEvent:Connect(function(player, partId, x, y, z, rot)
		if typeof(partId) ~= "string" or typeof(x) ~= "number" or typeof(y) ~= "number" or typeof(z) ~= "number" or typeof(rot) ~= "number" then
			return
		end
		if ConvoyRunService.IsInRun(player) then
			notify(player, "Finish the run first")
			return
		end
		local ok, err = DataService.PlaceBlock(player, partId, x, y, z, rot)
		if not ok then
			notify(player, err or "Can't place that")
			return
		end
		if GarageService._garages[player.UserId] then
			GarageService.RefreshPreview(player.UserId)
		end
	end)

	Remotes.Event("RemoveBlock").OnServerEvent:Connect(function(player, index)
		if typeof(index) ~= "number" then
			return
		end
		if ConvoyRunService.IsInRun(player) then
			notify(player, "Finish the run first")
			return
		end
		local ok, err = DataService.RemoveBlock(player, index)
		if not ok then
			notify(player, err or "Can't pick that up")
			return
		end
		if GarageService._garages[player.UserId] then
			GarageService.RefreshPreview(player.UserId)
		end
	end)

	Remotes.Event("EquipPart").OnServerEvent:Connect(function(player, category: string, partId: string)
		if typeof(category) ~= "string" or typeof(partId) ~= "string" then
			return
		end
		if ConvoyRunService.IsInRun(player) then
			notify(player, "Cannot change parts during a run")
			return
		end
		local ok, err = DataService.EquipPart(player, category, partId)
		if not ok then
			notify(player, err or "Equip failed")
			return
		end
		-- Refresh host preview if this player is a garage host
		if GarageService._garages[player.UserId] then
			GarageService.RefreshPreview(player.UserId)
		end
	end)

	ConvoyRunService.ReturnHandler = GarageService.ReturnToGarage

	Remotes.Event("ReturnToGarage").OnServerEvent:Connect(function(player)
		GarageService.ReturnToGarage(player)
	end)

	Remotes.Event("BuyBoost").OnServerEvent:Connect(function(player, itemId)
		if typeof(itemId) ~= "string" then
			return
		end
		local ok, err = DataService.BuyBoost(player, itemId)
		local item = Constants.ShopItem(itemId)
		if ok and item then
			notify(player, "Bought " .. item.name)
		elseif err then
			notify(player, err)
		end
	end)

	Remotes.Event("SelectLeverTarget").OnServerEvent:Connect(function(player, kind, targetId)
		if typeof(kind) ~= "string" or typeof(targetId) ~= "string" then
			return
		end
		GarageService.SelectTarget(player, kind, targetId)
	end)

	Remotes.Event("UnlockPart").OnServerEvent:Connect(function(player, partId: string)
		if typeof(partId) ~= "string" then
			return
		end
		-- Parts that cost nothing to "unlock" are lever drops; letting the remote
		-- hand them out would skip the lever entirely.
		local def = PartsCatalog.Get(partId)
		if not def or def.unlockCost <= 0 then
			return
		end
		local ok, err = DataService.UnlockPart(player, partId)
		if not ok then
			notify(player, err or "Unlock failed")
		else
			local part = PartsCatalog.Get(partId)
			notify(player, "Unlocked " .. (part and part.name or partId))
		end
	end)

	Remotes.Event("SelectSlot").OnServerEvent:Connect(function(player, slotIndex: number)
		if typeof(slotIndex) ~= "number" then
			return
		end
		local ok, err = DataService.SelectSlot(player, slotIndex)
		if not ok then
			notify(player, err or "Slot failed")
			return
		end
		if GarageService._garages[player.UserId] then
			GarageService.RefreshPreview(player.UserId)
		end
	end)

	Remotes.Event("JoinGarage").OnServerEvent:Connect(function(player, hostUserId: number)
		if typeof(hostUserId) ~= "number" then
			return
		end
		GarageService.Join(player, hostUserId)
	end)

	Remotes.Function("GetGarageOccupants").OnServerInvoke = function(player)
		local hostId = GarageService._playerGarage[player.UserId]
		if not hostId then
			return {}
		end
		local occupants = {}
		for _, userId in GarageService.GetOccupants(hostId) do
			local p = Players:GetPlayerByUserId(userId)
			if p then
				table.insert(occupants, { userId = userId, name = p.Name })
			end
		end
		return occupants
	end

	local function watchRespawn(player: Player)
		player.CharacterAdded:Connect(function()
			local hostId = GarageService._playerGarage[player.UserId]
			if hostId and not ConvoyRunService.IsInRun(player) then
				task.defer(function()
					GarageService.TeleportToGarage(player, hostId)
				end)
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		watchRespawn(player)
		-- Wait for data then open personal garage
		task.spawn(function()
			for _ = 1, 50 do
				if DataService.Get(player) then
					break
				end
				task.wait(0.1)
			end
			GarageService.OpenFor(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local garage = GarageService._garages[player.UserId]
		if garage then
			for occupantId in garage.occupants do
				if occupantId ~= player.UserId then
					local occ = Players:GetPlayerByUserId(occupantId)
					if occ then
						GarageService._playerGarage[occupantId] = nil
						notify(occ, "Host left — returning to your garage")
						GarageService.OpenFor(occ)
					end
				end
			end
			if garage.folder then
				garage.folder:Destroy()
			end
			GarageService._garages[player.UserId] = nil
		end
		GarageService._playerGarage[player.UserId] = nil
		GarageService._targets[player.UserId] = nil
		GarageService._pullCooldown[player.UserId] = nil
		GarageService._spins[player.UserId] = nil
	end)

	for _, player in Players:GetPlayers() do
		watchRespawn(player)
		task.spawn(function()
			for _ = 1, 50 do
				if DataService.Get(player) then
					break
				end
				task.wait(0.1)
			end
			GarageService.OpenFor(player)
		end)
	end
end

return GarageService

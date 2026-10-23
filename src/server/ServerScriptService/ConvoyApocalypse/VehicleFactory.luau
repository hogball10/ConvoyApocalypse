--!strict
--[[
	Welds placed blocks into one driveable assembly.
	The root carries mass and does not collide. Blocks collide and stay massless.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local PartsCatalog = require(Shared:WaitForChild("PartsCatalog"))
local HttpService = game:GetService("HttpService")
local BlockBuilder = require(Shared:WaitForChild("BlockBuilder"))
local Constants = require(Shared:WaitForChild("Constants"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local VehicleFactory = {}

export type PlacedBlock = {
	partId: string,
	x: number,
	y: number,
	z: number,
	rot: number,
}

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function tag(inst: Instance, block: PlacedBlock, index: number)
	inst:SetAttribute("BlockIndex", index)
	inst:SetAttribute("PartId", block.partId)
	inst:SetAttribute("GridX", block.x)
	inst:SetAttribute("GridY", block.y)
	inst:SetAttribute("GridZ", block.z)
	inst:SetAttribute("Rot", block.rot)
end

-- The player's equipped paint, trail and flag, as catalogue entries.
local function equippedCosmetics(player: Player): { paint: Constants.Cosmetic?, trail: Constants.Cosmetic?, flag: Constants.Cosmetic? }
	local profile = DataService.Get(player)
	local result: any = {}
	if profile then
		result.paint = Constants.CosmeticById(profile.cosmetics.paint)
		result.trail = Constants.CosmeticById(profile.cosmetics.trail)
		result.flag = Constants.CosmeticById(profile.cosmetics.flag)
	end
	return result
end

local function addTrail(root: BasePart, item: Constants.Cosmetic)
	local top = Instance.new("Attachment")
	top.Name = "TrailTop"
	top.Position = Vector3.new(0, 1.6, 3)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "TrailBottom"
	bottom.Position = Vector3.new(0, 0.2, 3)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "CosmeticTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 1.1
	trail.LightEmission = 0.7
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	if item.rainbow then
		trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
			ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 190, 50)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(120, 235, 70)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 200, 255)),
			ColorSequenceKeypoint.new(0.8, Color3.fromRGB(150, 90, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 200)),
		})
	else
		trail.Color = ColorSequence.new(item.color)
	end
	trail.Parent = root
end

local function addFlag(model: Model, root: BasePart, origin: CFrame, blocks: { PlacedBlock }, item: Constants.Cosmetic)
	local topY, rearZ = 0, 0
	for _, block in blocks do
		local size = PartsCatalog.BlockSize(block.partId, block.rot)
		topY = math.max(topY, block.y + size.Y)
		rearZ = math.max(rearZ, block.z)
	end
	local base = origin * CFrame.new(0, topY, rearZ)
	local pole = Instance.new("Part")
	pole.Name = "FlagPole"
	pole.Size = Vector3.new(0.18, 3, 0.18)
	pole.Color = Color3.fromRGB(40, 40, 46)
	pole.Material = Enum.Material.Metal
	pole.CFrame = base * CFrame.new(0, 1.5, 0)
	local cloth = Instance.new("Part")
	cloth.Name = "FlagCloth"
	cloth.Size = Vector3.new(0.1, 1.1, 1.8)
	cloth.Color = item.color
	cloth.Material = Enum.Material.Fabric
	cloth.CFrame = base * CFrame.new(0, 2.4, 1.0)
	for _, piece in { pole, cloth } do
		piece.Massless = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = piece
		w.Parent = root
	end
end

function VehicleFactory.Create(player: Player, blocks: { PlacedBlock }, origin: CFrame): Model
	local stats = PartsCatalog.ComputeBlockStats(blocks)
	local cosmetics = equippedCosmetics(player)
	local model = Instance.new("Model")
	model.Name = "Vehicle_" .. player.Name

	local root = Instance.new("Part")
	root.Name = "Body"
	root.Size = Vector3.new(4, 1, 6)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.Anchored = false
	root.CFrame = origin
	root.CustomPhysicalProperties = PhysicalProperties.new(2, 0.45, 0.15, 1, 1)
	root.Parent = model
	model.PrimaryPart = root

	local seatPlaced = false
	for index, block in blocks do
		local turned = PartsCatalog.BlockSize(block.partId, block.rot)
		local cf = origin * CFrame.new(block.x, block.y + turned.Y / 2, block.z) * CFrame.Angles(0, math.rad(block.rot), 0)
		local piece = BlockBuilder.Create(block.partId, cf)
		piece.Name = "Block"
		tag(piece, block, index)
		-- Paint covers the plain building blocks; guns, engines and tanks keep their look.
		local blockPart = PartsCatalog.Get(block.partId)
		if cosmetics.paint and blockPart and blockPart.category == "Block" then
			if piece:IsA("BasePart") then
				piece.Color = cosmetics.paint.color
			end
			for _, desc in piece:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.Color = cosmetics.paint.color
				end
			end
		end
		for _, desc in piece:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Massless = true
				desc.Anchored = false
				tag(desc, block, index)
				weld(root, desc)
			end
		end
		piece.Parent = model

		if not seatPlaced and PartsCatalog.BlockKind(block.partId) == "seat" then
			local seat = Instance.new("VehicleSeat")
			seat.Name = "DriveSeat"
			seat.Size = Vector3.new(1.6, 0.4, 1.6)
			seat.Transparency = 1
			seat.CanCollide = false
			seat.CanQuery = false
			seat.Massless = true
			seat.CFrame = cf * CFrame.new(0, -0.5, 0)
			seat.HeadsUpDisplay = false
			seat.MaxSpeed = stats.speed
			seat.Torque = 20 + stats.accel
			seat.TurnSpeed = 2 + stats.handling
			seat.Parent = model
			tag(seat, block, index)
			weld(root, seat)
			seatPlaced = true
		end
	end

	if cosmetics.trail then
		addTrail(root, cosmetics.trail)
	end
	if cosmetics.flag then
		addFlag(model, root, origin, blocks, cosmetics.flag)
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "NameTag"
	bb.Size = UDim2.fromOffset(160, 36)
	bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.MaxDistance = 120
	bb.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.35
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	label.Text = player.Name
	label.TextColor3 = Color3.fromRGB(255, 160, 60)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("MaxHealth", stats.health)
	model:SetAttribute("Health", stats.health)
	model:SetAttribute("MaxFuel", stats.fuel)
	model:SetAttribute("Fuel", stats.fuel)
	model:SetAttribute("Speed", stats.speed)
	model:SetAttribute("Accel", stats.accel)
	model:SetAttribute("Handling", stats.handling)
	model:SetAttribute("Offroad", stats.offroad)
	model:SetAttribute("DamageReduction", stats.damageReduction)
	model:SetAttribute("RamDamage", stats.ramDamage)
	model:SetAttribute("GunDamage", stats.gunDamage)
	model:SetAttribute("FireRate", stats.fireRate)
	model:SetAttribute("RepairPerSec", stats.repairPerSec)
	model:SetAttribute("BoostMult", stats.boostMult)
	model:SetAttribute("PickupMult", stats.pickupMult)
	model:SetAttribute("ScrapMult", stats.scrapMult)
	model:SetAttribute("WeaponKind", stats.weaponKind)
	model:SetAttribute("WeaponsJson", HttpService:JSONEncode(stats.weapons))
	model:SetAttribute("MaxShield", stats.shieldMax)
	model:SetAttribute("Shield", stats.shieldMax)
	model:SetAttribute("ShieldRegen", stats.shieldRegen)
	model:SetAttribute("FuelPerKill", stats.fuelPerKill)
	model:SetAttribute("LastHit", 0)
	model:SetAttribute("Kills", 0)
	model:SetAttribute("Alive", true)

	return model
end

return VehicleFactory


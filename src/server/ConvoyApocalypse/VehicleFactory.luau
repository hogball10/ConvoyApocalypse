--!strict
--[[
	Welds placed blocks into one driveable assembly.
	The root carries mass and does not collide. Blocks collide and stay massless.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local PartsCatalog = require(Shared:WaitForChild("PartsCatalog"))
local BlockBuilder = require(Shared:WaitForChild("BlockBuilder"))

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

function VehicleFactory.Create(player: Player, blocks: { PlacedBlock }, origin: CFrame): Model
	local stats = PartsCatalog.ComputeBlockStats(blocks)
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
	model:SetAttribute("Kills", 0)
	model:SetAttribute("Alive", true)

	return model
end

return VehicleFactory


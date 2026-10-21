--!strict
--[[
	One building block. The car is whatever arrangement of these you place.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local PartsCatalog = require(Shared:WaitForChild("PartsCatalog"))
local Constants = require(Shared:WaitForChild("Constants"))

local BlockBuilder = {}

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
end

local function part(name: string, size: Vector3, color: Color3, cf: CFrame, parent: Instance, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = true
	p.CastShadow = true
	p.CFrame = cf
	p.Parent = parent
	return p
end

local SKIN_NAME = {
	wheel = "Wheel",
	engine = "EngineSkin",
	fuel = "FuelSkin",
	minigun = "MinigunSkin",
	tesla = "TeslaSkin",
	flame = "FlameSkin",
	rail = "RailSkin",
	ram = "RamSkin",
	seat = "SeatSkin",
}

local function attachSkin(kind: string, host: BasePart, model: Model, cf: CFrame, tierColor: Color3)
	local folder = ReplicatedStorage:FindFirstChild("ConvoyArtSkins")
	local skinName = SKIN_NAME[kind]
	if not folder or not skinName then
		return
	end
	local template = folder:FindFirstChild(skinName)
	if not template then
		return
	end
	local clone = template:Clone()
	local function prep(part: BasePart)
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.Massless = true
		part.CastShadow = true
		local cx = part:GetAttribute("CenterX") or 0
		local cy = part:GetAttribute("CenterY") or 0
		local cz = part:GetAttribute("CenterZ") or 0
		if kind == "wheel" then
			part.Size = part.Size * Vector3.new(1.15 / 0.76, 2 / 2.56, 2 / 2.56)
		end
		if part:GetAttribute("TierAccent") or part.Name == "WheelHub" then
			part.Color = tierColor
		end
		part.CFrame = cf * CFrame.new(cx, cy, cz)
		part.Parent = model
		weld(host, part)
	end
	if clone:IsA("BasePart") then
		prep(clone)
	else
		for _, desc in clone:GetDescendants() do
			if desc:IsA("BasePart") then
				prep(desc)
			end
		end
		clone:Destroy()
	end
	host.Transparency = 1
	host.CastShadow = false
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and desc ~= host then
			local skinned = string.find(desc.Name, "Skin", 1, true) ~= nil or desc.Name == "WheelTire" or desc.Name == "WheelHub"
			if not skinned then
				desc.Transparency = 1
				desc.CastShadow = false
				desc.CanCollide = false
				desc.CanQuery = false
			end
		end
	end
end

local function studs(host: BasePart, model: Model, color: Color3)
	local size = host.Size
	local nx = math.max(1, math.floor(size.X / 2 + 0.01))
	local nz = math.max(1, math.floor(size.Z / 2 + 0.01))
	for ix = 1, nx do
		for iz = 1, nz do
			local stud = part(
				"Stud",
				Vector3.new(0.22, 0.55, 0.55),
				color:Lerp(Color3.new(1, 1, 1), 0.2),
				host.CFrame
					* CFrame.new(-size.X / 2 + (ix - 0.5) * (size.X / nx), size.Y / 2 + 0.1, -size.Z / 2 + (iz - 0.5) * (size.Z / nz))
					* CFrame.Angles(0, 0, math.rad(90)),
				model,
				Enum.Material.SmoothPlastic
			)
			stud.Shape = Enum.PartType.Cylinder
			stud.CanCollide = false
			stud.CanQuery = false
			stud.Massless = true
			weld(host, stud)
		end
	end
end

function BlockBuilder.Create(partId: string, cf: CFrame): Model
	local info = PartsCatalog.Get(partId)
	local kind = PartsCatalog.BlockKind(partId)
	local size = PartsCatalog.BlockSize(partId, 0)
	local tier = if info then info.tier else "Common"
	local color = Constants.TIER_COLORS[tier] or Color3.fromRGB(180, 180, 190)
	local model = Instance.new("Model")
	model.Name = partId

	local function box(name: string, boxSize: Vector3, boxColor: Color3, offset: Vector3, material: Enum.Material?): Part
		return part(name, boxSize, boxColor, cf * CFrame.new(offset), model, material)
	end

	if kind == "wheel" then
		local tire = box("Wheel", Vector3.new(1.3, 2, 2), Color3.fromRGB(20, 20, 22), Vector3.zero, Enum.Material.SmoothPlastic)
		tire.Shape = Enum.PartType.Cylinder
		local hub = box("Hub", Vector3.new(1.45, 0.8, 0.8), color, Vector3.zero, Enum.Material.Metal)
		hub.Shape = Enum.PartType.Cylinder
		hub.CanCollide = false
		hub.Massless = true
		weld(tire, hub)
		model.PrimaryPart = tire
	elseif kind == "fuel" then
		local can = box("Fuel", Vector3.new(1.6, 1.6, 1.6), color, Vector3.zero, Enum.Material.SmoothPlastic)
		can.Shape = Enum.PartType.Cylinder
		local cap = box("Cap", Vector3.new(0.4, 0.5, 0.5), Color3.fromRGB(30, 30, 30), Vector3.new(0, 0.9, 0))
		cap.CanCollide = false
		cap.Massless = true
		weld(can, cap)
		model.PrimaryPart = can
	elseif kind == "wedge" then
		local slope = Instance.new("WedgePart")
		slope.Name = "Slope"
		slope.Size = size
		slope.Color = color
		slope.Material = Enum.Material.CorrodedMetal
		slope.CFrame = cf
		slope.Parent = model
		studs(slope, model, color)
		model.PrimaryPart = slope
	elseif kind == "minigun" then
		local body = box("Gun", Vector3.new(1.4, 1.2, 1.6), Color3.fromRGB(35, 35, 40), Vector3.zero, Enum.Material.Metal)
		for index = -1, 1 do
			local barrel = box("Barrel", Vector3.new(0.25, 0.25, 2.4), Color3.fromRGB(20, 20, 22), Vector3.new(index * 0.35, 0.2, -1.2), Enum.Material.Metal)
			barrel.CanCollide = false
			barrel.Massless = true
			weld(body, barrel)
		end
		model.PrimaryPart = body
	elseif kind == "tesla" then
		local base = box("CoilBase", Vector3.new(2, 1, 2), Color3.fromRGB(40, 50, 70), Vector3.new(0, -0.5, 0), Enum.Material.Metal)
		local ball = box("Coil", Vector3.new(1.4, 1.4, 1.4), color, Vector3.new(0, 0.8, 0), Enum.Material.Neon)
		ball.Shape = Enum.PartType.Ball
		ball.CanCollide = false
		ball.Massless = true
		weld(base, ball)
		model.PrimaryPart = base
	elseif kind == "flame" then
		local body = box("Flame", Vector3.new(1.2, 1.2, size.Z), Color3.fromRGB(160, 60, 30), Vector3.zero, Enum.Material.Metal)
		local nozzle = box("Nozzle", Vector3.new(0.5, 0.5, 1), Color3.fromRGB(255, 120, 40), Vector3.new(0, 0, -size.Z / 2), Enum.Material.Neon)
		nozzle.CanCollide = false
		nozzle.Massless = true
		weld(body, nozzle)
		model.PrimaryPart = body
	elseif kind == "rail" then
		local body = box("Rail", Vector3.new(0.6, 0.6, size.Z), color, Vector3.zero, Enum.Material.Neon)
		model.PrimaryPart = body
	elseif kind == "ram" then
		local blade = Instance.new("WedgePart")
		blade.Name = "Ram"
		blade.Size = size
		blade.Color = Color3.fromRGB(90, 90, 98)
		blade.Material = Enum.Material.Metal
		blade.CFrame = cf
		blade.Parent = model
		model.PrimaryPart = blade
	elseif kind == "engine" then
		local body = box("Engine", size, Color3.fromRGB(45, 48, 55), Vector3.zero, Enum.Material.Metal)
		local head = box("Head", Vector3.new(size.X * 0.7, 0.6, size.Z * 0.55), color, Vector3.new(0, size.Y / 2 + 0.2, 0), Enum.Material.Metal)
		head.CanCollide = false
		head.Massless = true
		weld(body, head)
		studs(body, model, color)
		model.PrimaryPart = body
	elseif kind == "seat" then
		local cushion = box("Seat", Vector3.new(2, 0.5, 2), color:Lerp(Color3.fromRGB(30, 20, 15), 0.45), Vector3.new(0, -0.6, 0), Enum.Material.Fabric)
		local back = box("Back", Vector3.new(2, 1.4, 0.35), color:Lerp(Color3.fromRGB(30, 20, 15), 0.45), Vector3.new(0, 0.2, 0.7), Enum.Material.Fabric)
		back.CanCollide = false
		back.Massless = true
		weld(cushion, back)
		model.PrimaryPart = cushion
	else
		local body = box("Brick", size, color, Vector3.zero, Enum.Material.CorrodedMetal)
		studs(body, model, color)
		model.PrimaryPart = body
	end

	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Massless = true
			desc:SetAttribute("PartId", partId)
		end
	end
	model:SetAttribute("PartId", partId)
	if model.PrimaryPart then
		attachSkin(kind, model.PrimaryPart, model, cf, color)
	end
	return model
end

return BlockBuilder

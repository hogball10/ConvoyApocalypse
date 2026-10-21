--!strict
--[[
	Builds the Blender kit into real geometry.

	ReplicatedStorage.ConvoyShared.ArtData holds one generated module per art
	item (see tools/build_art_modules.py). Each part carries its vertices
	rebased onto its own bounding-box centre, so turning it into a MeshPart and
	stamping that centre back on as CenterX/Y/Z is all ArtKit.Place needs to put
	the piece where it was modelled.

	Results land in:
	  ServerStorage.ConvoyArt        world props, read by ArtKit
	  ReplicatedStorage.ConvoyArtSkins  vehicle skins, read by BlockBuilder

	Build is idempotent: if a populated folder is already in the place (saved
	there by a previous session) nothing is rebuilt.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ArtImporter = {}

local WORLD_FOLDER = "ConvoyArt"
local SKIN_FOLDER = "ConvoyArtSkins"

type PartData = {
	name: string,
	material: string,
	color: { number },
	accent: boolean,
	center: { number },
	vertexCount: number,
	triangleCount: number,
	verts: string,
	tris: string,
}

type ItemData = {
	name: string,
	folder: string,
	parts: { PartData },
}

local function numbers(encoded: string): { number }
	local out = {}
	for token in string.gmatch(encoded, "%S+") do
		out[#out + 1] = tonumber(token)
	end
	return out
end

local function materialOf(name: string): Enum.Material
	local ok, material = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	if ok and typeof(material) == "EnumItem" then
		return material
	end
	return Enum.Material.SmoothPlastic
end

-- One MeshPart from one generated part record.
local function buildPart(data: PartData): MeshPart?
	local verts = numbers(data.verts)
	local tris = numbers(data.tris)
	if #verts < 9 or #tris < 3 then
		warn("[ArtImporter] skipping degenerate part", data.name)
		return nil
	end

	local editable = AssetService:CreateEditableMesh()
	local ids = table.create(#verts // 3)
	for i = 1, #verts - 2, 3 do
		ids[#ids + 1] = editable:AddVertex(Vector3.new(verts[i], verts[i + 1], verts[i + 2]))
	end

	for i = 1, #tris - 2, 3 do
		local a, b, c = ids[tris[i]], ids[tris[i + 1]], ids[tris[i + 2]]
		if a and b and c then
			editable:AddTriangle(a, b, c)
		end
	end

	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(editable), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
		})
	end)
	editable:Destroy()

	if not ok then
		warn("[ArtImporter] CreateMeshPartAsync failed for", data.name, result)
		return nil
	end

	local meshPart = result :: MeshPart
	meshPart.Name = data.name
	meshPart.Material = materialOf(data.material)
	meshPart.Color = Color3.fromRGB(data.color[1], data.color[2], data.color[3])
	meshPart.Anchored = true
	meshPart.CanCollide = false
	meshPart.CanQuery = false
	meshPart.CastShadow = true
	meshPart:SetAttribute("CenterX", data.center[1])
	meshPart:SetAttribute("CenterY", data.center[2])
	meshPart:SetAttribute("CenterZ", data.center[3])
	if data.accent then
		meshPart:SetAttribute("TierAccent", true)
	end
	return meshPart
end

-- A whole art item: a bare MeshPart when it has one part, a Model otherwise.
local function buildItem(item: ItemData): Instance?
	if #item.parts == 1 then
		local only = buildPart(item.parts[1])
		if only then
			only.Name = item.name
		end
		return only
	end

	local model = Instance.new("Model")
	model.Name = item.name
	local built = 0
	for _, partData in item.parts do
		local meshPart = buildPart(partData)
		if meshPart then
			meshPart.Parent = model
			built += 1
		end
	end
	if built == 0 then
		model:Destroy()
		return nil
	end
	return model
end

local function folderNamed(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

--[[
	BlockBuilder asks the skin folder for "Wheel", but the kit exports the tyre
	and hub as two separate world meshes. Assemble the pair into one skin Model
	so the wheel block gets the Blender geometry instead of its fallback
	cylinder.
]]
local function assembleWheelSkin(world: Folder, skins: Folder)
	if skins:FindFirstChild("Wheel") then
		return
	end
	local tire = world:FindFirstChild("WheelTire")
	local hub = world:FindFirstChild("WheelHub")
	if not tire or not hub then
		return
	end
	local wheel = Instance.new("Model")
	wheel.Name = "Wheel"
	tire:Clone().Parent = wheel
	hub:Clone().Parent = wheel
	wheel.Parent = skins
end

function ArtImporter.Build(): boolean
	local world = folderNamed(WORLD_FOLDER, ServerStorage)
	local skins = folderNamed(SKIN_FOLDER, ReplicatedStorage)

	if #world:GetChildren() > 0 and #skins:GetChildren() > 0 then
		print("[ArtImporter] art already present, skipping rebuild")
		return true
	end

	local dataFolder = ReplicatedStorage:WaitForChild("ConvoyShared"):FindFirstChild("ArtData")
	if not dataFolder then
		warn("[ArtImporter] ConvoyShared.ArtData is missing -- world will fall back to blocks")
		return false
	end

	local started = os.clock()
	local built, failed = 0, 0

	for _, module in dataFolder:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, item = pcall(require, module)
			if not ok then
				warn("[ArtImporter] could not load", module.Name, item)
				failed += 1
				continue
			end
			local instance = buildItem(item :: ItemData)
			if instance then
				instance.Parent = if (item :: ItemData).folder == "skin" then skins else world
				built += 1
			else
				failed += 1
			end
		end
	end

	assembleWheelSkin(world, skins)

	print(string.format(
		"[ArtImporter] built %d art items (%d failed) in %.2fs -- %d world, %d skins",
		built, failed, os.clock() - started, #world:GetChildren(), #skins:GetChildren()
	))
	return built > 0
end

return ArtImporter

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

	Parts load from their uploaded mesh asset (meshId). A part without one is
	built from an EditableMesh instead, which only the server can see.

	Build is idempotent: each built item records a signature of its module and
	is kept while that still matches and all its parts are asset-backed.
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
	hash: string,
	meshId: string?,
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

-- Fallback for a part that has not been uploaded yet. Only the server can see
-- an EditableMesh: clients get a checkered placeholder box in its place.
local function buildEditablePart(data: PartData): MeshPart?
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

	-- The MeshPart keeps pointing at this EditableMesh, so it must stay alive:
	-- destroying it leaves the part with nothing to render.
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromObject(editable), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
		})
	end)

	if not ok then
		editable:Destroy()
		warn("[ArtImporter] CreateMeshPartAsync failed for", data.name, result)
		return nil
	end
	return result
end

local missingUploads = 0

-- One MeshPart from one generated part record.
local function buildPart(data: PartData): MeshPart?
	local result: MeshPart? = nil
	if data.meshId then
		local ok, loaded = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromUri(data.meshId :: string), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
			})
		end)
		if ok then
			result = loaded
		else
			warn("[ArtImporter] could not load mesh", data.meshId, "for", data.name, loaded)
		end
	end
	if not result then
		missingUploads += 1
		result = buildEditablePart(data)
	end
	if not result then
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

-- Fingerprint of a module: its geometry hashes, plus whether each part has
-- been uploaded, so adding a meshId swaps the placeholder build out.
local function signature(item: ItemData): string
	local pieces = table.create(#item.parts)
	for _, part in item.parts do
		table.insert(pieces, part.hash .. "=" .. (part.meshId or ""))
	end
	return table.concat(pieces, "|")
end

-- Only asset-backed parts survive a save and reach clients. Anything built
-- from an EditableMesh (or emptied by a save) is rebuilt.
local function isCurrent(existing: Instance, sig: string): boolean
	if existing:GetAttribute("ArtSig") ~= sig then
		return false
	end
	local parts = existing:GetDescendants()
	table.insert(parts, existing)
	for _, part in parts do
		if part:IsA("MeshPart") and part.MeshContent.SourceType ~= Enum.ContentSourceType.Uri then
			return false
		end
	end
	return true
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
	-- Always reassemble: a saved Wheel holds copies of empty tyre/hub meshes.
	local old = skins:FindFirstChild("Wheel")
	if old then
		old:Destroy()
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

	local dataFolder = ReplicatedStorage:WaitForChild("ConvoyShared"):FindFirstChild("ArtData")
	if not dataFolder then
		warn("[ArtImporter] ConvoyShared.ArtData is missing -- world will fall back to blocks")
		return false
	end

	local started = os.clock()
	local built, kept, failed = 0, 0, 0
	missingUploads = 0

	-- Loading a mesh asset waits on the network, so one item at a time took
	-- most of a minute. Load every stale item at once and wait for them all.
	local pending = 0
	local caller = coroutine.running()
	local waiting = false
	local expected: { [Instance]: { [string]: boolean } } = { [world] = {}, [skins] = { Wheel = true } }

	for _, module in dataFolder:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, loaded = pcall(require, module)
			if not ok then
				warn("[ArtImporter] could not load", module.Name, loaded)
				failed += 1
				continue
			end
			local item = loaded :: ItemData
			local target = if item.folder == "skin" then skins else world
			local sig = signature(item)
			expected[target][item.name] = true
			local existing = target:FindFirstChild(item.name)
			if existing and isCurrent(existing, sig) then
				kept += 1
				continue
			end
			pending += 1
			task.spawn(function()
				local instance = buildItem(item)
				if instance then
					instance:SetAttribute("ArtSig", sig)
					if existing then
						existing:Destroy()
					end
					instance.Parent = target
					built += 1
				else
					failed += 1
				end
				pending -= 1
				if pending == 0 and waiting then
					task.spawn(caller)
				end
			end)
		end
	end

	if pending > 0 then
		waiting = true
		coroutine.yield()
	end

	-- Drop leftovers no module builds (an earlier session saved some groups
	-- here). ArtKit looks names up recursively, so their empty parts could
	-- otherwise be found instead of the real item.
	for folder, names in expected do
		for _, child in folder:GetChildren() do
			if not names[child.Name] then
				child:Destroy()
			end
		end
	end

	assembleWheelSkin(world, skins)

	print(string.format(
		"[ArtImporter] built %d, kept %d art items (%d failed) in %.2fs -- %d world, %d skins",
		built, kept, failed, os.clock() - started, #world:GetChildren(), #skins:GetChildren()
	))
	if missingUploads > 0 then
		warn(string.format(
			"[ArtImporter] %d part(s) have no uploaded mesh and will show as placeholder boxes to players -- see tools/build_art_modules.py",
			missingUploads
		))
	end
	return built + kept > 0
end

return ArtImporter

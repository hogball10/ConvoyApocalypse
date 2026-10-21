--!strict
--[[
	Clones Blender meshes stored in ServerStorage.ConvoyArt.
	Each mesh keeps the bounding-box center it was built with so a CFrame
	places it back in the space it was modeled in.
]]

local ServerStorage = game:GetService("ServerStorage")

local ArtKit = {}

local function root(): Folder?
	local folder = ServerStorage:FindFirstChild("ConvoyArt")
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

function ArtKit.Template(name: string): Instance?
	local folder = root()
	if not folder then
		return nil
	end
	return folder:FindFirstChild(name, true)
end

function ArtKit.Place(template: Instance, cf: CFrame, anchored: boolean?): Instance
	local clone = template:Clone()
	local isAnchored = if anchored == nil then true else anchored

	local function place(part: BasePart)
		local cx = part:GetAttribute("CenterX") or 0
		local cy = part:GetAttribute("CenterY") or 0
		local cz = part:GetAttribute("CenterZ") or 0
		part.Anchored = isAnchored
		part.CanCollide = false
		part.Massless = true
		part.CastShadow = true
		part.CFrame = cf * CFrame.new(cx, cy, cz)
	end

	if clone:IsA("BasePart") then
		place(clone)
	end
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			place(desc)
		end
	end
	return clone
end

return ArtKit

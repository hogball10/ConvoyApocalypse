--!strict
--[[
	No shop screen. Click a bin block, then click the green pad to place it.
	R rotates. Right click or Q drops the held block. Click a placed block to pick it up.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local PartsCatalog = require(Shared:WaitForChild("PartsCatalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local BlockBuilder = require(Shared:WaitForChild("BlockBuilder"))
local UIUtil = require(script.Parent:WaitForChild("UIUtil"))

local player = Players.LocalPlayer

local GarageController = {}
GarageController._data = nil :: any
GarageController._inRun = false
GarageController._holdId = nil :: string?
GarageController._rot = 0
GarageController._ghost = nil :: Model?
GarageController._ghostKey = ""
GarageController._nextPlace = 0

local function myGarage(): Folder?
	local root = Workspace:FindFirstChild("Garages")
	if not root then
		return nil
	end
	for _, child in root:GetChildren() do
		if child:IsA("Folder") and child:GetAttribute("OwnerUserId") == player.UserId then
			return child
		end
	end
	return nil
end

local function currentBlocks(): { any }
	local data = GarageController._data
	if not data or typeof(data.slots) ~= "table" then
		return {}
	end
	local slot = data.slots[data.activeSlot]
	if slot and typeof(slot.blocks) == "table" then
		return slot.blocks
	end
	return {}
end

local function unplaced(partId: string): number
	local data = GarageController._data
	if not data or typeof(data.ownedParts) ~= "table" then
		return 0
	end
	local left = data.ownedParts[partId] or 0
	for _, block in currentBlocks() do
		if block.partId == partId then
			left -= 1
		end
	end
	return left
end

local inventoryPanel: Frame? = nil
local inventoryScroll: ScrollingFrame? = nil
local inventoryButton: TextButton? = nil
local holdPart: (string) -> ()

local function refreshInventory()
	if not inventoryScroll or not inventoryButton then
		return
	end
	for _, child in inventoryScroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local rows = {}
	local data = GarageController._data
	local owned = if data and typeof(data.ownedParts) == "table" then data.ownedParts else {}
	for partId, _count in owned do
		local left = unplaced(partId)
		local part = PartsCatalog.Get(partId)
		if part and left > 0 and part.category ~= "Chassis" then
			table.insert(rows, { id = partId, left = left, part = part })
		end
	end
	table.sort(rows, function(a, b)
		if a.part.category == b.part.category then
			return a.part.name < b.part.name
		end
		return a.part.category < b.part.category
	end)
	inventoryButton.Text = "INVENTORY (" .. tostring(#rows) .. ")"
	if #rows == 0 then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 0, 48)
		empty.Font = Enum.Font.GothamMedium
		empty.TextSize = 14
		empty.TextWrapped = true
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.TextColor3 = UIUtil.Colors.Muted
		empty.Text = "No parts yet. Pull a lever, then buy the one it lands on."
		empty.Parent = inventoryScroll
		return
	end
	for index, row in rows do
		local button = Instance.new("TextButton")
		button.Name = row.id
		button.LayoutOrder = index
		button.Size = UDim2.new(1, 0, 0, 40)
		button.BackgroundColor3 = if GarageController._holdId == row.id then UIUtil.Colors.AccentDim else UIUtil.Colors.PanelAlt
		button.BorderSizePixel = 0
		button.AutoButtonColor = true
		button.Text = ""
		button.Parent = inventoryScroll
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 5, 1, -8)
		stripe.Position = UDim2.fromOffset(4, 4)
		stripe.BackgroundColor3 = Constants.TIER_COLORS[row.part.tier] or UIUtil.Colors.Accent
		stripe.BorderSizePixel = 0
		stripe.Parent = button
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(16, 0)
		name.Size = UDim2.new(1, -56, 1, 0)
		name.Font = Enum.Font.GothamBold
		name.TextSize = 14
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = UIUtil.Colors.Text
		name.Text = row.part.name
		name.Parent = button
		local count = Instance.new("TextLabel")
		count.BackgroundTransparency = 1
		count.AnchorPoint = Vector2.new(1, 0)
		count.Position = UDim2.new(1, -8, 0, 0)
		count.Size = UDim2.fromOffset(36, 40)
		count.Font = Enum.Font.GothamBold
		count.TextSize = 14
		count.TextColor3 = UIUtil.Colors.Scrap
		count.Text = "x" .. tostring(row.left)
		count.Parent = button
		button.MouseButton1Click:Connect(function()
			holdPart(row.id)
			refreshInventory()
		end)
	end
end

local function buildInventory()
	local gui = UIUtil.ScreenGui("Inventory", player:WaitForChild("PlayerGui"))
	inventoryButton = UIUtil.Button({
		Name = "Toggle",
		Text = "INVENTORY (0)",
		Size = UDim2.fromOffset(180, 36),
		Position = UDim2.new(0, 16, 1, -52),
		Parent = gui,
	})
	inventoryPanel = UIUtil.Frame({
		Name = "Panel",
		Size = UDim2.fromOffset(280, 360),
		Position = UDim2.new(0, 16, 1, -424),
		Visible = false,
		Parent = gui,
	})
	UIUtil.Text({
		Name = "Title",
		Text = "INVENTORY",
		Size = UDim2.new(1, -16, 0, 28),
		Position = UDim2.fromOffset(8, 6),
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = inventoryPanel,
	})
	UIUtil.Text({
		Name = "Hint",
		Text = "Click a part, then the green pad. I toggles this.",
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(8, 32),
		TextColor3 = UIUtil.Colors.Muted,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = inventoryPanel,
	})
	inventoryScroll = UIUtil.Scroll({
		Name = "List",
		Size = UDim2.new(1, -16, 1, -62),
		Position = UDim2.fromOffset(8, 54),
		Parent = inventoryPanel,
	})
	inventoryButton.MouseButton1Click:Connect(function()
		if inventoryPanel then
			inventoryPanel.Visible = not inventoryPanel.Visible
		end
	end)
	refreshInventory()
end

local function writeLabel(name: string, text: string, color: Color3?)
	local garage = myGarage()
	if not garage then
		return
	end
	local label = garage:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") then
		label.Text = text
		if color then
			label.TextColor3 = color
		end
	end
end

holdPart = function(partId: string)
	GarageController._holdId = partId
	GarageController._rot = 0
	GarageController._ghostKey = ""
	local part = PartsCatalog.Get(partId)
	writeLabel("MessageReadout", "Holding " .. (part and part.name or partId) .. ". Click the green pad.", Color3.fromRGB(255, 186, 90))
end

local function clearGhost()
	if GarageController._ghost then
		GarageController._ghost:Destroy()
		GarageController._ghost = nil
	end
	GarageController._ghostKey = ""
end

local function clearHold()
	GarageController._holdId = nil
	GarageController._rot = 0
	clearGhost()
end

local function originOf(garage: Folder): CFrame
	return CFrame.new(
		garage:GetAttribute("BuildX") :: number,
		garage:GetAttribute("BuildY") :: number,
		garage:GetAttribute("BuildZ") :: number
	)
end

local function raycast(): RaycastResult?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local unit = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	if GarageController._ghost then
		table.insert(exclude, GarageController._ghost)
	end
	if player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude
	return Workspace:Raycast(unit.Origin, unit.Direction * 500, params)
end

local function snap(coord: number, extent: number): number
	local minEdge = math.round(coord - extent / 2)
	return minEdge + extent / 2
end

local function placementAt(hit: RaycastResult): (number?, number?, number?)
	local garage = myGarage()
	local partId = GarageController._holdId
	if not garage or not partId then
		return nil
	end
	local size = PartsCatalog.BlockSize(partId, GarageController._rot)
	local localHit = originOf(garage):PointToObjectSpace(hit.Position)
	local x = math.round(snap(localHit.X, size.X))
	local z = math.round(snap(localHit.Z, size.Z))
	local inst = hit.Instance
	local onPad = inst.Name == "BuildPlate" or inst.Name == "PadStud" or inst:GetAttribute("IsBuildPad") == true
	if onPad then
		return x, 0, z
	end
	local model = inst:FindFirstAncestorOfClass("Model")
	local gridY = inst:GetAttribute("GridY")
	local underId = inst:GetAttribute("PartId")
	local underRot = inst:GetAttribute("Rot")
	if model then
		if typeof(gridY) ~= "number" then
			gridY = model:GetAttribute("GridY")
		end
		if typeof(underId) ~= "string" then
			underId = model:GetAttribute("PartId")
		end
		if typeof(underRot) ~= "number" then
			underRot = model:GetAttribute("Rot")
		end
	end
	if typeof(gridY) ~= "number" or typeof(underId) ~= "string" or typeof(underRot) ~= "number" then
		return nil
	end
	local underSize = PartsCatalog.BlockSize(underId, underRot)
	return x, math.round(gridY + underSize.Y), z
end

local function legal(partId: string, x: number, y: number, z: number, rot: number): boolean
	local block = { partId = partId, x = x, y = y, z = z, rot = rot }
	if not PartsCatalog.BlockInBounds(block) then
		return false
	end
	for _, other in currentBlocks() do
		if PartsCatalog.BlocksOverlap(block, other) then
			return false
		end
	end
	return PartsCatalog.BlockSupported(block, currentBlocks())
end

local function showGhost(x: number, y: number, z: number, ok: boolean)
	local garage = myGarage()
	local partId = GarageController._holdId
	if not garage or not partId then
		clearGhost()
		return
	end
	local key = string.format("%s_%d_%d_%d_%d_%s", partId, GarageController._rot, x, y, z, tostring(ok))
	if GarageController._ghost and GarageController._ghostKey == key then
		return
	end
	clearGhost()
	local turned = PartsCatalog.BlockSize(partId, GarageController._rot)
	local cf = originOf(garage) * CFrame.new(x, y + turned.Y / 2, z) * CFrame.Angles(0, math.rad(GarageController._rot), 0)
	local ghost = BlockBuilder.Create(partId, cf)
	ghost.Name = "BlockGhost"
	for _, desc in ghost:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.CanQuery = false
			desc.Transparency = 0.45
			if not ok then
				desc.Color = Color3.fromRGB(190, 40, 40)
			end
		end
	end
	local host = ghost.PrimaryPart
	if host then
		local bill = Instance.new("BillboardGui")
		bill.Size = UDim2.fromOffset(160, 32)
		bill.StudsOffset = Vector3.new(0, 2.2, 0)
		bill.AlwaysOnTop = true
		bill.Parent = host
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 0.3
		text.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.TextColor3 = if ok then Color3.fromRGB(230, 230, 230) else Color3.fromRGB(255, 120, 120)
		local def = PartsCatalog.Get(partId)
		text.Text = if def then def.name else partId
		text.Parent = bill
	end
	ghost.Parent = garage
	GarageController._ghost = ghost
	GarageController._ghostKey = key
end

local function refreshScrap()
	local data = GarageController._data
	if not data then
		return
	end
	writeLabel("ScrapReadout", "Scrap  " .. tostring(data.scrap), Color3.fromRGB(255, 196, 80))
	local partId = GarageController._holdId
	if partId and unplaced(partId) <= 0 then
		clearHold()
	end
end

local function binIdFrom(inst: Instance): string?
	local id = inst:GetAttribute("BinPartId")
	if typeof(id) == "string" then
		return id
	end
	local model = inst:FindFirstAncestorOfClass("Model")
	if model then
		local modelId = model:GetAttribute("BinPartId")
		if typeof(modelId) == "string" then
			return modelId
		end
	end
	return nil
end

local function placedModel(inst: Instance): Model?
	local garage = myGarage()
	if not garage then
		return nil
	end
	local preview = garage:FindFirstChild("PreviewVehicle")
	if not preview then
		return nil
	end
	local model = inst:FindFirstAncestorOfClass("Model")
	if model and model:IsDescendantOf(preview) and typeof(model:GetAttribute("BlockIndex")) == "number" then
		return model
	end
	if inst:IsDescendantOf(preview) and typeof(inst:GetAttribute("BlockIndex")) == "number" then
		local parentModel = inst.Parent
		if parentModel and parentModel:IsA("Model") then
			return parentModel
		end
	end
	return nil
end

function GarageController.SetInRun(inRun: boolean)
	GarageController._inRun = inRun
	if inRun then
		clearHold()
	end
	local gui = player.PlayerGui:FindFirstChild("Inventory")
	if gui and gui:IsA("ScreenGui") then
		gui.Enabled = not inRun
	end
end

function GarageController.Init()
	Remotes.Init()
	buildInventory()

	Remotes.Event("DataUpdated").OnClientEvent:Connect(function(data)
		GarageController._data = data
		refreshScrap()
		refreshInventory()
	end)

	Remotes.Event("Notification").OnClientEvent:Connect(function(message: string)
		writeLabel("MessageReadout", tostring(message), Color3.fromRGB(230, 230, 235))
	end)

	Remotes.Event("LeverResult").OnClientEvent:Connect(function(result)
		local tier = tostring(result.tier or "")
		local color = Constants.TIER_COLORS[tier] or Color3.fromRGB(255, 220, 120)
		writeLabel("MessageReadout", tier .. "  " .. tostring(result.name) .. "  — added to inventory", color)
		local gui = player.PlayerGui:FindFirstChild("Inventory")
		local panel = gui and gui:FindFirstChild("Panel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = true
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.I and not processed and not GarageController._inRun then
			if inventoryPanel then
				inventoryPanel.Visible = not inventoryPanel.Visible
			end
			return
		end
		if GarageController._inRun or processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.R and GarageController._holdId then
			GarageController._rot = (GarageController._rot + 90) % 360
			GarageController._ghostKey = ""
			return
		end
		if input.KeyCode == Enum.KeyCode.Q or input.UserInputType == Enum.UserInputType.MouseButton2 then
			clearHold()
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local hit = raycast()
		if not hit then
			return
		end
		local picked = binIdFrom(hit.Instance)
		if picked then
			holdPart(picked)
			refreshInventory()
			return
		end
		if not GarageController._holdId then
			local model = placedModel(hit.Instance)
			if model then
				local partId = model:GetAttribute("PartId")
				local index = model:GetAttribute("BlockIndex")
				local rot = model:GetAttribute("Rot")
				if typeof(partId) == "string" and typeof(index) == "number" then
					Remotes.Event("RemoveBlock"):FireServer(index)
					GarageController._holdId = partId
					GarageController._rot = if typeof(rot) == "number" then rot else 0
					GarageController._ghostKey = ""
				end
			end
			return
		end
		if os.clock() < GarageController._nextPlace then
			return
		end
		local x, y, z = placementAt(hit)
		local partId = GarageController._holdId
		if not x or not y or not z or not partId then
			return
		end
		if not legal(partId, x, y, z, GarageController._rot) then
			writeLabel("MessageReadout", "That spot does not fit", Color3.fromRGB(255, 120, 100))
			return
		end
		GarageController._nextPlace = os.clock() + 0.2
		Remotes.Event("PlaceBlock"):FireServer(partId, x, y, z, GarageController._rot)
	end)

	RunService.RenderStepped:Connect(function()
		if GarageController._inRun or not GarageController._holdId then
			if GarageController._ghost then
				clearGhost()
			end
			return
		end
		local hit = raycast()
		if not hit then
			clearGhost()
			return
		end
		local x, y, z = placementAt(hit)
		local partId = GarageController._holdId
		if not x or not y or not z or not partId then
			clearGhost()
			return
		end
		showGhost(x, y, z, legal(partId, x, y, z, GarageController._rot))
	end)

	task.spawn(function()
		local data = Remotes.Function("GetPlayerData"):InvokeServer()
		if data then
			GarageController._data = data
			refreshScrap()
		end
	end)
end

return GarageController


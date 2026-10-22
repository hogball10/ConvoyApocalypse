--!strict
--[[
	Creates / returns RemoteEvents and RemoteFunctions under ReplicatedStorage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local FOLDER_NAME = "ConvoyRemotes"

local EVENT_NAMES = {
	"DataUpdated",
	"EquipPart",
	"UnlockPart",
	"SelectSlot",
	"StartRun",
	"JoinRun",
	"LeaveRun",
	"RunState",
	"VehicleInput",
	"ReturnToGarage",
	"BuyBoost",
	"FireWeapon",
	"TradeRequest",
	"TradeUpdate",
	"TradeRespond",
	"TradeConfirm",
	"TradeCancel",
	"Notification",
	"EnterGarage",
	"JoinGarage",
	"LeverResult",
	"SelectLeverTarget",
	"LeverTarget",
	"PlaceBlock",
	"RemoveBlock",
}

local FUNCTION_NAMES = {
	"GetPlayerData",
	"GetGarageOccupants",
}

local function getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

function Remotes.Init()
	local folder = getFolder()
	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTION_NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.Get(name: string): Instance
	local folder = getFolder()
	local remote = folder:WaitForChild(name, 10)
	assert(remote, "Missing remote: " .. name)
	return remote
end

function Remotes.Event(name: string): RemoteEvent
	return Remotes.Get(name) :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return Remotes.Get(name) :: RemoteFunction
end

return Remotes

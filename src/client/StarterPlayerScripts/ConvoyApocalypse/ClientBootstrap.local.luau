--!strict
--[[
	Client entry. Boots garage UI + run HUD.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Remotes = require(Shared:WaitForChild("Remotes"))
Remotes.Init()

local GarageController = require(script.Parent:WaitForChild("GarageController"))
local RunHUD = require(script.Parent:WaitForChild("RunHUD"))
local VehicleControls = require(script.Parent:WaitForChild("VehicleControls"))

GarageController.Init()

VehicleControls.Init()

RunHUD.Init(function()
	GarageController.SetInRun(false)
	RunHUD.Hide()
	-- The run is over: get out of the wasteland.
	Remotes.Event("ReturnToGarage"):FireServer()
end)

-- Fired whenever the server puts this player in a garage, including after a run.
Remotes.Event("EnterGarage").OnClientEvent:Connect(function()
	VehicleControls.SetActive(false)
	GarageController.SetInRun(false)
	RunHUD.Hide()
end)

Remotes.Event("RunState").OnClientEvent:Connect(function(state)
	if state.active then
		GarageController.SetInRun(true)
		VehicleControls.SetActive(true)
	elseif state.ended then
		VehicleControls.SetActive(false)
		-- Keep HUD end panel; garage returns on button
	end
end)

print("[ConvoyApocalypse] Client ready")

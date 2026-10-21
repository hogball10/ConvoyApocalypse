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

GarageController.Init()

RunHUD.Init(function()
	GarageController.SetInRun(false)
	RunHUD.Hide()
end)

Remotes.Event("RunState").OnClientEvent:Connect(function(state)
	if state.active then
		GarageController.SetInRun(true)
	elseif state.ended then
		-- Keep HUD end panel; garage returns on button
	end
end)

print("[ConvoyApocalypse] Client ready")
